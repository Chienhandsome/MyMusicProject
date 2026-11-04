// Runnable directly with Dart when the Flutter test runner is unavailable.
import 'dart:async';
import 'package:my_music_project/domain/entities/playlist.dart';
import 'package:my_music_project/domain/entities/playback_event.dart';
import 'package:my_music_project/domain/entities/play_mode.dart';
import 'package:my_music_project/domain/entities/song.dart';
import 'package:my_music_project/domain/repositories/playlist_repository.dart';
import 'package:my_music_project/domain/usecases/playback_queue_usecases.dart';
import 'package:my_music_project/domain/usecases/playback_usecases.dart';
import 'package:my_music_project/domain/usecases/playlist_usecases.dart';
import '../support/playback_fakes.dart';

Song song(int id) =>
    Song(id: id, title: '$id', path: '/$id.mp3', duration: 10000);
void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

class Fixture {
  final audio = FakeAudio();
  final preferences = FakePreferences();
  final config = FakeConfig();
  late final playback =
      PlaybackUseCases(audio, preferences, config, FakeMusic());
  Future<void> close() async {
    await settle();
    playback.dispose();
    audio.dispose();
  }
}

class FakePlaylists implements PlaylistRepository {
  String? selected;
  final Map<String, Playlist> records = {};
  @override
  Future<List<Playlist>> getPlaylists() async => records.values.toList();
  @override
  Future<void> addSong(String id, String path) async {
    records[id] =
        records[id]!.copyWith(songPaths: [...records[id]!.songPaths, path]);
  }

  @override
  Future<void> removeSong(String id, String path) async {
    records[id] = records[id]!.copyWith(
        songPaths: records[id]!.songPaths.where((p) => p != path).toList());
  }

  @override
  Future<void> deletePlaylist(String id) async {
    records.remove(id);
  }

  @override
  Future<void> updateSongPaths(String id, List<String> paths) async {
    records[id] = records[id]!.copyWith(songPaths: paths);
  }

  @override
  Future<String?> getCurrentPlaylistId() async => selected;
  @override
  Future<void> setCurrentPlaylistId(String? id) async {
    selected = id;
  }

