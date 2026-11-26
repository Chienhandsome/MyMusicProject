# Download server

FastAPI `GET /mp3?url=...`, trả MP3 128 kbps. Image chứa Python 3.12,
yt-dlp/EJS, Node.js 22 và FFmpeg. Chạy 1 worker, 1 replica.

## Khởi chạy trên Windows

Cần Docker Desktop đang chạy với Linux containers. Từ thư mục Flutter:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ../download_server/start.ps1
```

Script tạo admin key ngẫu nhiên lần đầu trong `.secrets/admin_api_key`, rồi build
và chạy Compose. Các lần chạy tiếp theo giữ nguyên key. Key được mount read-only
qua Docker secret, không đóng vào image hoặc in ra console. Không cần Firebase
để test bằng admin key. Script có thể chạy từ thư mục bất kỳ bằng đường dẫn đầy đủ.

Sau lần tạo key đầu tiên, vẫn có thể dùng lệnh Compose thông thường:

```powershell
docker compose -f ../download_server/compose.yaml up --build -d
```

Linux/macOS: từ `download_server`, tạo key trước khi chạy Compose:

```sh
mkdir -p .secrets
# Chỉ chạy dòng tạo key ở lần đầu, tránh ghi đè key đang dùng.
(umask 077; openssl rand -hex 32 > .secrets/admin_api_key)
docker compose up --build -d
```

## Test trực tiếp bằng admin key

Từ thư mục Flutter:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ../download_server/test-download.ps1 -Url "https://www.youtube.com/watch?v=VIDEO_ID" -Output audio.mp3
```

Script đọc key từ file local, gửi bằng header Authorization và lưu MP3 vào đường
dẫn `-Output` (mặc định thư mục hiện tại). Server remote dùng tham số
`-ApiBaseUrl https://api.example.com`; script chỉ cho HTTP khi gọi loopback.

Hoặc từ bất kỳ thư mục nào dùng curl:

```powershell
$key = (Get-Content -Raw 'D:\FlutterProject\MyMuSicProject\download_server\.secrets\admin_api_key').Trim()
$url = 'https://www.youtube.com/watch?v=VIDEO_ID'
curl.exe --get 'http://localhost:8000/mp3' -H "Authorization: Bearer $key" --data-urlencode "url=$url" --output audio.mp3 --fail-with-body
```

