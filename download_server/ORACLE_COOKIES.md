# Cookie file trên Oracle Cloud Ubuntu

Backend tại `~/download_server`, dùng Docker Compose, user container UID/GID
10001, RAM 384 MiB / CPU 0,75; chạy chung host với Capymuzi. Các lệnh dưới chỉ
build/recreate service `download-server`, không dừng bot hoặc xóa volume.

## Cách cookie hoạt động

- `compose.cookies.yaml` là cấu hình **tùy chọn**. Base Compose vẫn chạy không
  cookie; overlay bật `YTDLP_COOKIES_FILE=/run/secrets/youtube_cookies.txt`.
- Cookie gốc nằm ngoài image, được bind mount chỉ đọc. Backend copy vào
  `downloads/job-.../cookies.txt` có mode `0600`, thuộc UID chạy container.
- Cả bước metadata và tải audio nhận `--cookies` với **cùng bản sao**. Cookie
  do bước metadata cập nhật được bước tải sử dụng. Khi file cookie được cấu
  hình, nó được ưu tiên hơn `YTDLP_COOKIES_BROWSER`; không dùng browser của host.
- yt-dlp có thể sửa bản sao; không ghi lên cookie gốc. Các cập nhật chỉ tồn tại
  trong tác vụ, không được lưu về host hoặc dùng cho tác vụ kế tiếp.
- Cookie tác vụ bị xóa cùng thư mục sau khi gửi MP3, khi lỗi hoặc timeout.
  Cleaner giữ nguyên cơ chế dọn file sót quá 15 phút. Cookie gốc không bị cleaner
  đụng tới. Thay cookie trên host khi hết hạn, rồi recreate container.
- File nguồn thiếu/không đọc được hoặc sai header Netscape: HTTP 503 với thông
  báo chung, không khởi chạy yt-dlp; không tự chuyển sang tải không cookie.

Các giới hạn video <420 giây, từ chối livestream, 1 chạy + 2 chờ, timeout 180 giây,
MP3 128 kbps và xác thực admin/App Check vẫn áp dụng. Port host mặc định chỉ
bind `127.0.0.1:8000`; không cần mở 8000 trên firewall Oracle.

## 1. Export trên Windows

Cookie là thông tin đăng nhập nhạy cảm. Chỉ export cookie YouTube cần thiết,
lưu dưới dạng **Mozilla/Netscape cookies.txt**, không phải JSON. Header đầu tiên
phải là `# Netscape HTTP Cookie File` hoặc `# HTTP Cookie File`. Không paste nội
dung cookie vào chat, không bật shell tracing (`set -x`), không dùng `cat` để
in cookie, không commit, không upload cả profile trình duyệt.

Theo hướng dẫn [Exporting YouTube cookies của yt-dlp](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies):

1. Mở một cửa sổ private/incognito riêng và đăng nhập YouTube.
2. Trong cùng tab, mở `https://www.youtube.com/robots.txt`; chỉ giữ tab private này.
3. Dùng công cụ export Netscape được dẫn từ [FAQ chính thức](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp)
   để export cookie `youtube.com`, ví dụ lưu `D:\DownLoad\youtube.cookies.txt`.
4. Đóng cửa sổ private sau export, không mở lại phiên đó. Không dùng cách kết hợp
   `--cookies-from-browser` và `--cookies` để export phiên incognito này.

YouTube có thể thay cookie, giới hạn tài khoản hoặc vẫn chặn IP datacenter.
Cookie không bảo đảm chữa được mọi lỗi bot/IP/PO-token. Chỉ dùng khi cần; cân nhắc
tài khoản riêng thay vì tài khoản chính theo cảnh báo trong tài liệu yt-dlp.

## 2. Upload mã nguồn đã sửa (Windows PowerShell)

Thay `ubuntu` nếu SSH user của bạn khác; dùng SSH identity/config hiện có. Không
copy đè `.env` hoặc `.secrets/admin_api_key` trên Oracle.

```powershell
$backend = 'D:\FlutterProject\MyMuSicProject\download_server'
$sshHost = 'ubuntu@213.35.110.67'
ssh $sshHost 'mkdir -p ~/download_server/yt_dlp_server'
scp "$backend\compose.yaml" "$backend\compose.cookies.yaml" "$backend\Dockerfile" "$backend\requirements.txt" "$backend\.dockerignore" "$backend\.gitignore" "$backend\.env.example" "$backend\README.md" "$backend\ORACLE_COOKIES.md" "${sshHost}:~/download_server/"
scp "$backend\yt_dlp_server\main.py" "$backend\yt_dlp_server\download_auth.py" "${sshHost}:~/download_server/yt_dlp_server/"
```

Giữ nguyên các override Compose khác nếu Oracle đang dùng; kiểm tra merged config
trước khi recreate. File mẫu `.env.example` không tự ghi đè `.env` đang chạy.