  @override
  Future<Playlist?> getPlaylistById(String id) async => records[id];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final queueCases = <String, Future<void> Function(Fixture)>{
  'reordering retains song identity, position and playing state': (f) async {
    final a = song(1), b = song(2), c = song(3);
    await f.playback.setPlaylist([a, b, c]);
    await f.playback.playSong(b.path);
    await f.playback.seek(const Duration(seconds: 5));
    await f.playback.setPlaylist([c, a, b]);
    await settle();
    check(f.playback.currentSong?.path == b.path, 'song changed');
    check(f.audio.position == const Duration(seconds: 5), 'position lost');
    check(f.audio.active && f.audio.index == 2, 'playback not preserved');
  },
  'same queue refresh never reloads audio sources': (f) async {
    final songs = [song(1), song(2)];
    await f.playback.setPlaylist(songs);
    await f.playback.playSong(songs[0].path);
    await f.playback.seek(const Duration(seconds: 5));
    final loads = f.audio.sourceLoads;
    await f.playback.setPlaylist([song(1), song(2)]);
    check(f.audio.sourceLoads == loads && f.audio.position.inSeconds == 5,
        'sources reloaded');
  },
  'removing current song selects first song paused': (f) async {
    final a = song(1), b = song(2);
    await f.playback.setPlaylist([a, b]);
    await f.playback.playSong(b.path);
    await f.playback.setPlaylist([a]);
    check(
        f.playback.currentSong == a && !f.audio.active, 'unexpected auto play');
  },
  'removing earlier song preserves current song and paused position':
      (f) async {
    final a = song(1), b = song(2);
    await f.playback.setPlaylist([a, b]);
    await f.playback.playSong(b.path);
    await f.playback.pause();
    await f.playback.seek(const Duration(seconds: 3));
    await f.playback.setPlaylist([b]);
    check(
        f.playback.currentSong == b &&
            f.audio.position.inSeconds == 3 &&
            !f.audio.active,
        'paused state lost');
  },
  'empty queue clears song and stops audio': (f) async {
    await f.playback.setPlaylist([song(1)]);
    await f.playback.play();
    await f.playback.setPlaylist([]);
    check(
        f.playback.currentSong == null &&
            f.playback.currentIndex == -1 &&
            !f.audio.active,
        'queue not cleared');
  },
  'restored selection and scan both use filtered queue': (f) async {
    final repository = FakePlaylists()..selected = 'p';
    repository.records['p'] =
        Playlist(id: 'p', name: 'P', songPaths: [song(2).path], createdAt: 0);
    final queue =
        PlaybackQueueUseCases(f.playback, PlaylistUseCases(repository));
    await queue.setPlaylist([song(1), song(2)]);
    check(f.audio.queue.length == 1 && f.audio.queue.single.id == 2,
        'initial queue unfiltered');
    await queue.setPlaylist([song(3), song(2), song(1)]);
    check(f.audio.queue.length == 1 && f.audio.queue.single.id == 2,
        'scan queue unfiltered');
  },
  'playlist edits and deletion refresh active queue': (f) async {
    final repository = FakePlaylists()..selected = 'p';
    repository.records['p'] =
        Playlist(id: 'p', name: 'P', songPaths: [song(2).path], createdAt: 0);
    final queue =
        PlaybackQueueUseCases(f.playback, PlaylistUseCases(repository));
    await queue.setPlaylist([song(1), song(2), song(3)]);
    repository.records['p'] =
        Playlist(id: 'p', name: 'P', songPaths: [song(3).path], createdAt: 0);
    await queue.refresh();
    check(f.audio.queue.single.id == 3, 'mutation not synchronized');
    repository.records.clear();
    await queue.refresh();
    check(repository.selected == null && f.audio.queue.length == 3,
        'deleted selection not cleared');
  },
  'search switches to full queue and selects by path': (f) async {
    final repository = FakePlaylists()..selected = 'p';
    repository.records['p'] = Playlist(
        id: 'p',
        name: 'P',
        songPaths: [song(2).path, song(3).path],
        createdAt: 0);
    final queue =
        PlaybackQueueUseCases(f.playback, PlaylistUseCases(repository));
    await queue.setPlaylist([song(1), song(2), song(3)]);
    await repository.setCurrentPlaylistId(null);
    await queue.refresh();
    await f.playback.playSong(song(2).path);
    check(
        f.audio.queue.length == 3 &&
            f.playback.currentSong?.id == 2 &&
            f.audio.index == 1,
        'wrong search track');
  },
};

final concurrencyCases = <String, Future<void> Function(Fixture)>{
  'old completion cannot pause a newly selected song': (f) async {
    await f.playback.setPlaylist([song(1), song(2)]);
    await f.playback.playSong(song(1).path);
    f.audio.processing.add(PlaybackProcessingState.completed);
    await f.playback.playSong(song(2).path);
    await settle();
    check(f.playback.currentSong?.id == 2 && f.audio.active,
        'old completion paused new song');
  },
  'overlapping selections finish with matching metadata and saved path':
      (f) async {
    await f.playback.setPlaylist([song(1), song(2)]);
    f.preferences.gate = Completer<void>();
    f.preferences.gatePath = song(1).path;
    final first = f.playback.playSong(song(1).path);
    await settle();
    final second = f.playback.playSong(song(2).path);
    f.preferences.gate!.complete();
    await Future.wait([first, second]);
    check(
        f.playback.currentSong?.id == 2 &&
            f.audio.index == 1 &&
            f.audio.metadata?.id == 2 &&
            f.preferences.last == song(2).path,
        'selection results diverged');
  },
  'pause queued behind play is the final state': (f) async {
    await f.playback.setPlaylist([song(1)]);
    f.preferences.gate = Completer<void>();
    f.preferences.gatePath = song(1).path;
    final play = f.playback.play();
    await settle();
    final pause = f.playback.pause();
    f.preferences.gate!.complete();
    await Future.wait([play, pause]);
    check(!f.audio.active, 'late play overrode pause');
  },
  'failed command does not poison later commands': (f) async {
    await f.playback.setPlaylist([song(1)]);
    try {
      await f.playback.playSong('/missing.mp3');
      throw StateError('expected missing song to fail');
    } on StateError catch (error) {
      check(error.message == 'Song is not in the active queue', 'wrong error');
    }
    await f.playback.playSong(song(1).path);
    check(f.audio.active, 'command lane remained failed');
  },
  'rapid queue changes finish with the latest queue and identity': (f) async {
    await f.playback.setPlaylist([song(1), song(2)]);
    await f.playback.playSong(song(2).path);
    final first = f.playback.setPlaylist([song(2), song(3)]);
    final second = f.playback.setPlaylist([song(3), song(2), song(4)]);
    await Future.wait([first, second]);
    check(
        f.audio.queue.length == 3 &&
            f.audio.index == 1 &&
            f.playback.currentSong?.id == 2 &&
            f.audio.metadata?.id == 2,
        'queue updates interleaved');
  },
};

final stateCases = <String, Future<void> Function(Fixture)>{
  'auto advance during mode persistence is not dropped': (f) async {
    await f.playback.setPlaylist([song(1), song(2)]);
    await f.playback.setContinuePlay(true);
    await f.playback.play();
    await settle();
    f.config.writeGate = Completer<void>();
    final mode = f.playback.setPlayMode(PlayMode.shuffle);
    await settle();
    f.audio.index = 1;
    f.audio.indices.add(1);
    f.audio.discontinuities.add(const PlaybackDiscontinuity(
        isAutoAdvance: true, previousIndex: 0, currentIndex: 1));
    f.config.writeGate!.complete();
    await mode;
    await settle();
    check(f.playback.currentSong?.id == 2 && f.audio.metadata?.id == 2,
        'advance event lost');
  },
  'native error during an older command cannot pause the queued selection':
      (f) async {
    await f.playback.setPlaylist([song(1), song(2)]);
    f.preferences.gate = Completer<void>();
    f.preferences.gatePath = song(1).path;
    final first = f.playback.playSong(song(1).path);
    await settle();
    final second = f.playback.playSong(song(2).path);
    f.audio.errors.add(StateError('old source error'));
    f.preferences.gate!.complete();
    await Future.wait([first, second]);
    await settle();
    check(f.playback.currentSong?.id == 2 && f.audio.active,
        'stale native error paused selection');
  },
  'track tail and seeking near end do not stop playback': (f) async {
    await f.playback.setPlaylist([song(1)]);
    await f.playback.play();
    await f.playback.seek(const Duration(milliseconds: 9800));
    f.audio.positions.add(const Duration(milliseconds: 9800));
    await settle();
    check(f.audio.active && f.audio.position.inMilliseconds == 9800,
        'tail was cut');
  },
  'completion stops at song start when continue is off': (f) async {
    await f.playback.setPlaylist([song(1)]);
    await f.playback.play();
    f.audio.position = const Duration(seconds: 10);
    f.audio.processing.add(PlaybackProcessingState.completed);
    await settle();
    check(!f.audio.active && f.audio.position == Duration.zero,
        'end did not pause');
  },
  'native one-song loop stops only after actual loop boundary': (f) async {
    await f.playback.setPlaylist([song(1)]);
    await f.playback.play();
    f.audio.discontinuities.add(const PlaybackDiscontinuity(
        isAutoAdvance: true, previousIndex: 0, currentIndex: 0));
    await settle();
    check(!f.audio.active && f.audio.position == Duration.zero,
        'loop did not stop');
  },
  'continuous auto advance keeps metadata and stats on the new song':
      (f) async {
    final a = song(1), b = song(2);
    await f.playback.setPlaylist([a, b]);
    await f.playback.setContinuePlay(true);
    await f.playback.play();
    await settle();
    f.audio.index = 1;
    f.audio.indices.add(1);
    f.audio.discontinuities.add(const PlaybackDiscontinuity(
        isAutoAdvance: true, previousIndex: 0, currentIndex: 1));
    await settle();
    check(
        f.audio.active &&
            f.playback.currentSong == b &&
            f.audio.metadata == b &&
            b.numberOfTimesPlayed == 1,
        'advance state diverged');
  },
  'play error is observable without recording a successful play': (f) async {
    final a = song(1);
    await f.playback.setPlaylist([a]);
    final errors = <String?>[];
    final sub = f.playback.errorStream.listen(errors.add);
    f.audio.failPlay = true;
    await f.playback.play();
    await settle();
    check(
        !f.audio.active &&
            a.numberOfTimesPlayed == null &&
            errors.contains('playbackFailed'),
        'failed play was counted or hidden');
    await sub.cancel();
  },
  'count starts on confirmed playback, not command completion': (f) async {
    final a = song(1);
    await f.playback.setPlaylist([a]);
    f.audio.startImmediately = false;
    f.audio.playCompletion = Completer<void>();
    await f.playback.play();
    await settle();
    check(a.numberOfTimesPlayed == null, 'counted before playback began');
    f.audio.active = true;
    f.audio.playing.add(true);
    await settle();
    check(a.numberOfTimesPlayed == 1, 'confirmed playback not counted');
    f.audio.playCompletion!.complete();
  },
  'late play error from an older session cannot pause a newer song': (f) async {
    await f.playback.setPlaylist([song(1), song(2)]);
    final old = Completer<void>();
    f.audio.playCompletion = old;
    await f.playback.playSong(song(1).path);
    f.audio.playCompletion = null;
    await f.playback.playSong(song(2).path);
    old.completeError(StateError('old decoder'));
    await settle();
    check(f.audio.active && f.playback.currentSong?.id == 2,
        'stale error paused new song');
  },
  'notification controls share the command lane': (f) async {
    await f.playback.setPlaylist([song(1)]);
    await f.audio.notificationPlay!();
    await settle();
    check(f.audio.active, 'notification play not wired');
    await f.audio.notificationPause!();
    check(!f.audio.active, 'notification pause not wired');
  },
  'repeat and continue-off retain existing next behavior': (f) async {
    await f.playback.setPlaylist([song(1), song(2)]);
    await f.playback.play();
    await f.playback.playNext();
    check(f.playback.currentIndex == 0, 'continue-off next behavior changed');
    await f.playback.setContinuePlay(true);
    await f.playback.setPlayMode(PlayMode.repeat);
    await f.playback.playNext();
    check(f.playback.currentIndex == 0, 'repeat next behavior changed');
    await f.playback.setPlayMode(PlayMode.sequential);
    await f.playback.playNext();
    check(f.playback.currentIndex == 1, 'sequential next not delegated');
  },
  'mode persistence failure restores effective mode': (f) async {
    await f.playback.setPlaylist([song(1)]);
    f.config.failWrite = true;
    try {
      await f.playback.setPlayMode(PlayMode.shuffle);
    } catch (_) {}
    check(
        f.playback.playMode == PlayMode.sequential &&
            f.audio.mode == PlayMode.sequential,
        'mode diverged after failure');
  },
};

Future<void> runCases(Map<String, Future<void> Function(Fixture)> cases) async {
  for (final entry in cases.entries) {
    final f = Fixture();
    try {
      await entry.value(f);
      print('PASS: ${entry.key}'); // ignore: avoid_print
    } finally {
      await f.close();
    }
  }
}

Future<void> main() async {
  await runCases(queueCases);
  await runCases(concurrencyCases);
  await runCases(stateCases);
}
