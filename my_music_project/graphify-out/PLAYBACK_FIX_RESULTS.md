# Kết quả sửa luồng phát nhạc

Đã hoàn thành cả ba đợt sửa cho findings 2–9 trong PLAYBACK_AUDIT.md. Hành vi Next/Previous của finding 1 được giữ nguyên theo yêu cầu.

## Đợt 1 — queue và chọn bài

- PlaybackQueueUseCases đồng bộ active queue theo playlist đang chọn khi khởi động, scan, refresh, sửa hoặc xóa playlist.
- Search chuyển sang toàn thư viện và phát theo path; hàng bài hát cũng chọn/highlight theo path.
- Giữ identity, vị trí, play/pause khi queue đổi; không reload source khi các path không đổi. Nếu bài bị loại khỏi queue, chọn bài đầu ở trạng thái pause; queue rỗng thì clear current song.
- Cổng kiểm thử: 14/14 test qua, gồm 8 regression mới và 6 test load/kiến trúc.

## Đợt 2 — bất đồng bộ

- Lệnh từ UI và notification đi qua cùng hàng đợi thao tác.
- Generation và source-change guard ngăn callback/decoder error cũ ảnh hưởng lựa chọn mới, đồng thời giữ sự kiện auto-advance hợp lệ khi đang lưu mode.
- Selection playlist cũng được tuần tự hóa; refresh queue và kết quả load cũ được kiểm tra revision.
- Cổng kiểm thử: 13/13 regression test tại thời điểm kết thúc đợt.

## Đợt 3 — trạng thái, lỗi và hết bài

- Provider lấy trạng thái phát từ stream engine, hỗ trợ loading/buffering và lỗi; không gán playing=true dựa vào command completion.
- Lỗi decoder/native được chuyển lên UI với thông báo Việt/Anh; notification play/pause/stop/seek cũng qua use case.
- Ghi lượt phát sau tín hiệu playing + ready, không chờ play future kết thúc; kết quả lỗi cũ được bỏ qua.
- Clear bài khi stream gửi null; cập nhật lại UI và queue khi bỏ yêu thích trong Favorites.
- Bỏ dừng sớm duration−300ms; dừng ở completion/loop boundary khi phát tiếp tắt.
- Mode được rollback nếu lưu thất bại; mapping native loop/shuffle không đổi.

## Kiểm chứng cuối

- Toàn bộ Flutter suite: **78/78 passed** (41 test mới gồm domain, provider, service và tích hợp UI).
- Widget test thao tác thực: nhập Search, tap kết quả, kiểm tra chuyển selection/queue và metadata đúng bài.
- Analyzer các file Dart sửa/thêm: không có vấn đề sau khi dọn style.
- git diff --check: không có lỗi whitespace.
- pubspec.lock không đổi; dependencies được khôi phục để chạy Flutter tests.
- Kết quả runner: playback_test_results.txt.

Chạy lại: `flutter test --no-pub`.

Giới hạn: native AudioPlayer được giả lập trong unit/integration tests. Chưa phát âm thanh trên Android/iOS thật; cần smoke test thiết bị cho audio focus, notification lifecycle và thời điểm loop/end native. Graph JSON tạo trước thay đổi này cần được cập nhật trước khi dùng để suy luận kiến trúc mới.
