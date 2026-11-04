import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/media_keys.dart';
import '../../di/app_providers.dart';
import '../../domain/entities/play_mode.dart';
import '../../domain/entities/playback_event.dart';
import '../../domain/entities/song.dart';
import '../../domain/usecases/playback_usecases.dart';
import 'playlist_provider.dart';

class AudioState {
  final Song? currentSong;
  final int currentIndex;
  final bool isPlaying;
  final bool isLoading;
  final String? errorMessage;
  final int errorId;
  final PlayMode playMode;
  final bool isContinuePlay;
  final DateTime? sleepTimerEnd;
  final int sleepTimerCompletionId;

  const AudioState({
    this.currentSong,
    this.currentIndex = -1,
    this.isPlaying = false,
    this.isLoading = false,
    this.errorMessage,
    this.errorId = 0,
    this.playMode = PlayMode.sequential,
    this.isContinuePlay = false,
    this.sleepTimerEnd,
    this.sleepTimerCompletionId = 0,
  });

  AudioState copyWith({
    Song? currentSong,
    int? currentIndex,
    bool? isPlaying,
    bool? isLoading,
    String? errorMessage,
    int? errorId,
    bool clearError = false,
    PlayMode? playMode,
    bool? isContinuePlay,
    DateTime? sleepTimerEnd,
    int? sleepTimerCompletionId,
    bool clearCurrentSong = false,
    bool clearSleepTimer = false,
  }) {
    return AudioState(
      currentSong: clearCurrentSong ? null : (currentSong ?? this.currentSong),
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorId: errorId ?? this.errorId,
      playMode: playMode ?? this.playMode,
      isContinuePlay: isContinuePlay ?? this.isContinuePlay,
      sleepTimerEnd:
          clearSleepTimer ? null : (sleepTimerEnd ?? this.sleepTimerEnd),
      sleepTimerCompletionId:
          sleepTimerCompletionId ?? this.sleepTimerCompletionId,
    );
  }
}

class AudioNotifier extends StateNotifier<AudioState> {
  final PlaybackUseCases _playbackUseCases;
  late final StreamSubscription<Song?> _currentSongSubscription;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<PlaybackProcessingState>
      _processingSubscription;
  late final StreamSubscription<String?> _errorSubscription;
  final Future<void> Function()? _onFavoritesChanged;
  Timer? _sleepTimer;

  AudioNotifier(PlaybackUseCases playbackUseCases,
      {Future<void> Function()? onFavoritesChanged})
      : _onFavoritesChanged = onFavoritesChanged,
        _playbackUseCases = playbackUseCases,
        super(AudioState(
          isPlaying: playbackUseCases.isPlaying,
          currentSong: playbackUseCases.currentSong,
          currentIndex: playbackUseCases.currentIndex,
          playMode: playbackUseCases.playMode,
          isContinuePlay: playbackUseCases.continuePlay,
        )) {
    _playingSubscription = _playbackUseCases.playingStream.listen((isPlaying) {
      if (!mounted) return;
      state =
          state.copyWith(isPlaying: isPlaying && state.errorMessage == null);
    });
    _currentSongSubscription =
        _playbackUseCases.currentSongStream.listen((song) {
      if (!mounted) return;
      state = state.copyWith(
        currentSong: song,
        clearCurrentSong: song == null,
        currentIndex: _playbackUseCases.currentIndex,
      );
    });
    _processingSubscription =
        _playbackUseCases.processingStateStream.listen((processing) {
      if (!mounted) return;
      state = state.copyWith(
          isLoading: processing == PlaybackProcessingState.loading ||
              processing == PlaybackProcessingState.buffering);
    });
    _errorSubscription = _playbackUseCases.errorStream.listen((error) {
      if (!mounted) return;
      if (error == null) {
        state = state.copyWith(clearError: true);
      } else {
        _showError();
      }
    });
  }

  void _showError() {
    if (!mounted || state.errorMessage != null) return;
    state = state.copyWith(
        isPlaying: false,
        isLoading: false,
        errorMessage: 'playbackFailed',
        errorId: state.errorId + 1);
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (!mounted) return;
    state = state.copyWith(clearError: true);
    try {
      await action();
      if (!mounted) return;
      state = state.copyWith(
        currentSong: _playbackUseCases.currentSong,
        clearCurrentSong: _playbackUseCases.currentSong == null,
        currentIndex: _playbackUseCases.currentIndex,
        playMode: _playbackUseCases.playMode,
        isContinuePlay: _playbackUseCases.continuePlay,
      );
    } catch (_) {
      _showError();
    }
  }

  double get speed => _playbackUseCases.speed;

  Future<void> setPlaylist(List<Song> songs) =>
      _perform(() => _playbackUseCases.setPlaylist(songs));

  Future<void> playSongAt(int index) =>
      _perform(() => _playbackUseCases.playSongAt(index));

  Future<void> playSong(String path) =>
      _perform(() => _playbackUseCases.playSong(path));

  Future<void> play() => _perform(_playbackUseCases.play);

  Future<void> pause() => _perform(_playbackUseCases.pause);

  Future<void> stop() => _perform(_playbackUseCases.stop);

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> playNext() => _perform(_playbackUseCases.playNext);

  Future<void> playPrevious() => _perform(_playbackUseCases.playPrevious);

  Future<void> seek(Duration position) =>
      _perform(() => _playbackUseCases.seek(position));

  Future<void> togglePlayMode() => _perform(_playbackUseCases.togglePlayMode);

  String getPlayModeKey() {
    return switch (state.playMode) {
      PlayMode.repeat => MediaKeys.repeatMode,
      PlayMode.sequential => MediaKeys.sequentialMode,
      PlayMode.shuffle => MediaKeys.shuffleMode,
    };
  }

  Future<void> toggleContinuePlay() =>
      _perform(_playbackUseCases.toggleContinuePlay);

  Future<void> toggleCurrentSongFavorite() => _perform(() async {
        final song = state.currentSong;
        if (song == null) return;
        await _playbackUseCases.toggleFavorite(song);
        await _onFavoritesChanged?.call();
      });

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    state = state.copyWith(sleepTimerEnd: DateTime.now().add(duration));
    _sleepTimer = Timer(duration, () async {
      await pause();
      if (!mounted) return;
      state = state.copyWith(
        clearSleepTimer: true,
        sleepTimerCompletionId: state.sleepTimerCompletionId + 1,
      );
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    state = state.copyWith(clearSleepTimer: true);
  }

  Future<void> setSpeed(double speed) =>
      _perform(() => _playbackUseCases.setSpeed(speed));

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _playingSubscription.cancel();
    _currentSongSubscription.cancel();
    _processingSubscription.cancel();
    _errorSubscription.cancel();
    super.dispose();
  }
}

final audioProvider = StateNotifierProvider<AudioNotifier, AudioState>((ref) {
  return AudioNotifier(ref.watch(playbackUseCasesProvider),
      onFavoritesChanged: () =>
          ref.read(playlistProvider.notifier).loadPlaylists());
});

final playingProvider = StreamProvider<bool>((ref) {
  return ref.watch(playbackUseCasesProvider).playingStream;
});

final positionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playbackUseCasesProvider).positionStream;
});
