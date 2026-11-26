import asyncio
from contextlib import asynccontextmanager, suppress
import json
import logging
import math
import os
import re
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unicodedata
from urllib.parse import urlsplit

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Security
from fastapi.responses import FileResponse
from fastapi.security import APIKeyHeader, HTTPBearer

from download_auth import DownloadAuth

MAX_DURATION = 420
MAX_WAITING = 2
TASK_TIMEOUT = 180
STALE_SECONDS = 15 * 60
DOWNLOAD_DIR = Path(os.getenv("DOWNLOAD_DIR", "downloads")).resolve()
COOKIES_BROWSER = os.getenv("YTDLP_COOKIES_BROWSER")
COOKIES_FILE = os.getenv("YTDLP_COOKIES_FILE")
JS_RUNTIME = os.getenv("YTDLP_JS_RUNTIME")
logger = logging.getLogger("uvicorn.error")


class DownloadManager:
    def __init__(self):
        self.slot = asyncio.Semaphore(1)
        self.admitted = 0
        self.active_paths = set()

    @asynccontextmanager
    async def reserve(self):
        # No await between checking and incrementing: atomic on this event loop.
        if self.admitted >= 1 + MAX_WAITING:
            raise HTTPException(429, "Download queue is full", headers={"Retry-After": "10"})
        self.admitted += 1
        try:
            async with self.slot:
                yield
        finally:
            self.admitted -= 1

    def remove(self, path):
        try:
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink(missing_ok=True)
        except OSError:
            logger.exception("Could not remove temporary download: %s", path)
        finally:
            self.active_paths.discard(path)

    def clean_stale(self):
        cutoff = time.time() - STALE_SECONDS
        for path in DOWNLOAD_DIR.iterdir():
            try:
                if path not in self.active_paths and path.lstat().st_mtime < cutoff:
                    self.remove(path)
            except FileNotFoundError:
                pass

    async def cleanup_loop(self):
        while True:
            try:
                self.clean_stale()
            except OSError:
                logger.exception("Temporary download cleanup failed")
            await asyncio.sleep(60)


@asynccontextmanager
async def lifespan(app):
    app.state.auth = DownloadAuth.from_environment()
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    app.state.downloads = DownloadManager()
    cleaner = asyncio.create_task(app.state.downloads.cleanup_loop())
    try:
        yield
    finally:
        cleaner.cancel()
        with suppress(asyncio.CancelledError):
            await cleaner


app = FastAPI(lifespan=lifespan)
admin_scheme = HTTPBearer(auto_error=False, scheme_name="AdminKey")
app_check_scheme = APIKeyHeader(name="X-Firebase-AppCheck", auto_error=False, scheme_name="AppCheck")


async def authorize_download(
    request: Request,
    _admin=Security(admin_scheme),
    app_check_token=Security(app_check_scheme),
):
    return await request.app.state.auth.authorize(request.headers.get("Authorization"), app_check_token)


class TemporaryMP3Response(FileResponse):
    def __init__(self, path, manager, filename=None):
        super().__init__(path / "audio.mp3", media_type="audio/mpeg", filename=filename or "audio.mp3")
        self.job_path = path
        self.manager = manager

    async def __call__(self, scope, receive, send):
        # Finally also runs when sending fails or the client disconnects.
        try:
            await super().__call__(scope, receive, send)
        finally:
            self.manager.remove(self.job_path)


async def run_process(args, capture=False):
    options = {"start_new_session": True} if os.name == "posix" else {
        "creationflags": subprocess.CREATE_NEW_PROCESS_GROUP
    }
    try:
        process = await asyncio.create_subprocess_exec(
            *args, stdout=asyncio.subprocess.PIPE if capture else asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL, **options,
        )
    except FileNotFoundError as exc:
        raise HTTPException(503, "Required download executable is unavailable") from exc
    try:
        output, _ = await process.communicate()
    finally:
        # Kill the whole process group, including FFmpeg, on timeout/cancellation.
        if os.name == "posix":
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
        elif process.returncode is None:
            killer = await asyncio.create_subprocess_exec(
                "taskkill", "/PID", str(process.pid), "/T", "/F",
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
            )
            await killer.wait()
        await process.wait()
    if process.returncode:
        raise HTTPException(400, "Unable to read or download this video")
    return output


def validate_metadata(info):
    if not isinstance(info, dict) or info.get("_type") in {"playlist", "multi_video"}:
        raise HTTPException(400, "Only a single video is supported")
    if (info.get("is_live") or info.get("was_live")
            or info.get("live_status") in {"is_live", "is_upcoming", "post_live", "was_live"}):
        raise HTTPException(400, "Livestreams and upcoming streams are not supported")
    duration = info.get("duration")
    if (isinstance(duration, bool) or not isinstance(duration, (int, float))
            or not math.isfinite(duration) or duration <= 0 or duration >= MAX_DURATION):
        raise HTTPException(400, "Video duration must be known and below 420 seconds")


