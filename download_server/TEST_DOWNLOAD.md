# Hướng dẫn test download Pocket Music qua SSH tunnel

Tài liệu dành cho cấu hình hiện tại:

| Thành phần | Địa chỉ |
| --- | --- |
| Oracle Ubuntu | `ubuntu@213.35.110.67` |
| Backend trên Oracle | `~/download_server`, chỉ bind `127.0.0.1:8000` |
| API trên Windows qua tunnel | `http://127.0.0.1:8001` |
| Script test trên Windows | `D:\FlutterProject\MyMuSicProject\download_server\test-download.ps1` |

Windows → cổng 8001 → kết nối SSH mã hóa → Oracle cổng 8000 → backend.
Không gọi trực tiếp `213.35.110.67:8000`. Test thông thường không cần rebuild
hay restart container. Thay `ubuntu` nếu tài khoản SSH thực tế của bạn khác.

## 1. Mở tunnel — cửa sổ PowerShell Windows số 1

Thay đường dẫn private key trong dòng đầu bằng file thật của bạn (không dùng
file `.pub`). Chạy cả khối mỗi khi mở phiên PowerShell mới:

```powershell
$sshKey = 'D:\DUONG_DAN_THAT\oracle-private.key'
$sshHost = 'ubuntu@213.35.110.67'

if (-not (Test-Path -LiteralPath $sshKey -PathType Leaf)) {
    throw 'Chưa điền đúng đường dẫn private key SSH.'
}

ssh -i "$sshKey" -o IdentitiesOnly=yes `
  -o ExitOnForwardFailure=yes -N `
  -L 127.0.0.1:8001:127.0.0.1:8000 $sshHost
```

Nếu key có passphrase, SSH sẽ hỏi passphrase. Đây là mật khẩu mở private key,
không phải admin key API.

Lệnh không báo lỗi và đứng chờ là bình thường. **Giữ cửa sổ này mở** trong suốt
thời gian test. `-N` mở tunnel mà không mở terminal Oracle để chạy lệnh.
Biến `$sshKey`, `$sshHost` chỉ tồn tại trong cửa sổ PowerShell đã khai báo chúng.

## 2. Kiểm tra tunnel — cửa sổ PowerShell Windows số 2

```powershell
curl.exe --silent --show-error --max-time 10 -o NUL -w "HTTP %{http_code}\n" `
  http://127.0.0.1:8001/openapi.json
```

Mong đợi: **HTTP 200**. Endpoint này không cần admin key. HTTP 200 xác nhận API
truy cập được, chưa xác nhận YouTube hoặc cookie tải được video.

Kiểm tra API chặn yêu cầu không có key:

```powershell
curl.exe --silent --show-error --max-time 10 -i --get `
  'http://127.0.0.1:8001/mp3' `
  --data-urlencode 'url=https://www.youtube.com/watch?v=VIDEO_ID'
```

Mong đợi: **HTTP 401**, vì thiếu credential. Chưa có tác vụ tải nào được nhận.

## 3. Tải video theo tên YouTube — vẫn ở cửa sổ số 2

Chọn một video bình thường dài 2–5 phút, không phải livestream. Thay URL bên
 dưới bằng URL thật. Không dùng chính chuỗi `VIDEO_ID` để test.

```powershell
Set-Location 'D:\DownLoad'
$url = 'https://www.youtube.com/watch?v=VIDEO_ID'

powershell -NoProfile -ExecutionPolicy Bypass `
  -File 'D:\FlutterProject\MyMuSicProject\download_server\test-download.ps1' `
  -ApiBaseUrl 'http://127.0.0.1:8001' -PromptForAdminKey `
  -Url $url
```

Khi hiện `Admin key server:`, dán **admin key của Oracle** rồi nhấn Enter.
Ký tự nhập được che; script không in key ra màn hình. Không dùng passphrase SSH
hoặc mặc định cho rằng key server giống key local Windows.

Kết quả thành công:

- Script in `Saved MP3 to ...`.
- File nằm trong `D:\DownLoad`, tên theo tiêu đề YouTube, ví dụ `Tên bài hát.mp3`.
- Tên tiếng Việt được giữ; ký tự không hợp lệ được thay thế.
- Nếu đã có file cùng tên, script thêm `(1)`, `(2)` để tránh ghi đè.

**Không thêm `-Output audio.mp3` nếu muốn tên YouTube.** Tùy chọn `-Output` dùng
khi bạn chủ động muốn đặt tên khác. Lệnh cũ `Invoke-WebRequest -OutFile audio.mp3`
cũng ép tên lưu thành `audio.mp3`, bất kể tên backend trả về.

Nếu chưa có thư mục `D:\DownLoad`, đổi sang thư mục tải về đang tồn tại của bạn.

### Admin key Oracle nằm ở đâu?

Nếu chưa có key, dùng terminal SSH Oracle đang mở, hoặc mở cửa sổ Windows khác
và SSH thông thường bằng private key của bạn. Trong terminal **Oracle**, chạy:

```bash
sudo cat ~/download_server/.secrets/admin_api_key
```

Copy giá trị để nhập vào lời nhắc trên Windows. Không gửi key trong chat, log,
ảnh chụp hoặc lưu vào tài liệu này. Không tạo/đổi key mới chỉ để test.

## 4. Kiểm tra file MP3 trên Windows

Xem các file vừa tải:

