import '../entities/song.dart';
import 'playback_usecases.dart';
import 'playlist_usecases.dart';

/// Owns the library-to-active-queue mapping for scans and playlist changes.
class PlaybackQueueUseCases implements LibraryPlaybackController {
  final PlaybackUseCases _playback;
  final PlaylistUseCases _playlists;
  List<Song>? _library;
  Future<void> _tail = Future<void>.value();
  int _revision = 0;

  PlaybackQueueUseCases(this._playback, this._playlists);

  @override
  Future<void> setPlaylist(List<Song> songs) async {
    _library = List.of(songs);
    await refresh();
  }

  Future<void> refresh() {
    final revision = ++_revision;
    final result = _tail.then((_) => _refresh(revision));
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> _refresh(int revision) async {
    final library = _library;
    if (library == null) return;
    final id = await _playlists.getCurrentPlaylistId();
    final selected = id == null ? null : await _playlists.getPlaylistById(id);
    if (revision != _revision) return;
    if (id != null && selected == null) {
      await _playlists.setCurrentPlaylistId(null);
    }
    await _playback.setPlaylist(selected == null
        ? library
        : _playlists.filterSongsByPlaylist(selected, library));
  }

  @override
  Song? get currentSong => _playback.currentSong;

  @override
  Future<void> stop() => _playback.stop();
}