## 3. Upload cookie qua SSH và đặt quyền

Trên Windows (cookie đi qua SCP, không nằm trong Docker build):

```powershell
ssh $sshHost 'umask 077; mkdir -p ~/download_server/.secrets; chmod 700 ~/download_server/.secrets'
scp 'D:\DownLoad\youtube.cookies.txt' "${sshHost}:~/download_server/.secrets/youtube.cookies.upload"
```

Trên Oracle:

```sh
cd ~/download_server
chmod 600 .secrets/youtube.cookies.upload
sudo install -o 10001 -g 10001 -m 0400 .secrets/youtube.cookies.upload .secrets/youtube.cookies.txt
rm -- .secrets/youtube.cookies.upload
```

File cuối thuộc UID 10001 để user container đọc được; không dùng `chmod 777`.
Docker daemon resolve đường dẫn host; bind mount file trực tiếp nên container
không phải traverse thư mục `.secrets` mode 0700 trên host. Backend tạo bản sao
`0600` trong thư mục tác vụ `0700`, nên mount gốc read-only không cản yt-dlp ghi.

Mặc định source là `./.secrets/youtube.cookies.txt`. Nếu cần vị trí khác, đặt
`YTDLP_COOKIES_SOURCE=/duong/dan/tuyet/doi/youtube.cookies.txt` trong `.env`.
Đây là đường dẫn **host**; không đặt đường dẫn host vào `YTDLP_COOKIES_FILE` của
container. Không tạo `.env` mới bằng cách ghi đè cấu hình Firebase/admin hiện có.

## 4. Rebuild/recreate riêng backend

```sh
cd ~/download_server
docker compose -f compose.yaml -f compose.cookies.yaml config --quiet
docker compose -f compose.yaml -f compose.cookies.yaml up --build -d --no-deps --force-recreate download-server
docker compose -f compose.yaml -f compose.cookies.yaml ps
docker compose -f compose.yaml -f compose.cookies.yaml port download-server 8000
```

Port phải là `127.0.0.1:8000`. Cookie được thay bằng file mới có thể đổi inode;
luôn recreate sau mỗi lần upload/đổi cookie, kể cả khi code không đổi. Chỉ đổi
cookie thì bỏ `--build` cũng được. Tiếp tục dùng **cả hai `-f`** cho các lệnh
up/recreate sau này; chỉ dùng base sẽ tắt cookie. Không chạy `down -v` hoặc lệnh
dừng toàn bộ container trên host. Build mặc định tái sử dụng cache.

Nếu `.env` cũ có bind address khác, đặt `DOWNLOAD_SERVER_BIND_ADDRESS=127.0.0.1`.
Chỉ khi yt-dlp đã cũ mới cần thêm một lần cập nhật dependency (có thể tốn thêm
RAM/thời gian trên máy 1 GB):

```sh
docker compose -f compose.yaml -f compose.cookies.yaml build --pull --no-cache download-server
docker compose -f compose.yaml -f compose.cookies.yaml up -d --no-deps --force-recreate download-server
```

## 5. Kiểm tra trên Oracle, không lộ cookie

Kiểm tra UID, file nguồn đọc được, bản sao ghi được và yt-dlp load/save cookie jar.
Đoạn này không gọi YouTube, không in cookie và không thay file nguồn:

```sh
docker compose -f compose.yaml -f compose.cookies.yaml exec -T download-server python - <<'PY'
import os
import io
from contextlib import redirect_stderr
from pathlib import Path
import tempfile
from yt_dlp.cookies import YoutubeDLCookieJar
from main import prepare_cookie_file
try:
    assert os.getuid() == 10001
    source = Path(os.environ['YTDLP_COOKIES_FILE'])
    assert source.is_file() and os.access(source, os.R_OK)
    with tempfile.TemporaryDirectory(prefix='cookie-check-') as directory:
        copy = prepare_cookie_file(Path(directory))
        assert copy and copy != source
        assert copy.stat().st_mode & 0o777 == 0o600
        jar = YoutubeDLCookieJar(str(copy))
        # Some parsers warn with the bad cookie row; never echo raw warnings.
        with redirect_stderr(io.StringIO()):
            jar.load(ignore_discard=True, ignore_expires=True)
            jar.save(ignore_discard=True, ignore_expires=True)
    print('OK: UID 10001; cookie source readable; private copy load/save works')
except Exception:
    raise SystemExit('Cookie check failed; details/content suppressed') from None
PY

curl --fail --silent --output /dev/null --write-out 'schema HTTP %{http_code}\n' http://127.0.0.1:8000/openapi.json
docker compose -f compose.yaml -f compose.cookies.yaml logs --tail=30 download-server
```