Không đặt key trong URL, Flutter, Git, ảnh chụp hoặc log. Người giữ key có quyền
gọi trực tiếp; muốn chỉ riêng bạn truy cập, giữ key trên máy của mình. Admin vẫn
chịu cùng hàng chờ, timeout và giới hạn video. Đổi key bằng:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ../download_server/start.ps1 -RotateAdminKey
```

Script recreate container để mount key mới; key cũ hết hiệu lực cho yêu cầu mới.

Swagger: http://localhost:8000/docs → Authorize → nhập key vào AdminKey (không
thêm chữ Bearer). `/docs` và `/openapi.json` public để kiểm tra server; `/mp3`
luôn yêu cầu xác thực. Gọi không kèm credential phải nhận HTTP 401:

```powershell
curl.exe -i --get 'http://localhost:8000/mp3' --data-urlencode 'url=https://example.com/video'
```

## App Check cho Pocket Music (chưa cấu hình mặc định)

Nhánh app chỉ bật khi có cả `FIREBASE_PROJECT_NUMBER` và `FIREBASE_APP_IDS`.
Không đặt hai giá trị này: chỉ admin key được chấp nhận; không có chế độ public.

1. Tạo Firebase project và đăng ký app Android `com.pocketaudio.player` (và app
   iOS nếu phát hành), cấu hình Play Integrity/App Attest trong Firebase App Check.
2. Copy `.env.example` thành `.env` trong `download_server`. Điền **Project number
   dạng số**, không phải Project ID dạng chữ. Điền Firebase App ID dạng
   `1:123456789:android:...`; nhiều App ID phân cách bằng dấu phẩy. Đây là mã
   định danh công khai, không phải secret.
3. Tích hợp `firebase_core` và `firebase_app_check` vào Flutter, khởi tạo Firebase
   rồi activate App Check. Khi gọi API, lấy App Check token và gửi header
   `X-Firebase-AppCheck: TOKEN`. Không gửi admin key từ ứng dụng.
4. Chạy lại `start.ps1` hoặc Compose để áp dụng `.env`.

Backend dùng PyJWT/cryptography để xác minh RS256 với public JWKS của Google:
kiểm tra chữ ký, JWT header, issuer chính xác, audience/project number, iat/exp,
và subject thuộc allowlist App ID. Cache public keys tối đa 6 giờ; timeout tải key
5 giây và tối đa 2 lần xác minh song song. Không cần service-account private key
cho cách xác minh JWT này. Không nhận key URL từ token. Lỗi xác minh luôn từ chối.

Admin credential qua Authorization được ưu tiên: nếu gửi header này nhưng sai,
request bị từ chối ngay dù có App Check token. Khi gọi từ app, chỉ gửi App Check.
Đây là token bearer thông thường, có thể tái sử dụng đến khi hết hạn; chưa triển
khai token dùng một lần, xác thực người dùng hoặc quota theo tài khoản. App Check
giảm lạm dụng, không bảo đảm chặn mọi cách giả mạo. Không bật debug provider cho
bản phát hành; phải cân nhắc cách phát hành Google Play/APK khi cấu hình policy.

Tài liệu chính thức:
- https://firebase.google.com/docs/app-check/custom-resource-backend
- https://firebase.google.com/docs/app-check/flutter/default-providers

## Giới hạn xử lý

| Mục | Giới hạn |
| --- | --- |
| Video | Thời lượng biết trước, lớn hơn 0 và nhỏ hơn 420 giây |
| Livestream | Từ chối cả đang live, sắp phát và bản ghi đã live |
| Xử lý đồng thời | 1 tác vụ: metadata → tải → chuyển đổi |
| Chờ | 2 tác vụ; đầy trả HTTP 429 và Retry-After: 10 |
| Timeout | 180 giây từ lúc bắt đầu xử lý, không tính thời gian chờ; HTTP 504 |
| MP3 | Luôn encode lại 128 kbps; gần 7 phút khoảng 6,7 MB thập phân |
| Container Compose | 384 MiB RAM, 0,75 CPU |
| File tạm | Xóa sau gửi kể cả gửi lỗi; lỗi xử lý được dọn ngay |
| File sót | Quét mỗi 60 giây và lúc khởi động, xóa file cũ hơn 15 phút; giữ file đang dùng |

Timeout/cancellation dừng cả process group trong Linux container. Hàng chờ nằm
trong bộ nhớ, không tồn tại qua restart. File đang gửi không chiếm slot xử lý.
Volume `downloads` chỉ chứa file tạm. Dừng đột ngột: file sót đủ tuổi được dọn ở
lần chạy sau. Không scale nhiều worker/replica nếu chưa có hàng chờ dùng chung.

HTTP 400: URL/video bị từ chối hoặc tải/chuyển đổi lỗi. HTTP 401: thiếu/sai/hết hạn
credential. HTTP 403: app không nằm trong allowlist hoặc App Check chưa cấu hình.
HTTP 429: hàng chờ hoặc slot xác minh bận. HTTP 503: không tải được public keys
thiếu executable hoặc file cookie được cấu hình không đọc được/sai header Netscape. HTTP 504: tác vụ xử lý quá 180 giây.

## Deploy và vận hành

Build context là `download_server`, Dockerfile là `Dockerfile`. Uvicorn bind
`0.0.0.0`, biến `PORT` mặc định 8000. Mount secret rồi đặt `ADMIN_API_KEY_FILE`,
hoặc dùng secret environment `ADMIN_API_KEY` (ít nhất 32 byte). Không cấu hình
cùng lúc cả hai. Thiếu tất cả cơ chế xác thực hoặc cấu hình dở dang: không startup.
Trên nền tảng khác, tự đặt RAM/CPU tương đương Compose. Dùng HTTPS khi public API;
HTTP trong ví dụ chỉ để test local hoặc qua SSH tunnel. Không tắt kiểm tra TLS của client.

```sh
docker compose ps
docker compose logs -f
docker stats
docker compose down
```

Chạy các lệnh trên trong `download_server`, hoặc thêm `-f` tương ứng.
`down -v` xóa cả volume file tạm. Để cập nhật yt-dlp:

```sh
docker compose build --pull --no-cache
docker compose up -d
```

BuildKit cache pip nằm ngoài image; sửa main/auth không làm cài lại dependencies.
Build kiểm tra executable và import Python. Base tags/dependencies chưa khóa
bằng digest/lockfile nên build mới ở thời điểm khác có thể lấy phiên bản khác.

## Kiểm thử backend

Từ `download_server`, Python >= 3.12:

```sh
python -m pip install -r requirements.txt httpx
python -m unittest discover -s tests -v
```

Test dùng admin key giả và RSA key giả lập trong bộ nhớ, không dùng secret thật
hoặc gọi Firebase/YouTube. Bao gồm JWT sai chữ ký/project/app/hết hạn, thiếu key,
fail-closed, auth trước hàng chờ, 1 chạy/2 chờ/429, timeout, dọn file và FFmpeg thực
ở 128 kbps (bỏ qua test FFmpeg nếu chưa cài).


## Cookie file trên Docker / Oracle

Mã hỗ trợ `YTDLP_COOKIES_FILE`, ưu tiên hơn `YTDLP_COOKIES_BROWSER`. File nguồn
được copy riêng cho từng tác vụ; metadata và audio cùng dùng `--cookies` trỏ tới
bản sao có quyền ghi. Cookie gốc có thể mount chỉ đọc; bản sao bị dọn cùng file
MP3 khi xong/lỗi/timeout. Cookie nguồn không được sửa hoặc đưa vào image.

Xem [ORACLE_COOKIES.md](ORACLE_COOKIES.md) để export/upload cookie, đặt quyền cho
UID 10001, rebuild riêng backend và test qua SSH tunnel Windows cổng 8001.
Cấu hình opt-in: `docker compose -f compose.yaml -f compose.cookies.yaml ...`.
Base Compose không yêu cầu cookie và mặc định chỉ publish `127.0.0.1:8000`.
Không dùng `start.ps1` (chỉ base Compose) để recreate khi muốn giữ cookie bật;
hãy dùng lệnh có cả hai file Compose trong hướng dẫn Oracle.
Cookie có thể hết hạn và không bảo đảm vượt qua mọi trường hợp YouTube chặn IP.

## Tên file theo tiêu đề YouTube

Backend trả `Content-Disposition` với tên `<tiêu đề video>.mp3`, giữ tiếng Việt
và Unicode. Ký tự không hợp lệ trên Windows được thay thế, tên quá dài được rút
ngắn, tên thiếu/rỗng dùng `audio.mp3`. Tên file tạm nội bộ vẫn cố định trong thư
mục riêng từng tác vụ để bảo đảm cleanup; không dùng title làm đường dẫn server.

Client cần dùng tên từ header. `Invoke-WebRequest -OutFile audio.mp3` hoặc
`curl -o audio.mp3` luôn ghi đè tên lưu bằng tên bạn chỉ định. Script
`test-download.ps1` đã hỗ trợ lấy tên từ header (kể cả filename* UTF-8); bỏ tham
số `-Output` để dùng tên YouTube. Tên trùng có hậu tố `(1)`, `(2)` để tránh ghi đè.
Vẫn có thể truyền `-Output` khi muốn đặt tên riêng.

Test Oracle qua SSH tunnel 8001, từ PowerShell Windows (script sẽ hỏi key Oracle,
không dùng nhầm key local):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File 'D:\FlutterProject\MyMuSicProject\download_server\test-download.ps1' `
  -ApiBaseUrl 'http://127.0.0.1:8001' -PromptForAdminKey `
  -Url 'https://www.youtube.com/watch?v=VIDEO_ID'
```

File được lưu ở thư mục PowerShell hiện tại. Key không được in ra màn hình.
Chỉ cần upload lại `yt_dlp_server/main.py` lên Oracle rồi build/recreate service
`download-server` như hướng dẫn cookie; helper PowerShell chạy trên Windows.

Hướng dẫn test từng bước trên Windows qua SSH tunnel: [TEST_DOWNLOAD.md](TEST_DOWNLOAD.md).
