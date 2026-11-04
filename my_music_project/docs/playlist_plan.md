# Kế hoạch thêm tính năng Playlist

## Tổng quan

Thêm tính năng playlist vào app nhạc hiện tại:
- Horizontal playlist list nằm phía trên danh sách bài hát (SongsPage)
- Mặc định có playlist "Yêu thích" (hiển thị các bài hát được yêu thích)
- Thêm tab Playlists vào vị trí thứ 2 trong bottom navigation
- PlaylistsPage: AppBar (tìm kiếm, more option), danh sách playlist, FAB thêm playlist
- Khi nhấn vào 1 playlist → quay về màn hình songs, hiển thị bài hát trong list đó + cập nhật `current_playlist` trong Isar

---

## 1. Tầng Data — Isar Model

### Tạo `lib/data/models/playlist_record.dart`

```dart
@collection
class PlaylistRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String id;          // UUID

  late String name;
  late List<String> songPaths;  // danh sách path bài hát trong playlist
  late int createdAt;
  int? updatedAt;
  bool isDefault = false;  // true cho playlist "Yêu thích"
}
```

### Cập nhật `lib/data/services/isar_storage_service.dart`

Thêm `PlaylistRecordSchema` vào `Isar.open()`.

> ⚠️ Thêm schema mới → cần xóa DB cũ hoặc tăng schema version (dev thì xóa app data).

---

## 2. Tầng Data — Service & Repository

### Tạo `lib/data/services/playlist_cache_service.dart`

- `getPlaylists()` → lấy tất cả playlist từ Isar
- `createPlaylist(name)` → tạo mới
- `deletePlaylist(id)`
- `addSongToPlaylist(playlistId, songPath)`
- `removeSongFromPlaylist(playlistId, songPath)`
- `setCurrentPlaylistId(playlistId)` → lưu vào AppSettingRecord với key `current_playlist`
- `getCurrentPlaylistId()` → đọc từ AppSettingRecord
- `initDefaultPlaylists()` → tạo playlist "Yêu thích" nếu chưa tồn tại

### Tạo `lib/data/repositories/playlist_repository.dart`

Implement interface `PlaylistRepository`.

---

## 3. Tầng Domain

### Tạo `lib/domain/entities/playlist.dart`

```dart
class Playlist {
  final String id;
  final String name;
  final List<String> songPaths;
  final bool isDefault;
  final int createdAt;
  final int? updatedAt;
}
```

### Tạo `lib/domain/repositories/playlist_repository.dart`

```dart
abstract class PlaylistRepository {
  Future<List<Playlist>> getPlaylists();
  Future<Playlist> createPlaylist(String name);
  Future<void> deletePlaylist(String id);
  Future<void> addSong(String playlistId, Song song);
  Future<void> removeSong(String playlistId, String songPath);
  Future<String?> getCurrentPlaylistId();
  Future<void> setCurrentPlaylistId(String? id);
  Future<void> initDefaultPlaylists();
}
```

### Tạo `lib/domain/usecases/playlist_usecases.dart`

- `loadPlaylists()`
- `createPlaylist(name)`
- `deletePlaylist(id)`
- `addSongToPlaylist(playlistId, song)`
- `removeSongFromPlaylist(playlistId, songPath)`
- `selectPlaylist(playlistId)` → set current_playlist + lọc songs → gọi `PlaybackUseCases.setPlaylist(filteredSongs)`
- `clearPlaylistSelection()` → quay lại "All songs"
- `getFavoriteSongs(allSongs)` → lọc songs có `isFavorite == true`

---

## 4. Tầng Presentation — Providers

### Tạo `lib/presentation/providers/playlist_provider.dart`

```dart
class PlaylistState {
  final List<Playlist> playlists;
  final String? currentPlaylistId;  // null = "All songs"
  final bool isLoading;
  final String? errorMessage;
}

class PlaylistNotifier extends StateNotifier<PlaylistState> {
  // loadPlaylists, createPlaylist, deletePlaylist,
  // addSong, removeSong, selectPlaylist, clearSelection
}
```