Đoạn kiểm tra chặn stderr của parser vì cảnh báo có thể chứa dòng cookie lỗi;
nếu cần chia sẻ kết quả thì chỉ chia sẻ dòng OK/failure, không raw stderr.
Backend API bỏ stdout/stderr của bước tải và không trả cookie qua lỗi.

Gọi API bằng key hiện có trên Oracle, không đưa secret lên command line:

```sh
cd ~/download_server
{ printf 'Authorization: Bearer '; tr -d '\r\n' < .secrets/admin_api_key; printf '\n'; } |
  curl --header @- --get 'http://127.0.0.1:8000/mp3' \
    --data-urlencode 'url=https://www.youtube.com/watch?v=kzrPSMVcgu0' \
    --output audio.mp3 --fail-with-body --max-time 600 \
    --write-out '\nHTTP %{http_code}; total=%{time_total}s; bytes=%{size_download}\n'
```

Nếu admin key trên host chỉ root đọc được, dùng `sudo` riêng cho lệnh đọc secret
phù hợp, hoặc test qua Windows với key bạn đang giữ; không nới quyền để test.
HTTP 200 mới là thành công; khi `--fail-with-body` báo lỗi, `audio.mp3` có thể là
JSON lỗi, không phải nhạc. Video vẫn phải dưới 420 giây và không phải livestream.
HTTP 400 có thể vẫn là bot/IP block hoặc video không đạt điều kiện; cookie không
thay đổi các giới hạn. HTTP 503 cookie: kiểm tra mount, UID, quyền và định dạng.

## 6. Test từ Windows qua tunnel 8001

Mở một terminal giữ tunnel:

```powershell
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8001:127.0.0.1:8000 ubuntu@213.35.110.67
```

Terminal khác, dùng **admin key Oracle hiện có**, không giả định trùng key local:

```powershell
$oracleKey = Read-Host 'Admin key Oracle' -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential('admin', $oracleKey)
$headers = @{ Authorization = 'Bearer ' + $credential.GetNetworkCredential().Password }
$url = 'https://www.youtube.com/watch?v=kzrPSMVcgu0'
Invoke-WebRequest -Uri ('http://127.0.0.1:8001/mp3?url=' + [Uri]::EscapeDataString($url)) -Headers $headers -OutFile audio.mp3 -TimeoutSec 600
Remove-Variable oracleKey, credential, headers
ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,bit_rate -of json audio.mp3
```

MP3 thành công phải có codec `mp3`, bitrate `128000`. Không gửi request tới public
`213.35.110.67:8000`; dùng tunnel hoặc loopback Oracle như trên.

## 7. Làm mới hoặc tắt cookie

Cookie hết hạn/bị xoay: export mới, lặp bước upload/install/recreate. Bản sao bị
xóa sau mỗi tác vụ nên các cập nhật do yt-dlp ghi không được dùng như cookie lâu
dài. Nếu vẫn báo bot sau cookie mới, không thể kết luận code mount lỗi chỉ từ HTTP
400; cần phân biệt tình trạng YouTube/IP với kiểm tra file ở bước 5.

Tắt cookie: recreate chỉ bằng base Compose (không cần xóa cookie gốc):

```sh
docker compose -f compose.yaml up -d --no-deps --force-recreate download-server
```

`.gitignore` loại `.secrets` và các tên cookie phổ biến; `.dockerignore` dùng
allowlist, chỉ gửi Dockerfile/requirements/main/auth vào build. Ignore không gỡ
secret đã từng được Git track. Có thể kiểm tra mà không đọc nội dung:

```sh
git check-ignore .secrets/youtube.cookies.txt
git ls-files -- .secrets '*cookies*.txt' '*cookie*.json'
```

Lệnh `git ls-files` phải không liệt kê cookie thật. Nếu đây là thư mục deploy
upload rời không có `.git`, bỏ qua hai lệnh Git. Không đưa secret vào build args,
environment chứa nội dung, Dockerfile `COPY`, tar upload toàn thư mục hoặc log.

## Dùng tên YouTube khi test tải

Ví dụ `-OutFile audio.mp3` ở trên chủ động ép tên file local. Để tự dùng tiêu đề
YouTube, dùng helper Windows mới và không truyền `-Output`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File 'D:\FlutterProject\MyMuSicProject\download_server\test-download.ps1' `
  -ApiBaseUrl 'http://127.0.0.1:8001' -PromptForAdminKey `
  -Url 'https://www.youtube.com/watch?v=VIDEO_ID'
```

Sau khi upload lại `yt_dlp_server/main.py`, trên Oracle dùng quyền Docker hiện có:

```sh
cd ~/download_server
sudo env DOWNLOAD_SERVER_BIND_ADDRESS=127.0.0.1 DOWNLOAD_SERVER_PORT=8000 \
  docker compose -f compose.yaml -f compose.cookies.yaml \
  up --build -d --no-deps --force-recreate download-server
```
