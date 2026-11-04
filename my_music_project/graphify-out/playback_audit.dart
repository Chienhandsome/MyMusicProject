// Standalone characterization probes: success means the current defect was reproduced.
// Run with the bundled Dart executable; no packages or device are required.
import 'dart:async';
import '../lib/domain/entities/play_mode.dart';
import '../lib/domain/entities/playback_event.dart';
import '../lib/domain/entities/song.dart';
import '../lib/domain/repositories/audio_repository.dart';
import '../lib/domain/repositories/music_repository.dart';
import '../lib/domain/repositories/play_config_repository.dart';
import '../lib/domain/repositories/preferences_repository.dart';
import '../lib/domain/usecases/playback_usecases.dart';

Song song(int id) => Song(id: id, title: '$id', path: '/$id.mp3', duration: 10000);
void check(bool ok, String message) { if (!ok) throw StateError(message); }
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 15));

class Audio implements AudioRepository {
  final playing = StreamController<bool>.broadcast(sync: true);
  final processing = StreamController<PlaybackProcessingState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final indices = StreamController<int?>.broadcast(sync: true);
  final discontinuities = StreamController<PlaybackDiscontinuity>.broadcast(sync: true);
  List<Song> queue = [];
  Song? metadata;
  Duration position = Duration.zero;
  int? index;
  bool active = false;
  bool failPlay = false;
  @override int? get currentIndex => index;
  @override bool get isPlaying => active;
  @override Duration? get duration => const Duration(seconds: 10);
  @override double get speed => 1;
  @override Stream<bool> get playingStream => playing.stream;
  @override Stream<PlaybackProcessingState> get processingStateStream => processing.stream;
  @override Stream<Duration> get positionStream => positions.stream;
  @override Stream<int?> get currentIndexStream => indices.stream;
  @override Stream<PlaybackDiscontinuity> get discontinuityStream => discontinuities.stream;
  @override Future<void> setPlaylist(List<Song> songs, {int initialIndex = 0}) async {
    queue = List.of(songs); index = songs.isEmpty ? null : initialIndex; position = Duration.zero;
  }
  @override Future<void> seekToIndex(int value) async { index = value; position = Duration.zero; }
  @override Future<void> setCurrentSong(Song value) async { metadata = value; }
  @override Future<void> play() async {
    if (failPlay) throw StateError('decoder failure');
    active = true; playing.add(true);
  }
  @override Future<void> pause() async { active = false; playing.add(false); }
  @override Future<void> stop() => pause();
  @override Future<void> seek(Duration value) async { position = value; }
  @override Future<void> setPlayMode(PlayMode mode, {required bool continuePlay}) async {}
  @override void setNotificationCallbacks({required Future<void> Function() onSkipToNext, required Future<void> Function() onSkipToPrevious}) {}
  @override void dispose() { playing.close(); processing.close(); positions.close(); indices.close(); discontinuities.close(); }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class Prefs implements PreferencesRepository {
  String? last;
  Completer<void>? gate;
  String? gatePath;
  @override String? getLastSongPath() => last;
  @override Future<void> setLastSongPath(String path) async {
    if (path == gatePath) await gate!.future;
    last = path;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class Config implements PlayConfigRepository {
  bool continuous = false;
  @override PlayMode getPlayMode() => PlayMode.sequential;
  @override bool getContinuePlay() => continuous;
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class Music implements MusicRepository {
  @override Future<void> updatePlaybackStats(Song song, {required int lastPlay, required int numberOfTimesPlayed}) async {}
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Future<void> probe(String label, Future<void> Function(PlaybackUseCases, Audio, Prefs) body) async {
  final a = Audio(); final p = Prefs(); final u = PlaybackUseCases(a, p, Config(), Music());
  try { await body(u, a, p); print('REPRODUCED: $label'); }
  finally { await settle(); u.dispose(); a.dispose(); }
}
Future<void> main() async {
  await probe('reordered queue changes current song by numeric index', (u, a, p) async {
    final x= song(1), y= song(2), z= song(3);
    await u.setPlaylist([x,y,z]); await u.playSongAt(1);
    await u.setPlaylist([z,x,y]);
    check(u.currentSong == x && p.last == y.path, 'expected identity mismatch');
  });
  await probe('refresh resets playback position even with identical queue', (u,a,p) async {
    final list = [song(1),song(2)];
    await u.setPlaylist(list); await u.playSongAt(0); await u.seek(const Duration(seconds: 5));
    await u.setPlaylist(list);
    check(a.position == Duration.zero, 'expected position reset');
  });
  await probe('non-continuous playback pauses before actual track end', (u,a,p) async {
    await u.setPlaylist([song(1)]); await u.playSongAt(0);
    a.positions.add(const Duration(milliseconds: 9800)); await settle();
    check(!a.active && a.position == Duration.zero, 'expected premature pause');
  });
  await probe('old completion callback pauses newly selected song', (u,a,p) async {
    await u.setPlaylist([song(1),song(2)]); await u.playSongAt(0);
    a.processing.add(PlaybackProcessingState.completed);
    await u.playSongAt(1); await settle();
    check(u.currentIndex == 1 && !a.active, 'expected stale completion to pause new track');
  });
  await probe('overlapping selections leave metadata and saved path on old song', (u,a,p) async {
    final x=song(1),y=song(2);
    await u.setPlaylist([x,y]); await u.playSongAt(0);
    p.gate=Completer<void>(); p.gatePath=x.path;
    final first=u.playSongAt(0); await settle();
    await u.playSongAt(1); p.gate!.complete(); await first;
    check(u.currentSong==y && a.index==1 && a.metadata==x && p.last==x.path, 'expected stale metadata');
  });
  await probe('play failure returns success and records a play', (u,a,p) async {
    final x=song(1); await u.setPlaylist([x]); a.failPlay=true;
    await u.playSongAt(0); await settle();
    check(!a.active && x.numberOfTimesPlayed==1, 'expected swallowed play failure');
  });
  await probe('global search index selects wrong song in filtered queue', (u,a,p) async {
    final all=[song(1),song(2),song(3)]; final selected=[all[1],all[2]];
    await u.setPlaylist(selected);
    final globalIndex=all.indexOf(all[1]); await u.playSongAt(globalIndex);
    check(u.currentSong==all[2], 'expected wrong selected track');
  });
}
