import asyncio
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time
import unittest
import wave
from urllib.parse import unquote
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from cryptography.hazmat.primitives.asymmetric import rsa
import jwt

import httpx
from fastapi import HTTPException

main_path = Path(os.environ.get("DOWNLOAD_SERVER_MAIN", Path(__file__).resolve().parents[1] / "yt_dlp_server" / "main.py"))
sys.path.insert(0, str(main_path.parent))
spec = importlib.util.spec_from_file_location("download_server_main", main_path)
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class DownloadTests(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        cls.signing_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.directory_patch = patch.object(server, "DOWNLOAD_DIR", self.root)
        self.directory_patch.start()
        self.cookie_patch = patch.multiple(server, COOKIES_FILE=None, COOKIES_BROWSER=None)
        self.cookie_patch.start()
        self.auth_environment = patch.dict(os.environ, {
            "ADMIN_API_KEY": "test-only-admin-key-" + "x" * 32, "ADMIN_API_KEY_FILE": "",
            "FIREBASE_PROJECT_NUMBER": "", "FIREBASE_APP_IDS": "",
        })
        self.auth_environment.start()
        self.lifespan = server.lifespan(server.app)
        await self.lifespan.__aenter__()
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=server.app), base_url="http://test",
                                       headers={"Authorization": "Bearer " + os.environ["ADMIN_API_KEY"]})

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.lifespan.__aexit__(None, None, None)
        self.directory_patch.stop()
        self.cookie_patch.stop()
        self.auth_environment.stop()
        self.temp.cleanup()

    async def test_duration_and_livestream_boundaries(self):
        for info in [
            {"duration": 420}, {"duration": 421}, {"duration": None}, {},
            {"duration": -1}, {"duration": float("nan")}, {"duration": True},
            {"duration": 20, "is_live": True},
            {"duration": 20, "live_status": "is_upcoming"},
            {"duration": 20, "live_status": "post_live"},
            {"duration": 20, "live_status": "was_live"},
            {"duration": 20, "was_live": True},
            {"_type": "playlist", "duration": 20},
        ]:
            with self.subTest(info=info), self.assertRaises(HTTPException) as error:
                server.validate_metadata(info)
            self.assertEqual(error.exception.status_code, 400)
        server.validate_metadata({"duration": 419.99})

    async def test_youtube_title_becomes_unicode_attachment_name(self):
        title = "Bài hát yêu thích 🎵"
        async def fake_run(args, capture=False):
            if capture:
                return json.dumps({"duration": 120, "title": title}).encode()
            if args[0] == "yt-dlp":
                output = Path(args[args.index("-o") + 1])
                (output.parent / "source.webm").write_bytes(b"source")
            else:
                output = Path(args[-1])
                self.assertEqual(output.name, "audio.mp3")
                output.write_bytes(b"mp3")
        with patch.object(server, "run_process", fake_run):
            response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
        self.assertEqual(response.status_code, 200)
        header = response.headers["content-disposition"]
        self.assertTrue(header.startswith("attachment; filename*=utf-8''"))
        self.assertEqual(unquote(header.split("''", 1)[1]), title + ".mp3")
        self.assertEqual(response.content, b"mp3")
        self.assertEqual(list(self.root.iterdir()), [])

    async def test_attachment_filename_is_portable_and_bounded(self):
        self.assertEqual(server.download_filename(None), "audio.mp3")
        self.assertEqual(server.download_filename(" ... "), "audio.mp3")
        self.assertEqual(server.download_filename("Tên bài.mp3"), "Tên bài.mp3")
        for title in ['../../track\\name:bad?*<>|"\r\nInjected: value', "CON", "NUL.txt", "COM¹", "Á" * 400]:
            with self.subTest(title=title[:20]):
                filename = server.download_filename(title)
                self.assertTrue(filename.endswith(".mp3"))
                self.assertLessEqual(len(filename.encode("utf-8")), 185)
                self.assertFalse(any(c in filename for c in '<>:"/\\|?*\r\n'))
                self.assertFalse(filename.startswith("."))
                self.assertNotIn(filename.split(".")[0].upper(), {"CON", "NUL", "COM¹"})

    async def test_cookie_copy_is_shared_by_both_steps_and_removed_after_send(self):
        with tempfile.TemporaryDirectory() as secret_dir:
            source = Path(secret_dir) / "youtube.cookies.txt"
            source.write_bytes(b"# Netscape HTTP Cookie File\n")
            commands = []
            copies = []
            async def fake_run(args, capture=False):
                commands.append(args)
                if args[0] == "yt-dlp":
                    self.assertNotIn("--cookies-from-browser", args)
                    cookie = Path(args[args.index("--cookies") + 1])
                    copies.append(cookie)
                    self.assertNotEqual(cookie, source)
                    self.assertEqual(cookie.parent.parent, self.root)
                    if os.name == "posix":
                        self.assertEqual(cookie.stat().st_mode & 0o777, 0o600)
                    if capture:
                        # Simulate yt-dlp updating the jar during metadata extraction.
                        cookie.write_bytes(b"# Netscape HTTP Cookie File\n# updated by metadata\n")
                        return b'{"duration": 120}'
                    self.assertIn(b"# updated by metadata", cookie.read_bytes())
                    (cookie.parent / "source.webm").write_bytes(b"audio")
                else:
                    Path(args[-1]).write_bytes(b"mp3")
            with patch.object(server, "COOKIES_FILE", str(source)), patch.object(server, "COOKIES_BROWSER", "chrome"), patch.object(server, "run_process", fake_run):
                response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(len(commands), 3)
            self.assertEqual(copies[0], copies[1])
            self.assertFalse(copies[0].exists())
            self.assertEqual(source.read_bytes(), b"# Netscape HTTP Cookie File\n")
            self.assertEqual(list(self.root.iterdir()), [])

    async def test_missing_cookie_file_returns_503_without_starting_process(self):
        with patch.object(server, "COOKIES_FILE", str(self.root / "missing.txt")), patch.object(server, "run_process", new_callable=AsyncMock) as run:
            response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["detail"], "Configured cookie file could not be prepared")
        run.assert_not_awaited()
        self.assertEqual(list(self.root.iterdir()), [])

    async def test_unreadable_cookie_file_returns_generic_503(self):
        with patch.object(server, "COOKIES_FILE", "secret-path"), patch.object(server.shutil, "copyfile", side_effect=PermissionError("sensitive error")), patch.object(server, "run_process", new_callable=AsyncMock) as run:
            response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("sensitive", response.text)
        self.assertNotIn("secret-path", response.text)
        run.assert_not_awaited()
        self.assertEqual(list(self.root.iterdir()), [])

    async def test_invalid_cookie_format_is_rejected_and_copy_is_removed(self):
        with tempfile.TemporaryDirectory() as secret_dir:
            source = Path(secret_dir) / "bad.cookies.txt"
            source.write_bytes(b"not a Netscape cookie jar\n")
            with patch.object(server, "COOKIES_FILE", str(source)), patch.object(server, "run_process", new_callable=AsyncMock) as run:
                response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
            self.assertEqual(response.status_code, 503)
            run.assert_not_awaited()
            self.assertTrue(source.exists())
            self.assertEqual(list(self.root.iterdir()), [])

    async def test_cookie_copy_is_removed_after_download_error_or_timeout(self):
        for timeout in [False, True]:
            with self.subTest(timeout=timeout), tempfile.TemporaryDirectory() as secret_dir:
                source = Path(secret_dir) / "youtube.cookies.txt"
                source.write_bytes(b"# Netscape HTTP Cookie File\n")
                copies = []
                async def fail_or_wait(args, capture=False):
                    cookie = Path(args[args.index("--cookies") + 1])
                    copies.append(cookie)
                    if capture:
                        return b'{"duration": 120}'
                    if timeout:
                        await asyncio.sleep(10)
                    raise HTTPException(400, "download failed")
                with patch.object(server, "COOKIES_FILE", str(source)), patch.object(server, "run_process", fail_or_wait), patch.object(server, "TASK_TIMEOUT", 0.02):
                    response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
                self.assertEqual(response.status_code, 504 if timeout else 400)
                self.assertTrue(copies)
                self.assertTrue(all(not p.exists() for p in copies))
                self.assertEqual(source.read_bytes(), b"# Netscape HTTP Cookie File\n")
                self.assertEqual(list(self.root.iterdir()), [])

    async def test_no_cookie_configuration_preserves_existing_command(self):
        command = server.ytdlp_command(server.prepare_cookie_file(self.root))
        self.assertNotIn("--cookies", command)
        self.assertNotIn("--cookies-from-browser", command)
        with patch.object(server, "COOKIES_BROWSER", "firefox"):
            command = server.ytdlp_command(server.prepare_cookie_file(self.root))
        self.assertEqual(command[command.index("--cookies-from-browser") + 1], "firefox")
        self.assertNotIn("--cookies", command)

    def app_token(self, **overrides):
        claims = {
            "iss": "https://firebaseappcheck.googleapis.com/123456",
            "aud": ["projects/123456"], "sub": "1:123456:android:pocket",
            "iat": int(time.time()) - 5, "exp": int(time.time()) + 300,
        }
        claims.update(overrides)
        return jwt.encode(claims, self.signing_key, algorithm="RS256", headers={"kid": "test-key"})

    def configure_app_auth(self):
        auth = server.DownloadAuth("test-only-admin-key-" + "x" * 32, "123456", {"1:123456:android:pocket"})
        auth.jwks.get_signing_key_from_jwt = lambda token: SimpleNamespace(key=self.signing_key.public_key())
        server.app.state.auth = auth
        self.client.headers.pop("Authorization", None)
        return auth

    async def test_unauthorized_requests_never_reach_download_queue(self):
        self.client.headers.pop("Authorization")
        attempts = [{}, {"Authorization": "Bearer wrong"}, {"Authorization": "Basic dGVzdA=="},
                    {"Authorization": "Bearer"}, {"Authorization": "Bearer " + "x" * 40}]
        with patch.object(server, "produce_mp3", new_callable=AsyncMock) as produce:
            for headers in attempts:
                response = await self.client.get("/mp3", params={"url": "https://example.com/video"}, headers=headers)
                self.assertEqual(response.status_code, 401)
            produce.assert_not_awaited()
        self.assertEqual(server.app.state.downloads.admitted, 0)
        self.assertEqual(list(self.root.iterdir()), [])
        self.assertEqual((await self.client.get("/openapi.json")).status_code, 200)

    async def test_app_access_disabled_until_configured(self):
        self.client.headers.pop("Authorization")
        response = await self.client.get("/mp3", params={"url": "https://example.com/video"},
                                         headers={"X-Firebase-AppCheck": "anything"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(server.app.state.downloads.admitted, 0)

    async def test_valid_signed_app_token_downloads(self):
        self.configure_app_auth()
        async def produce(url, path):
            (path / "audio.mp3").write_bytes(b"app-download")
        with patch.object(server, "produce_mp3", produce):
            response = await self.client.get("/mp3", params={"url": "https://example.com/video"},
                                             headers={"X-Firebase-AppCheck": self.app_token()})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, b"app-download")
        self.assertEqual(list(self.root.iterdir()), [])

    async def test_expired_wrong_project_and_bad_signature_are_rejected(self):
        self.configure_app_auth()
        tokens = [self.app_token(exp=int(time.time()) - 10),
                  self.app_token(aud=["projects/999"]),
                  self.app_token(iss="https://firebaseappcheck.googleapis.com/999"),
                  self.app_token(iat=int(time.time()) + 300), "not-a-jwt"]
        other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        claims = jwt.decode(self.app_token(), options={"verify_signature": False})
        tokens.append(jwt.encode(claims, other_key, algorithm="RS256", headers={"kid": "test-key"}))
        del claims["exp"]
        tokens.append(jwt.encode(claims, self.signing_key, algorithm="RS256", headers={"kid": "test-key"}))
        with patch.object(server, "produce_mp3", new_callable=AsyncMock) as produce:
            for token in tokens:
                response = await self.client.get("/mp3", params={"url": "https://example.com/video"},
                                                 headers={"X-Firebase-AppCheck": token})
                self.assertEqual(response.status_code, 401)
            produce.assert_not_awaited()

    async def test_other_registered_app_is_forbidden(self):
        self.configure_app_auth()
        response = await self.client.get("/mp3", params={"url": "https://example.com/video"},
                                         headers={"X-Firebase-AppCheck": self.app_token(sub="1:123456:android:other")})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(server.app.state.downloads.admitted, 0)

    async def test_no_auth_configuration_fails_closed(self):
        with patch.dict(os.environ, {"ADMIN_API_KEY": "", "ADMIN_API_KEY_FILE": "",
                                    "FIREBASE_PROJECT_NUMBER": "", "FIREBASE_APP_IDS": ""}):
            with self.assertRaises(ValueError):
                server.DownloadAuth.from_environment()
        for kwargs in [{"admin_key": "short"}, {"project_number": "123456"},
                       {"admin_key": "x" * 40, "project_number": "123456", "app_ids": {"1:999:android:pocket"}}]:
            with self.assertRaises(ValueError):
                server.DownloadAuth(**kwargs)

    async def test_admin_key_can_be_loaded_from_secret_file(self):
        key_file = self.root / "key"
        key_file.write_text("file-key-" + "x" * 40, encoding="utf-8")
        with patch.dict(os.environ, {"ADMIN_API_KEY": "", "ADMIN_API_KEY_FILE": str(key_file)}):
            auth = server.DownloadAuth.from_environment()
        self.assertEqual(await auth.authorize("Bearer file-key-" + "x" * 40, None), "admin")
        with self.assertRaises(HTTPException):
            await auth.authorize("Bearer incorrect", None)

    async def test_signing_key_network_failure_fails_closed(self):
        from jwt.exceptions import PyJWKClientConnectionError
        auth = self.configure_app_auth()
        with patch.object(auth.jwks, "get_signing_key_from_jwt", side_effect=PyJWKClientConnectionError("offline")):
            response = await self.client.get("/mp3", params={"url": "https://example.com/video"},
                                             headers={"X-Firebase-AppCheck": self.app_token()})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(server.app.state.downloads.admitted, 0)

    async def test_single_active_two_waiting_then_429(self):
        gate = asyncio.Event()
        running = 0
        peak = 0

        async def fake_download(url, path):
            nonlocal running, peak
            running += 1
            peak = max(peak, running)
            await gate.wait()
            await asyncio.sleep(0.01)
            (path / "audio.mp3").write_bytes(b"mp3")
            running -= 1

        with patch.object(server, "produce_mp3", fake_download):
            tasks = [asyncio.create_task(self.client.get("/mp3", params={"url": "https://example.com/video"})) for _ in range(3)]
            try:
                for _ in range(100):
                    if server.app.state.downloads.admitted == 3:
                        break
                    await asyncio.sleep(0.001)
                self.assertEqual(server.app.state.downloads.admitted, 3)
                response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
                self.assertEqual(response.status_code, 429)
                self.assertIn("retry-after", response.headers)
            finally:
                gate.set()
                responses = await asyncio.gather(*tasks)
        self.assertEqual(peak, 1)
        self.assertTrue(all(r.status_code == 200 and r.content == b"mp3" for r in responses))
        self.assertEqual(server.app.state.downloads.admitted, 0)
        self.assertEqual(list(self.root.iterdir()), [])

    async def test_timeout_cleans_partial_files(self):
        async def slow(url, path):
            (path / "source.part").write_bytes(b"partial")
            await asyncio.sleep(10)
        with patch.object(server, "produce_mp3", slow), patch.object(server, "TASK_TIMEOUT", 0.02):
            response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
        self.assertEqual(response.status_code, 504)
        self.assertEqual(server.app.state.downloads.admitted, 0)
        self.assertEqual(list(self.root.iterdir()), [])

    async def test_error_cleans_partial_files(self):
        async def fail(url, path):
            (path / "source.part").touch()
            raise HTTPException(400, "source failed")
        with patch.object(server, "produce_mp3", fail):
            response = await self.client.get("/mp3", params={"url": "https://example.com/video"})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(list(self.root.iterdir()), [])

    async def test_stale_cleanup_preserves_active_and_recent(self):
        manager = server.app.state.downloads
        for name in ["old", "active", "recent"]:
            (self.root / name).mkdir()
            (self.root / name / "audio.part").touch()
        legacy = self.root / "legacy.mp3"
        legacy.touch()
        for path in [self.root / "old", self.root / "active", legacy]:
            os.utime(path, (time.time() - 901, time.time() - 901))
        manager.active_paths.add(self.root / "active")
        manager.clean_stale()
        self.assertEqual({p.name for p in self.root.iterdir()}, {"active", "recent"})

    async def test_cancelled_waiter_releases_queue_capacity(self):
        manager = server.app.state.downloads
        entered = asyncio.Event()
        async def waiter():
            entered.set()
            async with manager.reserve():
                pass
        async with manager.reserve():
            waiting = asyncio.create_task(waiter())
            await entered.wait()
            self.assertEqual(manager.admitted, 2)
            waiting.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await waiting
            self.assertEqual(manager.admitted, 1)
        self.assertEqual(manager.admitted, 0)

    async def test_failed_send_removes_mp3(self):
        manager = server.app.state.downloads
        path = self.root / "job"
        path.mkdir()
        (path / "audio.mp3").write_bytes(b"mp3")
        manager.active_paths.add(path)
        response = server.TemporaryMP3Response(path, manager)
        async def send(message):
            raise OSError("disconnected")
        async def receive():
            return {"type": "http.disconnect"}
        with self.assertRaises(OSError):
            await response({"type": "http", "method": "GET", "headers": []}, receive, send)
        self.assertFalse(path.exists())
        self.assertNotIn(path, manager.active_paths)

    async def test_encoding_always_forces_128k_even_for_mp3_source(self):
        commands = []
        async def fake_run(args, capture=False):
            commands.append(args)
            if capture:
                return json.dumps({"duration": 419}).encode()
            if args[0] == "yt-dlp":
                (self.root / "source.mp3").write_bytes(b"source")
            else:
                (self.root / "audio.mp3").write_bytes(b"encoded")
        with patch.object(server, "run_process", fake_run):
            await server.produce_mp3("https://example.com/video", self.root)
        self.assertEqual(commands[2][0], "ffmpeg")
        self.assertEqual(commands[2][commands[2].index("-b:a") + 1], "128k")
        self.assertIn("!is_live & duration < 420", commands[1])

    async def test_rejected_metadata_never_downloads(self):
        commands = []
        async def fake_run(args, capture=False):
            commands.append(args)
            return b'{"duration": 420}'
        with patch.object(server, "run_process", fake_run), self.assertRaises(HTTPException):
            await server.produce_mp3("https://example.com/video", self.root)
        self.assertEqual(len(commands), 1)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg is not installed")
    async def test_real_ffmpeg_output_is_128_kbps(self):
        original = server.run_process
        async def source_or_encode(args, capture=False):
            if args[0] != "yt-dlp":
                return await original(args, capture=capture)
            if capture:
                return b'{"duration": 1}'
            with wave.open(str(self.root / "source.wav"), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(44100)
                wav.writeframes(b"\x00\x00" * 44100)
        with patch.object(server, "run_process", source_or_encode):
            await server.produce_mp3("https://example.com/video", self.root)
        info = await original([
            "ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
            "stream=bit_rate,codec_name", "-of", "json", str(self.root / "audio.mp3"),
        ], capture=True)
        stream = json.loads(info)["streams"][0]
        self.assertEqual(stream["codec_name"], "mp3")
        self.assertEqual(stream["bit_rate"], "128000")

    async def test_invalid_url_does_not_enter_queue(self):
        for url in ["file:///etc/passwd", "--version", "https://[invalid"]:
            response = await self.client.get("/mp3", params={"url": url})
            self.assertEqual(response.status_code, 400)
        self.assertEqual(server.app.state.downloads.admitted, 0)

    async def test_real_subprocess_is_stopped_on_timeout(self):
        # Run a real child to verify cancellation waits for process termination.
        created = []
        original = asyncio.create_subprocess_exec
        async def track(*args, **kwargs):
            process = await original(*args, **kwargs)
            if args[0] == sys.executable:
                created.append(process)
            return process
        with patch.object(server.asyncio, "create_subprocess_exec", track):
            with self.assertRaises(TimeoutError):
                async with asyncio.timeout(0.3):
                    await server.run_process([sys.executable, "-c", "import time; time.sleep(30)"])
        self.assertEqual(len(created), 1)
        self.assertIsNotNone(created[0].returncode)


if __name__ == "__main__":
    unittest.main()
