import 'dart:async';

import '../entities/play_mode.dart';
import '../entities/playback_event.dart';
import '../entities/song.dart';
import '../repositories/audio_repository.dart';
import '../repositories/music_repository.dart';
import '../repositories/play_config_repository.dart';
import '../repositories/preferences_repository.dart';

abstract class LibraryPlaybackController {
  Future<void> setPlaylist(List<Song> songs);

  Future<void> stop();

  Song? get currentSong;
}

class PlaybackUseCases implements LibraryPlaybackController {
  final AudioRepository _audioRepository;
  final PreferencesRepository _preferencesRepository;
  final PlayConfigRepository _playConfigRepository;
  final MusicRepository _musicRepository;
  final StreamController<Song?> _currentSongController =
      StreamController<Song?>.broadcast();

  late final StreamSubscription<PlaybackProcessingState>
      _processingStateSubscription;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<Object> _errorSubscription;
  final _errors = StreamController<String?>.broadcast();
  PlaybackProcessingState _processingState = PlaybackProcessingState.idle;
  int _executingGeneration = 0;
  String? _pendingRecordPath;
  int? _failedGeneration;
  late final StreamSubscription<int?> _currentIndexSubscription;
  late final StreamSubscription<PlaybackDiscontinuity>
      _discontinuitySubscription;

  Future<void> _operationTail = Future<void>.value();
  int _generation = 0;
  int _pendingCommands = 0;
  bool _disposed = false;
  bool _changingSource = false;

  Future<void> _sourceChange(Future<void> Function() action) async {
    _changingSource = true;
    try {
      await action();
    } finally {
      _changingSource = false;
    }
  }