---

## 5. Tầng Presentation — UI

### 5.1 Horizontal Playlist List trên SongsPage

Thêm widget vào đầu SongsPage (phía trên filter bar):

```
┌──────────────────────────────────────────────┐
│ [Tất cả] [❤️ Yêu thích] [Chill] [Workout]  │  ← horizontal scroll
├──────────────────────────────────────────────┤
│  12 bài hát                    [Sắp xếp ▼]  │
├──────────────────────────────────────────────┤
│  🎵 Song 1                                   │
│  🎵 Song 2                                   │
│  ...                                         │
└──────────────────────────────────────────────┘
```

- Chip "Tất cả" active mặc định (currentPlaylistId == null)
- Chọn playlist → filter songs theo songPaths
- Playlist "Yêu thích" → filter songs theo `isFavorite == true`

### 5.2 PlaylistPage (tab thứ 2 trong BottomNav)

```
┌──────────────────────────────────────────────┐
│  AppBar: [🔍 Tìm kiếm]          [⋮ More]    │
├──────────────────────────────────────────────┤
│  ❤️ Yêu thích          5 bài hát      ▶     │
│  🎵 Chill Vibes         12 bài hát     ▶     │
│  🎵 Workout             8 bài hát      ▶     │
│  ...                                         │
├──────────────────────────────────────────────┤
│                              [+ FAB]         │
└──────────────────────────────────────────────┘
```

- **AppBar**: TextField tìm kiếm playlist + IconButton more option
- **Body**: ListView các playlist (tên, số bài, icon)
- **FAB**: Mở dialog tạo playlist mới (nhập tên)
- **Tap playlist** → chuyển tab về SongsPage (index 0) + set `currentPlaylistId`

### 5.3 Cập nhật HomePage — Bottom Navigation

```dart
IndexedStack(
  children: const [
    SongsPage(),
    PlaylistPage(),   // vị trí thứ 2
    MorePage(),
  ],
)

BottomNavigationBar items: [
  Songs (music_note),
  Playlists (playlist_play),  // thêm mới
  More (more_horiz),
]
```

---

## 6. Flow chính

### Flow khi chọn playlist (từ PlaylistPage)

```
PlaylistPage → user tap "Chill Vibes"
  → PlaylistNotifier.selectPlaylist("chill-vibes")
    → PlaylistRepository.setCurrentPlaylistId("chill-vibes")  // lưu Isar
    → Lọc songs từ musicProvider.songs theo songPaths
    → PlaybackUseCases.setPlaylist(filteredSongs)  // update player
    → state.currentPlaylistId = "chill-vibes"
  → HomePage: chuyển tab về SongsPage (index 0)
  → SongsPage hiển thị chỉ songs trong playlist đó
```

### Flow playlist "Yêu thích"

- Tự động tạo khi init app (trong PlaylistCacheService.initDefaultPlaylists)
- Songs lấy bằng filter `isFavorite == true` từ allSongs (không cần lưu songPaths riêng)
- Khi user toggle favorite → playlist "Yêu thích" tự cập nhật (reactive)

### Flow khi tắt/mở lại app

```
SplashPage → init
  → PlaylistCacheService.initDefaultPlaylists()
  → PlaylistCacheService.getCurrentPlaylistId()
  → Nếu có currentPlaylistId:
    → Load songs + filter theo playlist
    → PlaybackUseCases.setPlaylist(filteredSongs)
  → Nếu null:
    → Load all songs bình thường
```

---

## 7. Thứ tự triển khai

