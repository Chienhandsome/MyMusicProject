import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_music_project/data/repositories/audio_repository.dart';
import 'package:my_music_project/data/services/audio_player_service.dart';
import 'package:my_music_project/domain/entities/play_mode.dart';

class NativePlayer extends Fake implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast();
  LoopMode loop = LoopMode.off;
  bool shuffleEnabled = false;
  int plays = 0, pauses = 0, nexts = 0, previous = 0;
  @override
  PlaybackEvent get playbackEvent => PlaybackEvent(currentIndex: 0);
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  bool get playing => false;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;
  @override
  Future<void> setShuffleModeEnabled(bool value) async {
    shuffleEnabled = value;
  }

  @override
  Future<void> setLoopMode(LoopMode value) async {
    loop = value;
  }

  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> seekToNext() async {
    nexts++;
  }

  @override
  Future<void> seekToPrevious() async {
    previous++;
  }

  @override
  Future<void> dispose() async {
    await events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativePlayer native;
  late AudioPlayerService service;
  setUp(() {
    native = NativePlayer();
    service = AudioPlayerService(player: native);
  });
  tearDown(() => service.dispose());

  test('all existing loop/shuffle mode mappings remain unchanged', () async {
    for (final mode in PlayMode.values) {
      await service.setPlayMode(mode, continuePlay: false);
      expect(native.loop, LoopMode.one);
      expect(native.shuffleEnabled, isFalse);
    }
    await service.setPlayMode(PlayMode.repeat, continuePlay: true);
    expect(native.loop, LoopMode.one);
    expect(native.shuffleEnabled, isFalse);
    await service.setPlayMode(PlayMode.shuffle, continuePlay: true);
    expect(native.loop, LoopMode.all);
    expect(native.shuffleEnabled, isTrue);
    await service.setPlayMode(PlayMode.sequential, continuePlay: true);
    expect(native.loop, LoopMode.all);
    expect(native.shuffleEnabled, isFalse);
  });

  test(
      'notification play/pause callbacks and repository native commands do not recurse',
      () async {
    final repository = AudioRepositoryImpl(service);
    var playRequests = 0, pauseRequests = 0;
    repository.setNotificationCallbacks(
        onSkipToNext: () async {},
        onSkipToPrevious: () async {},
        onPlay: () async {
          playRequests++;
          await repository.play();
        },
        onPause: () async {
          pauseRequests++;
          await repository.pause();
        });
    await service.play();
    await service.pause();
    expect(playRequests, 1);
    expect(native.plays, 1);
    expect(pauseRequests, 1);
    expect(native.pauses, 1);
  });

  test('manual next and previous still delegate to the native player',
      () async {
    await service.setPlayMode(PlayMode.repeat, continuePlay: true);
    await service.seekToNext();
    await service.seekToPrevious();
    expect(native.nexts, 1);
    expect(native.previous, 1);
  });

  test('native playback errors reach the repository error stream', () async {
    final expected = expectLater(
        AudioRepositoryImpl(service).errorStream, emits(isA<StateError>()));
    native.events.addError(StateError('decoder failure'));
    await expected;
  });
}
