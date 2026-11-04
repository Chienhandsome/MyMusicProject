import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/app_providers.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/song.dart';
import '../../domain/usecases/playback_queue_usecases.dart';
import '../../domain/usecases/playlist_usecases.dart';
import 'music_provider.dart';

class PlaylistState {
  final List<Playlist> playlists;
  final String? currentPlaylistId;
  final bool isLoading;
  final String? errorMessage;

  const PlaylistState({
    this.playlists = const [],
    this.currentPlaylistId,
    this.isLoading = false,
    this.errorMessage,
  });

  PlaylistState copyWith({
    List<Playlist>? playlists,
    String? currentPlaylistId,
    bool? isLoading,
    String? errorMessage,
    bool clearPlaylistId = false,
    bool clearError = false,
  }) {
    return PlaylistState(
      playlists: playlists ?? this.playlists,
      currentPlaylistId: clearPlaylistId
          ? null
          : (currentPlaylistId ?? this.currentPlaylistId),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Playlist? get currentPlaylist {
    if (currentPlaylistId == null) return null;
    try {
      return playlists.firstWhere((p) => p.id == currentPlaylistId);
    } catch (_) {
      return null;
    }
  }
}

class PlaylistNotifier extends StateNotifier<PlaylistState> {
  final PlaylistUseCases _playlistUseCases;
  final PlaybackQueueUseCases _queue;
  Future<void> _selectionTail = Future<void>.value();
  int _selectionRevision = 0;
  int _loadRevision = 0;

  PlaylistNotifier(
    this._playlistUseCases,
    this._queue,
  ) : super(const PlaylistState());

  Future<void> loadPlaylists() async {
    final loadRevision = ++_loadRevision;
    final selectionRevision = _selectionRevision;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final playlists = await _playlistUseCases.loadPlaylists();
      var currentId = await _playlistUseCases.getCurrentPlaylistId();
      if (!mounted ||
          loadRevision != _loadRevision ||
          selectionRevision != _selectionRevision) {
        return;
      }
      if (currentId != null &&
          !playlists.any((playlist) => playlist.id == currentId)) {
        await _playlistUseCases.setCurrentPlaylistId(null);
        currentId = null;
      }
      state = state.copyWith(
        playlists: playlists,
        currentPlaylistId: currentId,
        isLoading: false,
        clearError: true,
        clearPlaylistId: currentId == null,
      );
      await _queue.refresh();
    } catch (e) {
      if (!mounted || loadRevision != _loadRevision) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load playlists: $e',
      );
    }
  }

  Future<void> createPlaylist(String name) async {
    try {
      final playlist = await _playlistUseCases.createPlaylist(name);
      state = state.copyWith(
        playlists: [...state.playlists, playlist],
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to create playlist: $e');
    }
  }

  Future<void> deletePlaylist(String id) async {
    try {
      await _playlistUseCases.deletePlaylist(id);
      final updatedPlaylists =
          state.playlists.where((p) => p.id != id).toList();

      final clearCurrent = state.currentPlaylistId == id;
      if (clearCurrent) {
        await _playlistUseCases.setCurrentPlaylistId(null);
      }

      state = state.copyWith(
        playlists: updatedPlaylists,
        clearPlaylistId: clearCurrent,
        clearError: true,
      );
      await _queue.refresh();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete playlist: $e');
    }
  }

  Future<void> addSongToPlaylist(String playlistId, String songPath) async {
    try {
      await _playlistUseCases.addSongToPlaylist(playlistId, songPath);
      await _refreshPlaylist(playlistId);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to add song: $e');
    }
  }

  Future<void> removeSongFromPlaylist(
      String playlistId, String songPath) async {
    try {
      await _playlistUseCases.removeSongFromPlaylist(playlistId, songPath);
      await _refreshPlaylist(playlistId);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to remove song: $e');
    }
  }

  Future<void> selectPlaylist(String playlistId) => _select(playlistId);

  Future<void> clearSelection() => _select(null);

  Future<void> _select(String? id) {
    _selectionRevision++;
    final result = _selectionTail.then((_) async {
      await _playlistUseCases.setCurrentPlaylistId(id);
      if (!mounted) return;
      state = state.copyWith(
          currentPlaylistId: id, clearPlaylistId: id == null, isLoading: false);
      await _syncAudioPlaylist();
    });
    _selectionTail = result.catchError((Object _) {});
    return result;
  }

  /// Lọc songs theo playlist hiện tại
  List<Song> filterSongs(List<Song> allSongs) {
    final playlist = state.currentPlaylist;
    if (playlist == null) return allSongs;
    return _playlistUseCases.filterSongsByPlaylist(playlist, allSongs);
  }

  /// Đồng bộ audio player playlist với playlist đang chọn
  Future<void> _syncAudioPlaylist() async {
    await _queue.refresh();
  }

  Future<void> _refreshPlaylist(String playlistId) async {
    final updated = await _playlistUseCases.getPlaylistById(playlistId);
    if (updated == null) return;

    final playlists = state.playlists.map((p) {
      return p.id == playlistId ? updated : p;
    }).toList();

    state = state.copyWith(playlists: playlists);
    await _queue.refresh();
  }
}

final playlistProvider =
    StateNotifierProvider<PlaylistNotifier, PlaylistState>((ref) {
  final notifier = PlaylistNotifier(
    ref.watch(playlistUseCasesProvider),
    ref.watch(playbackQueueUseCasesProvider),
  );
  ref.listen(musicProvider.select((state) => state.songs), (_, __) {
    notifier.loadPlaylists();
  });
  return notifier;
});