| # | Action | File | Mô tả |
|---|--------|------|--------|
| 1 | Tạo | `lib/data/models/playlist_record.dart` | Isar model cho playlist |
| 2 | Sửa | `lib/data/services/isar_storage_service.dart` | Thêm PlaylistRecordSchema |
| 3 | Tạo | `lib/data/services/playlist_cache_service.dart` | CRUD playlist trong Isar |
| 4 | Tạo | `lib/domain/entities/playlist.dart` | Entity playlist |
| 5 | Tạo | `lib/domain/repositories/playlist_repository.dart` | Abstract interface |
| 6 | Tạo | `lib/data/repositories/playlist_repository.dart` | Implementation |
| 7 | Tạo | `lib/domain/usecases/playlist_usecases.dart` | Business logic |
| 8 | Sửa | `lib/di/app_providers.dart` | Thêm playlist providers |
| 9 | Tạo | `lib/presentation/providers/playlist_provider.dart` | State management |
| 10 | Sửa | `lib/presentation/pages/playlist/playlist_page.dart` | Implement full UI |
| 11 | Tạo | `lib/presentation/widgets/playlist_horizontal_list.dart` | Widget chip list |
| 12 | Sửa | `lib/presentation/pages/songs/songs_page.dart` | Thêm horizontal list + filter logic |
| 13 | Sửa | `lib/presentation/pages/home_page.dart` | Uncomment playlist tab |
| 14 | Sửa | `lib/presentation/pages/splash/splash_page.dart` | Init default playlists |

---

## 8. Reconcile Playlist khi Scan

Vì playlist lưu `songPaths`, khi user đổi tên/di chuyển file thì path cũ sẽ invalid.

### Giải pháp: Sync playlist mỗi lần scan device

Thêm logic reconcile trong `LoadSongsUseCase` hoặc `PlaylistUseCases` sau khi scan xong:

```dart
Future<void> reconcilePlaylists(List<Song> scannedSongs) async {
  final validPaths = scannedSongs.map((s) => s.path).toSet();
  final playlists = await _playlistRepository.getPlaylists();

  for (final playlist in playlists) {
    if (playlist.isDefault) continue; // "Yêu thích" không cần vì filter dynamic

    final originalCount = playlist.songPaths.length;
    final updatedPaths = <String>[];

    for (final path in playlist.songPaths) {
      if (validPaths.contains(path)) {
        // Path vẫn còn tồn tại → giữ lại
        updatedPaths.add(path);
      } else {
        // Path không còn → thử match bằng metadata (duration + size)
        // để phát hiện file bị rename
        final matchedSong = _tryMatchRenamed(path, scannedSongs, cachedSongs);
        if (matchedSong != null) {
          updatedPaths.add(matchedSong.path); // update sang path mới
        }
        // Nếu không match được → loại bỏ (file đã bị xóa thật)
      }
    }

    if (updatedPaths.length != originalCount) {
      await _playlistRepository.updateSongPaths(playlist.id, updatedPaths);
    }
  }
}

/// Match file bị rename bằng duration + size + dateModified
Song? _tryMatchRenamed(String oldPath, List<Song> scannedSongs, List<Song> cachedSongs) {
  final cachedSong = cachedSongs.firstWhereOrNull((s) => s.path == oldPath);
  if (cachedSong == null) return null;

  // Tìm bài mới có cùng duration + size nhưng path khác
  // và path mới chưa tồn tại trong cache (= file mới xuất hiện)
  final cachedPaths = cachedSongs.map((s) => s.path).toSet();

  return scannedSongs.firstWhereOrNull((s) =>
    s.duration == cachedSong.duration &&
    s.size == cachedSong.size &&
    !cachedPaths.contains(s.path) // path mới, chưa có trong cache cũ
  );
}
```

### Thời điểm chạy reconcile

```
LoadSongsUseCase.loadLibrary()
  → load cache
  → scan device
  → reconcilePlaylists(scannedSongs)  ← thêm bước này
  → save cache
  → set playlist
```

### Tóm tắt logic

