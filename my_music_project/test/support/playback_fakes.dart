import 'dart:async';
import 'package:my_music_project/domain/entities/play_mode.dart';
import 'package:my_music_project/domain/entities/playback_event.dart';
import 'package:my_music_project/domain/entities/song.dart';
import 'package:my_music_project/domain/repositories/audio_repository.dart';
import 'package:my_music_project/domain/repositories/music_repository.dart';
import 'package:my_music_project/domain/repositories/play_config_repository.dart';
import 'package:my_music_project/domain/repositories/preferences_repository.dart';

class FakeAudio implements AudioRepository {
  final playing = StreamController<bool>.broadcast(sync: true);
  final processing =
      StreamController<PlaybackProcessingState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final indices = StreamController<int?>.broadcast(sync: true);
  final discontinuities =
      StreamController<PlaybackDiscontinuity>.broadcast(sync: true);
  final errors = StreamController<Object>.broadcast(sync: true);
  List<Song> queue = [];
  Song? metadata;
  @override
  Duration position = Duration.zero;
  int sourceLoads = 0;
  int? index;
  bool active = false;
  bool failPlay = false;
  bool failLoad = false;
  bool startImmediately = true;
  Completer<void>? playCompletion;
  PlayMode mode = PlayMode.sequential;
  bool continuePlay = false;
  Future<void> Function()? notificationPlay;
  Future<void> Function()? notificationPause;
  Future<void> Function()? notificationNext;
  @override
  int? get currentIndex => index;
  @override
  bool get isPlaying => active;
  @override
  Duration? get duration => const Duration(seconds: 10);
  @override
  double get speed => 1;
  @override
  Stream<Object> get errorStream => errors.stream;
  @override
  Stream<bool> get playingStream => playing.stream;
  @override
  Stream<PlaybackProcessingState> get processingStateStream =>
      processing.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<int?> get currentIndexStream => indices.stream;
  @override
  Stream<PlaybackDiscontinuity> get discontinuityStream =>
      discontinuities.stream;
  @override
  Future<void> setPlaylist(List<Song> songs, {int initialIndex = 0}) async {
    if (failLoad) throw StateError('load failure');
    sourceLoads++;
    queue = List.of(songs);
    index = songs.isEmpty ? null : initialIndex;
    position = Duration.zero;
    processing.add(PlaybackProcessingState.ready);
  }

  @override
  Future<void> seekToNext() =>
      seekToIndex(!continuePlay || mode == PlayMode.repeat
          ? index!
          : (index! + 1) % queue.length);
  @override
  Future<void> seekToPrevious() =>
      seekToIndex(!continuePlay || mode == PlayMode.repeat
          ? index!
          : (index! - 1 + queue.length) % queue.length);
  @override
  Future<void> seekToIndex(int value) async {
    index = value;
    position = Duration.zero;
  }

  @override
  Future<void> setCurrentSong(Song value) async {
    metadata = value;
  }

  @override
  Future<void> play() async {
    if (failPlay) throw StateError('decoder failure');
    if (startImmediately) {
      active = true;
      playing.add(true);
    }
    await playCompletion?.future;
  }

  @override
  Future<void> pause() async {
    active = false;
    playing.add(false);
  }

  @override
  Future<void> stop() => pause();
  @override
  Future<void> seek(Duration value) async {
    position = value;
  }

  @override
  Future<void> setPlayMode(PlayMode mode, {required bool continuePlay}) async {
    this.mode = mode;
    this.continuePlay = continuePlay;
  }

  @override
  void setNotificationCallbacks(
      {required Future<void> Function() onSkipToNext,
      required Future<void> Function() onSkipToPrevious,
      Future<void> Function()? onPlay,
      Future<void> Function()? onPause,
      Future<void> Function()? onStop,
      Future<void> Function(Duration)? onSeek}) {
    notificationPlay = onPlay;
    notificationPause = onPause;
    notificationNext = onSkipToNext;
  }

  @override
  void dispose() {
    errors.close();
    playing.close();
    processing.close();
    positions.close();
    indices.close();
    discontinuities.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePreferences implements PreferencesRepository {
  String? last;
  Completer<void>? gate;
  String? gatePath;
  @override
  String? getLastSongPath() => last;
  @override
  Future<void> setLastSongPath(String path) async {
    if (path == gatePath) await gate!.future;
    last = path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConfig implements PlayConfigRepository {
  bool continuous = false;
  bool failWrite = false;
  Completer<void>? writeGate;
  @override
  PlayMode getPlayMode() => PlayMode.sequential;
  @override
  bool getContinuePlay() => continuous;
  @override
  Future<void> setPlayMode(PlayMode value) async {
    await writeGate?.future;
    if (failWrite) throw StateError('storage failure');
  }

  @override
  Future<void> setContinuePlay(bool value) async {
    if (failWrite) throw StateError('storage failure');
    continuous = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMusic implements MusicRepository {
  List<Song> library = [];
  @override
  Future<List<Song>> loadCachedSongs() async => library;
  @override
  Future<List<Song>> scanDeviceSongs() async => library;
  @override
  Future<int?> getLastScanAt() async => null;
  @override
  Future<void> saveSongCache(List<Song> songs) async {
    library = songs;
  }

  @override
  Future<void> deleteSongFromDevice(Song song) async {
    library = library.where((s) => s.path != song.path).toList();
  }

  @override
  Future<void> updateFavorite(Song song, {required bool isFavorite}) async {}
  @override
  Future<void> updatePlaybackStats(Song song,
      {required int lastPlay, required int numberOfTimesPlayed}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
