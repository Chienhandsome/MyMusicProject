import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_music_project/di/app_providers.dart';
import 'package:my_music_project/domain/entities/playlist.dart';
import 'package:my_music_project/l10n/app_localizations.dart';
import 'package:my_music_project/presentation/pages/search/search_page.dart';
import 'package:my_music_project/presentation/providers/audio_provider.dart';
import 'package:my_music_project/presentation/providers/music_provider.dart';
import 'package:my_music_project/presentation/providers/playlist_provider.dart';
import '../domain/playback_regression.dart';
import '../support/playback_fakes.dart';

void main() {
  late Fixture f;
  late FakeMusic music;
  late FakePlaylists playlists;
  late ProviderContainer container;
  setUp(() {
    f = Fixture();
    music = FakeMusic()..library = [song(1), song(2), song(3)];
    playlists = FakePlaylists()..selected = 'p';
    playlists.records['p'] = Playlist(
        id: 'p',
        name: 'P',
        songPaths: [song(2).path, song(3).path],
        createdAt: 0);
    container = ProviderContainer(overrides: [
      playbackUseCasesProvider.overrideWithValue(f.playback),
      musicRepositoryProvider.overrideWithValue(music),
      playlistRepositoryProvider.overrideWithValue(playlists),
    ]);
    container.read(audioProvider);
  });
  tearDown(() async {
    container.dispose();
    await f.close();
  });

  Future<void> load() async {
    await container.read(playlistProvider.notifier).loadPlaylists();
    await container.read(musicProvider.notifier).loadSongs();
    await settle();
  }

  test('restored filter and refresh keep UI and player queue aligned',
      () async {
    await load();
    expect(container.read(playlistProvider).currentPlaylistId, 'p');
    expect(f.audio.queue.map((s) => s.id), [2, 3]);
    await container.read(musicProvider.notifier).loadSongs();
    await settle();
    expect(f.audio.queue.map((s) => s.id), [2, 3]);
  });

  test('editing selected playlist changes queue immediately', () async {
    await load();
    final notifier = container.read(playlistProvider.notifier);
    await notifier.removeSongFromPlaylist('p', song(2).path);
    expect(f.audio.queue.map((s) => s.id), [3]);
    await notifier.addSongToPlaylist('p', song(1).path);
    expect(f.audio.queue.map((s) => s.id), [1, 3]);
    await notifier.deletePlaylist('p');
    expect(container.read(playlistProvider).currentPlaylistId, isNull);
    expect(f.audio.queue.map((s) => s.id), [1, 2, 3]);
  });

  test('favorite removal from active favorites clears provider and queue',
      () async {
    music.library[1].isFavorite = true;
    playlists.records['p'] = const Playlist(
        id: 'p',
        name: 'Favorites',
        songPaths: [],
        isDefault: true,
        createdAt: 0);
    await load();
    await container.read(audioProvider.notifier).playSong(song(2).path);
    var playlistUpdates = 0;
    final subscription =
        container.listen(playlistProvider, (_, __) => playlistUpdates++);
    await container.read(audioProvider.notifier).toggleCurrentSongFavorite();
    await settle();
    expect(f.audio.queue, isEmpty);
    expect(container.read(audioProvider).currentSong, isNull);
    expect(playlistUpdates, greaterThan(0));
    subscription.close();
  });

  test('deleting an earlier library file preserves current path and selection',
      () async {
    await load();
    await container.read(audioProvider.notifier).playSong(song(3).path);
    await f.playback.seek(const Duration(seconds: 4));
    await container
        .read(musicProvider.notifier)
        .deleteSongFromDevice(music.library.first);
    await settle();
    expect(f.playback.currentSong?.id, 3);
    expect(f.audio.position.inSeconds, 4);
    expect(f.audio.queue.map((s) => s.id), [2, 3]);
  });

  testWidgets('tap a search result switches to all songs and plays that path',
      (tester) async {
    await tester.runAsync(load);
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SearchPage())));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), '2');
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, '2')).onTap,
        isNotNull);
    await tester.tap(find.widgetWithText(ListTile, '2'));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
      if (f.audio.queue.length == 3 && f.audio.metadata?.id == 2) break;
    }
    expect(playlists.selected, isNull);
    expect(f.audio.queue.map((s) => s.id), [1, 2, 3]);
    expect(f.playback.currentSong?.id, 2);
    expect(f.audio.metadata?.id, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