| Trường hợp | Xử lý |
|-------------|--------|
| File vẫn còn (path match) | Giữ nguyên |
| File bị rename (match duration + size) | Update path mới trong playlist |
| File bị xóa thật (không match được) | Loại khỏi playlist |

---

## 9. Lưu ý

- Playlist "Yêu thích" là playlist đặc biệt: `isDefault = true`, không xóa được, songs lọc dynamic theo `isFavorite`.
- Các playlist khác lưu `songPaths` cứng trong Isar.
- Field `current_playlist` lưu trong `AppSettingRecord` (key-value) để restore khi mở lại app.
- Khi `currentPlaylistId != null`, player foreground service sẽ phát playlist đã filter (không phải toàn bộ library).
- Reconcile playlist chạy mỗi lần scan → đảm bảo playlist luôn đồng bộ với file thực tế trên device.


---

## 10. Flow tạo Playlist mới — Chọn bài hát

### Mô tả

Khi user nhấn FAB (+) tạo playlist:
1. Hiện dialog nhập tên playlist → nhấn "Tạo"
2. Sau khi tạo thành công → navigate tới **SongPickerPage** (full screen)
3. SongPickerPage hiển thị toàn bộ bài hát với checkbox để chọn nhiều bài
4. Có thanh tìm kiếm phía trên để filter bài hát theo tên
5. Có nút "Xong" (hoặc FAB) để xác nhận → thêm các bài đã chọn vào playlist vừa tạo

### UI SongPickerPage

```
┌──────────────────────────────────────────────┐
│  AppBar: [←] Thêm bài hát       [Xong (3)]  │
├──────────────────────────────────────────────┤
│  [🔍 Tìm kiếm bài hát...]                   │
├──────────────────────────────────────────────┤
│  ☐ Song A                        3:45        │
│  ☑ Song B                        4:12        │
│  ☑ Song C                        2:58        │
│  ☐ Song D                        5:01        │
│  ☑ Song E                        3:22        │
│  ...                                         │
└──────────────────────────────────────────────┘
```

- Mỗi item hiển thị: checkbox + title + duration
- Checkbox multi-select
- Nút "Xong" trên AppBar hiển thị số bài đã chọn
- Có thể dùng lại cho cả trường hợp "Thêm bài vào playlist đã tồn tại"

### Thứ tự triển khai

| # | Action | File | Mô tả |
|---|--------|------|--------|
| 1 | Tạo | `lib/presentation/pages/playlist/song_picker_page.dart` | Full screen page chọn bài hát |
| 2 | Sửa | `lib/presentation/pages/playlist/playlist_page.dart` | Sau tạo playlist → navigate tới SongPickerPage |
| 3 | Sửa | `lib/l10n/app_en.arb` | Thêm keys: `addSongs`, `done`, `searchSongsToAdd`, `selectedCount` |
| 4 | Sửa | `lib/l10n/app_vi.arb` | Thêm translations VI |
| 5 | Chạy | `flutter gen-l10n` | Generate lại l10n |

### Flow chi tiết

```
PlaylistPage → FAB (+) → Dialog nhập tên
  → "Tạo" → playlistProvider.createPlaylist(name)
  → Navigator.push(SongPickerPage(playlistId: newPlaylist.id))
  → User chọn bài hát (multi-select) + tìm kiếm
  → "Xong" → playlistProvider.addSongToPlaylist(id, path) cho mỗi bài
  → Navigator.pop() → về PlaylistPage (playlist đã có bài hát)
```

### Tái sử dụng

SongPickerPage nhận param `playlistId` → có thể dùng lại khi:
- Tạo playlist mới (sau dialog tên)
- Thêm bài vào playlist đã tồn tại (từ menu option của playlist)

### Lưu ý

- Nếu playlist đã có bài → hiển thị bài đó đã checked sẵn (pre-selected)
- Tìm kiếm filter real-time theo title (giống SearchPage hiện tại)
- Không giới hạn số bài chọn
