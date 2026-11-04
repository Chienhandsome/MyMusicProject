import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_music_project/di/app_providers.dart';
import 'package:my_music_project/domain/entities/playback_event.dart';
import 'package:my_music_project/domain/entities/play_mode.dart';
import 'package:my_music_project/presentation/providers/audio_provider.dart';
import '../domain/playback_regression.dart';

void main() {
  late Fixture f;
  late ProviderContainer container;
  setUp(() {
    f = Fixture();
    container = ProviderContainer(overrides: [
      playbackUseCasesProvider.overrideWithValue(f.playback),
    ]);
    container.read(audioProvider);
  });
  tearDown(() async {
    container.dispose();
    await f.close();
  });

  test('play state follows engine signals instead of command completion',
      () async {
    await f.playback.setPlaylist([song(1)]);
    f.audio.startImmediately = false;
    await container.read(audioProvider.notifier).play();
    expect(container.read(audioProvider).isPlaying, isFalse);
    f.audio.active = true;
    f.audio.playing.add(true);
    expect(container.read(audioProvider).isPlaying, isTrue);
  });

  test('direct domain clear removes old song from provider', () async {
    await f.playback.setPlaylist([song(1)]);
    await settle();
    expect(container.read(audioProvider).currentSong, isNotNull);
    await f.playback.setPlaylist([]);
    await settle();
    expect(container.read(audioProvider).currentSong, isNull);
    expect(container.read(audioProvider).currentIndex, -1);
    expect(container.read(audioProvider).isPlaying, isFalse);
  });

  test('failed playback reports error and can recover on retry', () async {
    await f.playback.setPlaylist([song(1)]);
    f.audio.failPlay = true;
    final notifier = container.read(audioProvider.notifier);
    await notifier.play();
    await settle();
    expect(container.read(audioProvider).isPlaying, isFalse);
    expect(container.read(audioProvider).errorMessage, isNotNull);
    expect(f.playback.currentSong!.numberOfTimesPlayed, isNull);
    f.audio.failPlay = false;
    await notifier.play();
    await settle();
    expect(container.read(audioProvider).isPlaying, isTrue);
    expect(container.read(audioProvider).errorMessage, isNull);
    expect(f.playback.currentSong!.numberOfTimesPlayed, 1);
  });

  test('empty play never creates a phantom playing state', () async {
    await container.read(audioProvider.notifier).play();
    await settle();
    expect(container.read(audioProvider).isPlaying, isFalse);
    expect(container.read(audioProvider).errorMessage, isNotNull);
  });

  test('loading and buffering are visible and error clears loading', () async {
    f.audio.processing.add(PlaybackProcessingState.loading);
    expect(container.read(audioProvider).isLoading, isTrue);
    f.audio.processing.add(PlaybackProcessingState.buffering);
    expect(container.read(audioProvider).isLoading, isTrue);
    f.audio.errors.add(StateError('native decoder'));
    await settle();
    expect(container.read(audioProvider).isLoading, isFalse);
    expect(container.read(audioProvider).errorMessage, isNotNull);
  });

  test('rapid mode toggles use domain state and retain all presses', () async {
    final notifier = container.read(audioProvider.notifier);
    await Future.wait([
      notifier.togglePlayMode(),
      notifier.togglePlayMode(),
      notifier.togglePlayMode()
    ]);
    expect(f.playback.playMode, PlayMode.sequential);
    expect(container.read(audioProvider).playMode, PlayMode.sequential);
    await Future.wait(
        [notifier.toggleContinuePlay(), notifier.toggleContinuePlay()]);
    expect(f.playback.continuePlay, isFalse);
    expect(container.read(audioProvider).isContinuePlay, isFalse);
  });

  test('dispose during pending command does not update disposed state',
      () async {
    await f.playback.setPlaylist([song(1)]);
    f.preferences.gate = Completer<void>();
    f.preferences.gatePath = song(1).path;
    final command = container.read(audioProvider.notifier).play();
    await settle();
    container.dispose();
    f.preferences.gate!.complete();
    await command;
    // A separate container keeps tearDown safe without a second dispose.
    container = ProviderContainer();
  });
}
