# Rà soát luồng phát nhạc — 2026-11-02

Phạm vi: chọn bài, Play/Pause, Next/Previous (UI và notification), hết bài, sequential/repeat/shuffle, phát tiếp, thay queue, refresh/scan, playlist con và tìm kiếm.

Không chỉnh code ứng dụng. Dùng graph để định vị, sau đó xác minh trực tiếp source. Chạy 7 characterization probes trên code domain thực với AudioRepository/PreferencesRepository giả lập; cả 7 tái hiện hành vi lỗi. Đây không phải kiểm thử audio native trên thiết bị. Flutter test suite chưa chạy được: lệnh `flutter --version` không trả kết quả trong phiên này; package_config cũng tham chiếu PubCache không tồn tại. Đã dừng lệnh chờ và dùng Dart SDK trực tiếp.

## Findings

### 1. [P1] Next/Previous không chuyển bài khi repeat hoặc tắt phát tiếp

`lib/data/services/audio_player_service.dart:94`, `:103`, `:120`, `:124`.

Hai trường hợp trên đặt LoopMode.one, trong khi Next/Previous gọi trực tiếp seekToNext/seekToPrevious. just_audio 0.9.46 tính nextIndex và previousIndex bằng chính currentIndex khi LoopMode.one. Sau khi queue được load, nút chuyển bài chỉ seek về đầu bài hiện tại; cả notification chịu ảnh hưởng. Khi queue chưa load, fallback tự tính index trong PlaybackUseCases lại có thể chuyển bài, tạo hành vi không nhất quán.

Xác minh qua source thư viện đúng phiên bản trong pubspec.lock: https://github.com/ryanheise/just_audio/blob/just_audio-v0.9.46/just_audio/lib/just_audio.dart#L492 và #L1119.

Sửa: tách chuyển bài chủ động khỏi loop tự động; tính index kế/trước theo thứ tự queue hoặc shuffle rồi seekToIndex.

### 2. [P1] UI và player không cùng queue sau scan hoặc thay nội dung playlist

`lib/domain/usecases/load_songs_usecase.dart:34`, `:48`, `:68`; `lib/presentation/providers/playlist_provider.dart:93`, `:114`, `:123`, `:159`.

Load/scan/delete file luôn đưa toàn bộ thư viện vào player, không áp dụng playlist đang chọn. Ngược lại thêm/xóa bài khỏi playlist chỉ refresh state, không sync player; xóa playlist đang chọn cũng không sync lại queue. Khi khởi động, loadPlaylists khôi phục bộ lọc nhưng loadLibrary vẫn nạp queue toàn bộ. SongsPage tính index theo danh sách đã lọc nên có thể phát nhầm bài, Next đi ra ngoài playlist, hoặc vẫn phát bài vừa bỏ khỏi playlist.

Xác minh tĩnh xuyên các call site; chưa kiểm thử UI/native. Sửa: một nơi sở hữu active queue và đồng bộ từ cùng danh sách khi scan, selection và mutation thay đổi.

### 3. [P1] Search dùng index toàn thư viện để phát playlist con

`lib/presentation/pages/search/search_page.dart:334`, `:349`, `:236`; `lib/presentation/widgets/song_item.dart:82`.

Ví dụ toàn thư viện [A,B,C], player đang có [B,C]. Search B truyền index 1, player phát C. Search C truyền index 2 ngoài queue, domain bỏ qua; notifier vẫn có thể gán isPlaying=true. SearchPage còn dùng ref.read nên highlight không tự cập nhật theo playback.

Đã tái hiện sai index với code domain thật và cùng phép ánh xạ index của UI. Sửa: chọn bằng path/id và xác định rõ queue khi phát kết quả tìm kiếm.

### 4. [P1] Refresh/đổi queue đổi bài đang phát và mất vị trí

`lib/domain/usecases/playback_usecases.dart:84`, `:99`, `:248`.

setPlaylist giữ _currentIndex, không giữ identity bài hiện tại. Ví dụ đang B ở index 1 trong [A,B,C], đổi thành [C,A,B] thì chuyển thành A. _restoreLastSong bỏ qua vì index đã khác -1. Kể cả danh sách không đổi, setAudioSource được gọi lại không truyền position cũ nên phát lại từ đầu. Xóa một bài đứng trước bài hiện tại cũng làm lệch identity.

Hai probe riêng đã tái hiện. Sửa: snapshot path, position, playing; remap index theo path và chỉ thay source khi cần.

### 5. [P1] Callback cuối bài cũ có thể pause bài mới

`lib/domain/usecases/playback_usecases.dart:64`, `:302`, `:333`.