  // Commands, metadata writes, and player callbacks share one ordered lane.
  // A new command immediately invalidates callbacks from the old session.
  Future<void> _command(Future<void> Function() action) {
    final generation = ++_generation;
    _pendingCommands++;
    final result = _operationTail.then((_) async {
      if (_disposed) return;
      _executingGeneration = generation;
      try {
        await action();
      } catch (error) {
        if (_isCurrent(generation)) await _failPlayback(generation);
        rethrow;
      }
    }).whenComplete(() => _pendingCommands--);
    _operationTail = result.catchError((Object _) {});
    return result;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _playerEvent(Future<void> Function(int generation) action,
      {int? session, bool duringCommand = false}) {
    if (_disposed ||
        (!duringCommand &&
            _pendingCommands > 0 &&
            (_changingSource || _executingGeneration != _generation))) {
      return;
    }
    final generation = session ?? _generation;
    final result = _operationTail.then((_) async {
      if (_isCurrent(generation)) await action(generation);
    });
    _operationTail = result.catchError((Object _) async {
      if (_isCurrent(generation)) await _failPlayback(generation);
    });
  }

  Future<void> _failPlayback(int generation) async {
    if (!_isCurrent(generation)) return;
    _signalFailure(generation);
    try {
      await _audioRepository.pause();
    } catch (_) {/* Already reporting the playback error. */}
  }

  void _signalFailure(int generation) {
    if (!_isCurrent(generation) || _failedGeneration == generation) return;
    _failedGeneration = generation;
    _pendingRecordPath = null;
    _errors.add('playbackFailed');
  }

  void _publishSong() {
    if (!_disposed) _currentSongController.add(currentSong);
  }

  List<Song> _playlist = [];
  int _currentIndex = -1;
  late PlayMode _playMode;
  late bool _continuePlay;
  bool _isAudioPlaylistLoaded = false;
  bool _isBlockingAutoAdvance = false;
  bool _isManualIndexChange = false;
  int? _manualIndexChangeTarget;

  PlaybackUseCases(
    this._audioRepository,
    this._preferencesRepository,
    this._playConfigRepository,
    this._musicRepository,
  ) {
    _playMode = _playConfigRepository.getPlayMode();
    _continuePlay = _playConfigRepository.getContinuePlay();
    _audioRepository.setNotificationCallbacks(
      onSkipToNext: playNext,
      onSkipToPrevious: playPrevious,
      onPlay: play,
      onPause: pause,
      onStop: stop,
      onSeek: seek,
    );

    _processingStateSubscription =
        _audioRepository.processingStateStream.listen((state) {
      _processingState = state;
      _confirmPlayback();
      if (!_continuePlay && state == PlaybackProcessingState.completed) {
        _playerEvent((generation) => _stopAtCurrentSongStart(generation));
      }
    });
    _playingSubscription = _audioRepository.playingStream.listen((playing) {
      if (playing) _confirmPlayback();
    });
    _errorSubscription = _audioRepository.errorStream.listen((error) {
      final generation =
          _pendingCommands > 0 ? _executingGeneration : _generation;
      _signalFailure(generation);
      _playerEvent((generation) => _failPlayback(generation),
          session: generation, duringCommand: true);
    });
    _currentIndexSubscription =
        _audioRepository.currentIndexStream.listen((index) {
      if (_isBlockingAutoAdvance) return;
      _playerEvent(
          (generation) => _handlePlayerIndexChanged(index, generation));
    });
    _discontinuitySubscription =
        _audioRepository.discontinuityStream.listen((event) {
      _playerEvent((generation) => _handleDiscontinuity(event, generation));
    });
  }

  @override
  Future<void> setPlaylist(List<Song> songs) {
    final snapshot = List<Song>.of(songs);
    return _command(() => _sourceChange(() => _setPlaylist(snapshot)));
  }

  Future<void> _setPlaylist(List<Song> songs) async {
    _pendingRecordPath = null;
    final previousSong = currentSong;
    final previousPosition = _audioRepository.position;
    final wasPlaying = _audioRepository.isPlaying;
    final sameSources = _isAudioPlaylistLoaded &&
        songs.length == _playlist.length &&
        List.generate(songs.length, (i) => songs[i].path == _playlist[i].path)
            .every((same) => same);
    _playlist = List<Song>.of(songs);

    if (_playlist.isEmpty) {
      _isAudioPlaylistLoaded = false;
      _currentIndex = -1;
      await _audioRepository.pause();
      await _audioRepository.setPlaylist(const []);
      _publishSong();
      return;
    }

    final path = previousSong?.path ?? _preferencesRepository.getLastSongPath();
    final retainedIndex = _playlist.indexWhere((song) => song.path == path);
    _currentIndex = retainedIndex < 0 ? 0 : retainedIndex;
    if (!sameSources) {
      _isAudioPlaylistLoaded = false;
      await _audioRepository.pause();
      _isManualIndexChange = true;
      try {
        await _audioRepository.setPlaylist(
          _playlist,
          initialIndex: _currentIndex,
        );
        if (previousSong != null && retainedIndex >= 0) {
          await _audioRepository.seek(previousPosition);
        }
        await _audioRepository.setPlayMode(
          _playMode,
          continuePlay: _continuePlay,
        );
        _isAudioPlaylistLoaded = true;
      } finally {
        _isManualIndexChange = false;
      }
    }

    final song = currentSong;
    if (song != null) {
      await _audioRepository.setCurrentSong(song);
    }
    _publishSong();
    if (!sameSources &&
        wasPlaying &&
        previousSong != null &&
        retainedIndex >= 0) {
      _startPlayback(record: false);
    }
  }

  Future<void> playSong(String path) => _command(() => _sourceChange(() async {
        final index = _playlist.indexWhere((song) => song.path == path);
        if (index < 0) throw StateError('Song is not in the active queue');
        await _playSongAt(index);
      }));

  Future<void> playSongAt(int index) =>
      _command(() => _sourceChange(() => _playSongAt(index)));

  Future<void> _playSongAt(int index) async {
    if (index < 0 || index >= _playlist.length) {
      throw StateError('Song is not in the active queue');
    }

    _currentIndex = index;
    final song = _playlist[index];

    if (_isAudioPlaylistLoaded) {
      await _runManualIndexChange(() async {
        await _audioRepository.seekToIndex(index);
        _manualIndexChangeTarget = index;
      });
    } else {
      await _audioRepository.setPlaylist(_playlist, initialIndex: index);
      await _audioRepository.setPlayMode(
        _playMode,
        continuePlay: _continuePlay,
      );
      _isAudioPlaylistLoaded = true;
    }
    await _preferencesRepository.setLastSongPath(song.path);
    await _audioRepository.setCurrentSong(song);
    _publishSong();
    _startPlayback();
  }

  Future<void> play() => _command(_play);

  Future<void> _play() async {
    final song = currentSong;
    if (song == null) throw StateError('No song selected');
    if (!_isAudioPlaylistLoaded) {
      await _playSongAt(_currentIndex);
      return;
    }
    await _preferencesRepository.setLastSongPath(song.path);
    _startPlayback();
  }

  void _startPlayback({bool record = true}) {
    if (_disposed) return;
    final generation = _executingGeneration;
    _pendingRecordPath = record ? currentSong?.path : null;
    _failedGeneration = null;
    if (!_disposed) _errors.add(null);
    // just_audio's future completes when playback stops, not when it starts.
    unawaited(_audioRepository.play().catchError((Object error) {
      _signalFailure(generation);
      _playerEvent((session) => _failPlayback(session),
          session: generation, duringCommand: true);
    }));
    _confirmPlayback(session: generation);
  }

  void _confirmPlayback({int? session}) {
    final path = _pendingRecordPath;
    if (path == null) return;
    final generation = session ?? _generation;
    _playerEvent((_) async {
      await Future<void>.delayed(Duration.zero);
      if (!_isCurrent(generation)) return;
      if (_pendingRecordPath != path ||
          currentSong?.path != path ||
          !_audioRepository.isPlaying ||
          _processingState != PlaybackProcessingState.ready) {
        return;
      }
      _pendingRecordPath = null;
      await _recordPlayback(currentSong!);
    }, session: generation, duringCommand: true);
  }

  Future<void> _recordPlayback(Song song) async {
    final lastPlay = DateTime.now().millisecondsSinceEpoch;
    final playCount = (song.numberOfTimesPlayed ?? 0) + 1;
    song
      ..lastPlay = lastPlay
      ..numberOfTimesPlayed = playCount;

    try {
      await _musicRepository.updatePlaybackStats(
        song,
        lastPlay: lastPlay,
        numberOfTimesPlayed: playCount,
      );
    } catch (_) {
      // Playback should continue even when recording analytics fails.
    }
  }

  Future<void> pause() => _command(() async {
        _pendingRecordPath = null;
        await _audioRepository.pause();
      });

  @override
  Future<void> stop() => _command(() async {
        _pendingRecordPath = null;
        await _audioRepository.stop();
      });

  Future<void> playNext() => _command(() => _sourceChange(_playNext));

  Future<void> _playNext() async {
    if (_playlist.isEmpty) return;
    if (!_isAudioPlaylistLoaded) {
      await _playSongAt((_currentIndex + 1) % _playlist.length);
      return;
    }

    await _runManualIndexChange(() async {
      await _audioRepository.seekToNext();
      _manualIndexChangeTarget = _audioRepository.currentIndex;
    });
    final index = _audioRepository.currentIndex;
    if (index != null) {
      await _handleCurrentIndexChanged(index, forceRecord: true);
    }
    _startPlayback();
  }

  Future<void> playPrevious() => _command(() => _sourceChange(_playPrevious));

  Future<void> _playPrevious() async {
    if (_playlist.isEmpty) return;
    if (!_isAudioPlaylistLoaded) {
      final index = (_currentIndex - 1 + _playlist.length) % _playlist.length;
      await _playSongAt(index);
      return;
    }

    await _runManualIndexChange(() async {
      await _audioRepository.seekToPrevious();
      _manualIndexChangeTarget = _audioRepository.currentIndex;
    });
    final index = _audioRepository.currentIndex;
    if (index != null) {
      await _handleCurrentIndexChanged(index, forceRecord: true);
    }
    _startPlayback();
  }

  Future<void> seek(Duration position) =>
      _command(() => _audioRepository.seek(position));

  Future<void> setSpeed(double speed) =>
      _command(() => _audioRepository.setSpeed(speed));

  Future<void> togglePlayMode() => _command(() => _setPlayMode(
      PlayMode.values[(_playMode.index + 1) % PlayMode.values.length]));

  Future<void> toggleContinuePlay() =>
      _command(() => _setContinuePlay(!_continuePlay));

  Future<void> setPlayMode(PlayMode mode) => _command(() => _setPlayMode(mode));

  Future<void> _setPlayMode(PlayMode mode) async {
    try {
      await _audioRepository.setPlayMode(mode, continuePlay: _continuePlay);
      await _playConfigRepository.setPlayMode(mode);
      _playMode = mode;
    } catch (_) {
      try {
        await _audioRepository.setPlayMode(_playMode,
            continuePlay: _continuePlay);
      } catch (_) {/* Preserve the original error. */}
      rethrow;
    }
  }

  Future<void> setContinuePlay(bool continuePlay) =>
      _command(() => _setContinuePlay(continuePlay));

  Future<void> _setContinuePlay(bool continuePlay) async {
    try {
      await _audioRepository.setPlayMode(_playMode, continuePlay: continuePlay);
      await _playConfigRepository.setContinuePlay(continuePlay);
      _continuePlay = continuePlay;
    } catch (_) {
      try {
        await _audioRepository.setPlayMode(_playMode,
            continuePlay: _continuePlay);
      } catch (_) {/* Preserve the original error. */}
      rethrow;
    }
  }

  Future<void> toggleFavorite(Song song) =>
      _command(() => _toggleFavorite(song));

  Future<void> _toggleFavorite(Song song) async {
    final next = !song.isFavorite;
    song.isFavorite = next;
    try {
      await _musicRepository.updateFavorite(song, isFavorite: next);
      _publishSong();
    } catch (_) {
      song.isFavorite = !next;
      rethrow;
    }
  }

  Future<void> _handleCurrentIndexChanged(
    int? index, {
    bool forceRecord = false,
  }) async {
    if (index == null || index < 0 || index >= _playlist.length) return;
    if (index == _currentIndex && !forceRecord) return;

    _currentIndex = index;
    final song = currentSong;
    _publishSong();
    if (song == null) return;

    await _audioRepository.setCurrentSong(song);
    await _preferencesRepository.setLastSongPath(song.path);
    if (forceRecord) {
      _pendingRecordPath = song.path;
      _confirmPlayback();
    }
  }

  Future<void> _handlePlayerIndexChanged(int? index, int generation) async {
    if (index == null || index < 0 || index >= _playlist.length) return;
    final allowed = _isManualIndexChange || index == _manualIndexChangeTarget;
    if (index == _manualIndexChangeTarget) _manualIndexChangeTarget = null;

    if (!_continuePlay && !allowed && index != _currentIndex) {
      await _blockAutoAdvance(_currentIndex, generation);
      return;
    }
    await _handleCurrentIndexChanged(index);
  }

  Future<void> _handleDiscontinuity(
      PlaybackDiscontinuity event, int generation) async {
    if (!event.isAutoAdvance) return;
    if (_continuePlay) {
      await _handleCurrentIndexChanged(event.currentIndex, forceRecord: true);
      return;
    }

    final previousIndex = event.previousIndex;
    if (previousIndex == null ||
        previousIndex < 0 ||
        previousIndex >= _playlist.length) {
      return;
    }
    await _blockAutoAdvance(previousIndex, generation);
  }

  Future<void> _blockAutoAdvance(int indexToRestore, int generation) async {
    if (indexToRestore < 0 || indexToRestore >= _playlist.length) return;
    if (_isBlockingAutoAdvance) return;

    _isBlockingAutoAdvance = true;
    try {
      await Future<void>.delayed(Duration.zero);
      if (!_isCurrent(generation)) return;
      await _audioRepository.pause();
      if (!_isCurrent(generation)) return;
      await _audioRepository.seekToIndex(indexToRestore);
      if (!_isCurrent(generation)) return;
      await _audioRepository.seek(Duration.zero);
      if (!_isCurrent(generation)) return;
      _currentIndex = indexToRestore;
      final song = currentSong;
      _publishSong();
      if (song != null) {
        await _audioRepository.setCurrentSong(song);
        await _preferencesRepository.setLastSongPath(song.path);
      }
    } finally {
      _isBlockingAutoAdvance = false;
    }
  }

  Future<void> _runManualIndexChange(Future<void> Function() change) async {
    _isManualIndexChange = true;
    try {
      await change();
    } finally {
      _isManualIndexChange = false;
    }
  }

  Future<void> _stopAtCurrentSongStart(int generation) async {
    await Future<void>.delayed(Duration.zero);
    if (!_isCurrent(generation)) return;
    await _audioRepository.pause();
    if (!_isCurrent(generation)) return;
    await _audioRepository.seek(Duration.zero);
  }

  @override
  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _playlist.length
          ? _playlist[_currentIndex]
          : null;

  Stream<Song?> get currentSongStream => _currentSongController.stream;

  int get currentIndex => _currentIndex;

  PlayMode get playMode => _playMode;

  bool get continuePlay => _continuePlay;

  double get speed => _audioRepository.speed;

  bool get isPlaying => _audioRepository.isPlaying;

  Stream<String?> get errorStream => _errors.stream;

  Stream<PlaybackProcessingState> get processingStateStream =>
      _audioRepository.processingStateStream;

  Stream<bool> get playingStream => _audioRepository.playingStream;

  Stream<Duration> get positionStream => _audioRepository.positionStream;

  void dispose() {
    _disposed = true;
    _generation++;
    _processingStateSubscription.cancel();
    _playingSubscription.cancel();
    _errorSubscription.cancel();
    _errors.close();
    _currentIndexSubscription.cancel();
    _discontinuitySubscription.cancel();
    _currentSongController.close();
  }
}