```powershell
Get-ChildItem -LiteralPath 'D:\DownLoad' -Filter '*.mp3' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 Name, Length, LastWriteTime
```

Chọn đúng tên file, đặt trong dấu nháy để hỗ trợ khoảng trắng/tiếng Việt:

```powershell
ffprobe -v error -select_streams a:0 `
  -show_entries stream=codec_name,bit_rate `
  -of json 'D:\DownLoad\TEN_FILE_VUA_TAI.mp3'
```

Mong đợi: `codec_name` là **mp3**, `bit_rate` là **128000**. Mở file bằng trình
phát nhạc để kiểm tra nghe được. Nếu máy chưa có `ffprobe`, vẫn có thể nghe thử;
chưa thể xác nhận bitrate bằng lệnh trên.

## 5. Các giới hạn cần biết khi test

| Mục | Hành vi |
| --- | --- |
| Video | Thời lượng lớn hơn 0, biết trước và **nhỏ hơn 420 giây** |
| Livestream | Từ chối cả đang live, sắp live và bản ghi đã live |
| Xử lý | 1 tác vụ chạy, tối đa 2 tác vụ chờ |
| Hàng chờ đầy | HTTP 429 |
| Timeout xử lý | 180 giây, không tính thời gian chờ; HTTP 504 |
| MP3 | 128 kbps |
| File tạm server | Xóa sau gửi/lỗi; file sót quá 15 phút được quét dọn |

Có thể thử URL video từ 7 phút trở lên để kiểm tra từ chối: chạy lại script với
URL đó, mong đợi HTTP 400 và thông báo thời lượng. Với video ngắn, script phải
tải được. Test hàng chờ đầy chỉ có ý nghĩa khi 1 tác vụ đang chạy và 2 đang chờ;
không suy luận lỗi nếu bấm nhiều lần nhưng các yêu cầu hoàn tất quá nhanh.

Tải mất khoảng 30 giây chưa đủ để xác định lỗi hiệu năng. Tổng thời gian gồm
metadata, tải nguồn, chuyển đổi FFmpeg, thời gian chờ nếu có, rồi gửi qua tunnel.
Hiện chưa có log thời gian riêng từng bước. Backend chạy giới hạn 0,75 CPU và
384 MiB RAM; máy Oracle còn chạy chung bot Capymuzi.

## 6. Tra lỗi nhanh

| Lỗi | Kiểm tra / cách xử lý |
| --- | --- |
| `Permission denied (publickey)` | Đúng private key, đúng user `ubuntu`, có `-i` và `IdentitiesOnly=yes` |
| `Identity file ... not accessible` | Điền đường dẫn file thật; khai báo lại `$sshKey` trong đúng cửa sổ |
| Cổng 8001 đã được dùng / không bind được | Có thể tunnel cũ vẫn mở; dùng tunnel đó hoặc đổi cổng local thành 8002 ở cả `-L` và `-ApiBaseUrl` |
| `Failed to connect` / HTTP 000 | Cửa sổ tunnel còn mở? SSH có lỗi? Backend Oracle còn healthy? |
| HTTP 401 | Thiếu/sai admin key; nhập key Oracle hiện tại, không phải key local |
| HTTP 403 | Nếu gọi từ app: App Check chưa cấu hình hoặc app không được phép; test cá nhân dùng admin key |
| HTTP 400, thông báo duration | Video >=420 giây hoặc không lấy được thời lượng hợp lệ |
| HTTP 400, lỗi download | Có thể YouTube/cookie/IP hoặc chuyển đổi thất bại; chưa thể kết luận chỉ từ mã 400 |
| HTTP 429 | Hàng chờ hoặc xác minh đang bận; chờ rồi thử lại |
| HTTP 503, thông báo cookie | Kiểm tra file nguồn, mount, quyền UID 10001 và header Netscape |
| HTTP 504 | Tác vụ vượt 180 giây; thử lại sau hoặc dùng video ngắn hơn |
| Vẫn tên `audio.mp3` | Bản backend mới đã deploy chưa? Có dùng `-Output`/`-OutFile audio.mp3` không? Video có thiếu tiêu đề không? |

Nếu cần kiểm tra container/log, chạy trong terminal **Oracle**:

```bash
cd ~/download_server

sudo env DOWNLOAD_SERVER_BIND_ADDRESS=127.0.0.1 DOWNLOAD_SERVER_PORT=8000 \
  docker compose -f compose.yaml -f compose.cookies.yaml ps

sudo env DOWNLOAD_SERVER_BIND_ADDRESS=127.0.0.1 DOWNLOAD_SERVER_PORT=8000 \
  docker compose -f compose.yaml -f compose.cookies.yaml logs --tail=50 download-server
```

Mong đợi trạng thái `healthy` và port `127.0.0.1:8000->8000/tcp`. Các lệnh này
chỉ xem trạng thái/log, không restart bot. Không public cổng 8000 để sửa lỗi tunnel.
Cookie có thể hết hạn hoặc YouTube vẫn chặn IP; xem [ORACLE_COOKIES.md](ORACLE_COOKIES.md)
để export/upload/làm mới cookie. Không in nội dung cookie khi chẩn đoán.

## 7. Kết thúc

Ở cửa sổ tunnel số 1, nhấn **Ctrl+C**. Chỉ tunnel đóng; backend và bot trên Oracle
vẫn chạy. Muốn test lần sau, mở lại tunnel bằng bước 1 rồi thực hiện bước 2–4.