def download_filename(title):
    """Keep Unicode titles while producing a portable, bounded attachment name."""
    title = unicodedata.normalize("NFC", title) if isinstance(title, str) else ""
    title = "".join(c for c in title if not unicodedata.category(c).startswith("C"))
    title = re.sub(r'[<>:"/\\|?*]', "_", title)
    title = " ".join(title.split()).strip(" .")
    if title.lower().endswith(".mp3"):
        title = title[:-4].rstrip(" .")
    title = title.encode("utf-8")[:180].decode("utf-8", errors="ignore").rstrip(" .") or "audio"
    reserved = {"CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"}
    reserved.update(f"{prefix}{number}" for prefix in ("COM", "LPT") for number in "123456789¹²³")
    if title.split(".")[0].upper() in reserved:
        title = "_" + title
    return title + ".mp3"


def prepare_cookie_file(path):
    """Copy the host secret into this job so yt-dlp can update its own jar."""
    if not COOKIES_FILE:
        return None
    cookie_file = path / "cookies.txt"
    try:
        # The job directory is private (mkdtemp mode 0700); the copy belongs to
        # the container user, even when the mounted source is read-only.
        shutil.copyfile(COOKIES_FILE, cookie_file)
        cookie_file.chmod(0o600)
        with cookie_file.open("rb") as source:
            header = source.readline(128).strip()
        if header not in {b"# Netscape HTTP Cookie File", b"# HTTP Cookie File"}:
            raise HTTPException(503, "Configured cookie file must use Netscape format")
    except OSError:
        # Do not expose paths, cookie contents or OS exception text to clients/logs.
        raise HTTPException(503, "Configured cookie file could not be prepared") from None
    return cookie_file


def ytdlp_command(cookie_file=None):
    command = ["yt-dlp", "--ignore-config", "--no-playlist", "--no-warnings",
               "--socket-timeout", "15", "--retries", "2", "--fragment-retries", "2"]
    if cookie_file is not None:
        command.extend(["--cookies", str(cookie_file)])
    elif COOKIES_BROWSER:
        command.extend(["--cookies-from-browser", COOKIES_BROWSER])
    if JS_RUNTIME:
        command.extend(["--js-runtimes", JS_RUNTIME])
    return command


async def produce_mp3(url, path):
    cookie_file = prepare_cookie_file(path)
    command = ytdlp_command(cookie_file)
    raw = await run_process(command + ["--dump-single-json", "--skip-download", "--", url], capture=True)
    try:
        info = json.loads(raw)
    except (ValueError, TypeError) as exc:
        raise HTTPException(400, "Unable to read video metadata") from exc
    validate_metadata(info)
    await run_process(command + [
        "--match-filters", "!is_live & duration < 420",
        "-f", "bestaudio/best",
        "--concurrent-fragments", "1", "--no-progress",
        "-o", str(path / "source.%(ext)s"), "--", url,
    ])
    sources = [p for p in path.glob("source.*") if p.is_file() and p.suffix not in {".part", ".ytdl"}]
    if len(sources) != 1:
        raise HTTPException(400, "No single audio source produced")
    # Always encode, including when the input is already MP3 at another bitrate.
    await run_process([
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-threads", "1", "-i", str(sources[0]), "-map", "0:a:0", "-vn",
        "-codec:a", "libmp3lame", "-b:a", "128k", "-threads", "1", str(path / "audio.mp3"),
    ])
    if not (path / "audio.mp3").is_file():
        raise HTTPException(400, "No MP3 produced; the source may have been rejected")
    return download_filename(info.get("title"))


@app.get("/mp3", response_class=FileResponse, dependencies=[Depends(authorize_download)])
async def download_mp3(url: str = Query(...)):
    try:
        parsed = urlsplit(url)
        valid = parsed.scheme in {"http", "https"} and bool(parsed.hostname)
    except ValueError:
        valid = False
    if not valid:
        raise HTTPException(400, "A valid HTTP(S) video URL is required")
    manager = app.state.downloads
    async with manager.reserve():
        path = Path(tempfile.mkdtemp(prefix="job-", dir=DOWNLOAD_DIR))
        manager.active_paths.add(path)
        try:
            # Queue waiting time is excluded; metadata + download + conversion share one deadline.
            async with asyncio.timeout(TASK_TIMEOUT):
                filename = await produce_mp3(url, path)
            return TemporaryMP3Response(path, manager, filename)
        except TimeoutError as exc:
            manager.remove(path)
            raise HTTPException(504, "Download exceeded the 180-second time limit") from exc
        except BaseException:
            manager.remove(path)
            raise