Các handler stop cuối bài chờ Duration.zero rồi seek/pause mà không kiểm tra bài hoặc phiên phát còn hiện hành. Người dùng chọn bài mới trong lúc callback chờ sẽ bị seek về đầu/pause bài mới. _blockAutoAdvance còn có thể khôi phục index cũ.

Đã tái hiện callback completed của A làm B vừa chọn bị pause. Sửa: kiểm tra generation/token và identity sau mỗi await; vô hiệu hóa tác vụ cuối bài cũ khi có lệnh mới.

### 6. [P1] Lệnh chọn bài chồng nhau để lại metadata/lastSong sai

`lib/domain/usecases/playback_usecases.dart:122`, `:138`, `:140`.

Không có serialization hoặc operation token. Một lệnh A chờ ghi preferences; lệnh B hoàn thành; sau đó A tiếp tục ghi metadata A và phát, trong khi index/currentSong đã là B. Lock của SongItem không bao trùm nút skip, notification và callback player.

Probe dùng Completer tái hiện: currentSong/player index = B nhưng metadata và saved path = A. Sửa: tuần tự hóa mutation queue/index và bỏ kết quả của thao tác cũ.

### 7. [P1] UI báo đang phát khi play lỗi hoặc không có bài

`lib/domain/usecases/playback_usecases.dart:145`, `:153`; `lib/presentation/providers/audio_provider.dart:92`, `:101`, `:124`.

_startPlayback nuốt lỗi; AudioNotifier tự gán isPlaying=true sau play/playSongAt/Next/Previous. Không có xác nhận decoder bắt đầu phát. Một lỗi file/decoder có thể trả thành công, không báo lỗi và UI hiện nút pause. Gọi play khi currentSong=null cũng trả thành công; notifier vẫn đặt true. Thống kê tăng trước khi play thành công.

Probe đã tái hiện decoder giả lập lỗi nhưng playSongAt trả thành công, play count tăng, audio không phát. Sửa: lấy trạng thái từ player stream, mô hình hóa loading/error, chuyển lỗi đến UI; không await toàn bộ play future như một tín hiệu 'đã bắt đầu' vì future của just_audio kết thúc khi phát dừng/pause/complete.

### 8. [P2] Queue rỗng nhưng mini-player vẫn giữ bài cũ

`lib/presentation/providers/audio_provider.dart:42`, `:73`.

Stream phát null nhưng copyWith giữ this.currentSong nếu không truyền clearCurrentSong. Các caller scan/playlist gọi thẳng usecase, không qua AudioNotifier.setPlaylist có xử lý clear. Chọn playlist rỗng/xóa bài cuối vì vậy có thể để title cũ và currentIndex=-1.

Xác minh tĩnh. Sửa: clearCurrentSong: song == null trong stream listener hoặc nullable sentinel rõ ràng.

### 9. [P2] Tắt phát tiếp cắt đuôi bài và làm seek cuối bài bị dừng

`lib/domain/usecases/playback_usecases.dart:339`, `:346`.

Position >= duration - 300ms lập tức seek 0 và pause, dù chưa hết audio. Với track 10 giây, probe tại 9.8 giây đã dừng; bài rất ngắn bị ảnh hưởng mạnh hơn. Seek đến 200ms cuối lúc đang phát cũng kích hoạt hành vi này.

Đã tái hiện. Sửa: dựa trên sự kiện kết thúc, không dùng ngưỡng position để thay thế completion; xử lý loop/end thống nhất cùng mục 1 và 5.

## Ma trận mode hiện tại

| Phát tiếp | Mode | Native loop/shuffle | Next/Previous sau khi load |
|---|---|---|---|
| Tắt | Bất kỳ | one / shuffle off | Quay đầu chính bài hiện tại: lỗi #1 |
| Bật | Repeat | one / shuffle off | Quay đầu chính bài hiện tại: lỗi #1 |
| Bật | Sequential | all / shuffle off | Theo queue, vòng về đầu ở cuối |
| Bật | Shuffle | all / shuffle on | Theo thứ tự shuffle |

Sequential đang có nghĩa đi theo thứ tự và lặp toàn queue; nếu sản phẩm muốn dừng ở cuối danh sách thì cần chốt lại yêu cầu này. Chưa kết luận đây là lỗi.

## Chạy lại probes

`C:\flutter\src\flutter\bin\cache\dart-sdk\bin\dart.exe graphify-out/playback_audit.dart`

7/7 in REPRODUCED nghĩa là xác nhận defect hiện tại, không phải 7 kiểm thử hành vi đúng. Các probe không giả lập native decoder, thứ tự stream native đầy đủ hay audio focus/notification lifecycle. Cần thêm kiểm thử thiết bị cho hết bài, đổi mode sát cuối bài, thao tác skip nhanh, file hỏng và gián đoạn âm thanh.
