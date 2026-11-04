# Graph Report - my_music_project  (2026-11-02)

## Corpus Check
- Corpus is ~38,209 words - fits in a single context window. You may not need a graph.

## Summary
- 2141 nodes · 2939 edges · 140 communities (75 shown, 65 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 19 edges (avg confidence: 0.84)
- Token cost: unmeasured for host-agent semantic extraction (tool usage unavailable); AST extraction uses no LLM tokens. cost.json zero values are placeholders.

## Community Hubs (Navigation)
- Isar Generated Storage
- Localization Base Strings
- English Translation Strings
- Vietnamese Translation Strings
- Playback Use Cases
- Flutter Project Dependencies
- Apple Platform Bootstrap
- Library Use Case Tests
- Audio Provider State
- Persistent Storage Keys
- Splash and Permission Views
- Application Dependency Injection
- Audio Playback Service
- Product Plans and Privacy
- Player Screen Composition
- Playlist Domain Use Cases
- Playlist Screen Interaction
- Shared Player Widgets
- Isar Query Extensions
- Permission State Management
- Windows Native Window
- Settings and App Entry
- Animated Interface Widgets
- Audio Repository Implementation
- Locale and Sharing Providers
- Audio Repository Contract
- Playlist Provider State
- Application Initialization
- Initialization Use Case Tests
- Playback Preference Storage
- Song Action Dialogs
- Song Domain Entity
- Permission Use Case Tests
- Song Search Screen
- Permission Domain Use Cases
- Launcher Icon Configuration
- Playlist Song Picker
- Windows Flutter Hosting
- Locale Domain Use Cases
- Songs Library Screen
- Playlist Repository Implementation
- Platform Domain Gateway
- Music Repository Implementation
- Playlist Cache Storage
- Windows Window Registration
- Library Loading Workflow
- Music Library Provider
- Home Tab Navigation
- Windows Startup Utilities
- Song Cache Storage
- Locale Use Case Tests
- Result Value Wrapper
- Music Repository Contract
- Playback Event Entities
- Song Item Interaction
- Platform Gateway Implementation
- Playlist Domain Entity
- Web Application Manifest
- Playback Progress Slider
- Music File Operations
- Playlist Storage Record
- App Settings Storage
- Isar Storage Initialization
- Windows Plugin Registration
- Song Model Serialization
- Device Music Queries
- Playback Configuration Contract
- Localization Delegate Types
- Song Entity Tests
- Windows CMake Build
- Isar Collection Models
- Dart Analysis Configuration
- Isar Index Extensions
- Isar Collection Accessors
- Privacy Policy Link
- Local Date Conversion
- Window Point Coordinates
- Android Audio Activity
- Audio Handler Inheritance
- Playback Duration Formatting
- Filename Display Formatting
- Playback Mode Entity
- Audio Notifier Types
- Windows Class Registration
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Nullable Dart Type
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Music Brand Asset
- Launch Placeholder Asset
- Launch Placeholder Asset
- Launch Placeholder Asset
- iOS Launch Customization
- macOS Flutter Icon
- macOS Flutter Icon
- macOS Flutter Icon
- macOS Flutter Icon
- macOS Flutter Icon
- macOS Flutter Icon
- macOS Flutter Icon
- Web Flutter Icon
- Web Flutter Icon
- Web Flutter Icon
- Web Flutter Icon
- Web Flutter Icon

## God Nodes (most connected - your core abstractions)
1. `audioProvider` - 24 edges
2. `Win32Window` - 21 edges
3. `dependencies` - 20 edges
4. `musicProvider` - 18 edges
5. `playlistProvider` - 16 edges
6. `Playlist feature implementation plan` - 14 edges
7. `_SplashPageState` - 12 edges
8. `FlutterWindow` - 10 edges
9. `Pocket Audio` - 10 edges
10. `flutter_launcher_icons` - 9 edges

## Surprising Connections (you probably didn't know these)
- `Playlist feature implementation plan` --semantically_similar_to--> `Planned playlist CRUD and default Favorites`  [INFERRED] [semantically similar]
  docs/playlist_plan.md → CHANGELOG.md
- `Local settings playback and song cache` --semantically_similar_to--> `Isar local database`  [INFERRED] [semantically similar]
  web/index.html → README.md
- `Audio and storage access policy` --semantically_similar_to--> `on_audio_query device scanning`  [INFERRED] [semantically similar]
  web/index.html → README.md
- `User selected operating system sharing` --semantically_similar_to--> `share_plus song sharing`  [INFERRED] [semantically similar]
  web/index.html → README.md
- `_FakeMusicRepository` --implements--> `MusicRepository`  [EXTRACTED]
  test/domain/load_songs_usecase_test.dart → lib/domain/repositories/music_repository.dart

## Import Cycles
- None detected.

## Communities (140 total, 65 thin omitted)

### Community 0 - "Isar Generated Storage"
Cohesion: 0.01
Nodes (348): anyIsarId, _appSettingRecordAttach, _appSettingRecordDeserialize, _appSettingRecordEstimateSize, _appSettingRecordGetId, _appSettingRecordGetLinks, appSettingRecords, AppSettingRecordSchema (+340 more)

### Community 1 - "Localization Base Strings"
Cohesion: 0.02
Nodes (114): addSongs, addToFavorites, addToPlaylist, addToQueue, addToQueueNotImplemented, allSongs, appName, cancel (+106 more)

### Community 2 - "English Translation Strings"
Cohesion: 0.02
Nodes (106): addSongs, addToFavorites, addToPlaylist, addToQueue, addToQueueNotImplemented, allSongs, appName, cancel (+98 more)

### Community 3 - "Vietnamese Translation Strings"
Cohesion: 0.02
Nodes (106): addSongs, addToFavorites, addToPlaylist, addToQueue, addToQueueNotImplemented, allSongs, appName, cancel (+98 more)

### Community 4 - "Playback Use Cases"
Cohesion: 0.04
Nodes (49): _audioRepository, _blockAutoAdvance, _continuePlay, _currentIndex, _currentIndexSubscription, currentSong, _currentSongController, currentSongStream (+41 more)

### Community 5 - "Flutter Project Dependencies"
Cohesion: 0.05
Nodes (42): dependencies, audio_service, diacritic, flutter, flutter_launcher_icons, flutter_localizations, flutter_riverpod, hive_flutter (+34 more)

### Community 6 - "Apple Platform Bootstrap"
Cohesion: 0.06
Nodes (19): audio_service, audio_session, Cocoa, Flutter, FlutterMacOS, Foundation, AppDelegate, RunnerTests (+11 more)

### Community 7 - "Library Use Case Tests"
Cohesion: 0.05
Nodes (30): addSong, cachedSongs, createPlaylist, currentSong, deletePlaylist, deleteSongFromDevice, getCurrentPlaylistId, getLastScanAt (+22 more)

### Community 8 - "Audio Provider State"
Cohesion: 0.06
Nodes (32): cancelSleepTimer, copyWith, currentIndex, currentSong, _currentSongSubscription, dispose, getPlayModeKey, isContinuePlay (+24 more)

### Community 9 - "Persistent Storage Keys"
Cohesion: 0.06
Nodes (29): HiveBoxNames, playlists, settings, songs, englishCode, languageCode, LanguageKeys, vietnameseCode (+21 more)

### Community 10 - "Splash and Permission Views"
Cohesion: 0.07
Nodes (24): appInitializationUseCaseProvider, playlistUseCasesProvider, _SleepTimerCountdown, _SleepTimerCountdownState, SearchPage, _SearchPageState, _checkPermissionAfterSettings, _controller (+16 more)

### Community 11 - "Application Dependency Injection"
Cohesion: 0.06
Nodes (17): appSettingsServiceProvider, audioPlayerHandler, audioRepositoryProvider, audioServiceProvider, loadSongsUseCaseProvider, localeUseCasesProvider, musicRepositoryProvider, permissionRepositoryProvider (+9 more)

### Community 12 - "Audio Playback Service"
Cohesion: 0.06
Nodes (27): _audioPlayer, audioPlayerHandler, _closeControl, dispose, handler, initAudioPlayerHandler, _onSkipToNext, _onSkipToPrevious (+19 more)

### Community 13 - "Product Plans and Privacy"
Cohesion: 0.10
Nodes (25): Release 1.0.0 documented features, Planned filtered playback queue, Planned LoadSongsUseCase scan integration, Planned PlaylistCacheService, Playlist feature implementation plan, Planned horizontal playlist chips, Planned PlaylistNotifier and PlaylistState, Planned PlaylistPage and navigation (+17 more)

### Community 14 - "Player Screen Composition"
Cohesion: 0.09
Nodes (23): build, createState, dispose, initState, _item, _onMoreEvent, _PlayerMoreMenu, PlayerPage (+15 more)

### Community 15 - "Playlist Domain Use Cases"
Cohesion: 0.07
Nodes (26): PlaylistRepositoryImpl, addSong, createPlaylist, deletePlaylist, getCurrentPlaylistId, getPlaylistById, getPlaylists, initDefaultPlaylists (+18 more)

### Community 16 - "Playlist Screen Interaction"
Cohesion: 0.08
Nodes (27): build, _buildAppBar, _buildEmptyState, _buildPlaylistList, _confirmDeletePlaylist, createState, dispose, _getSongCount (+19 more)

### Community 17 - "Shared Player Widgets"
Cohesion: 0.08
Nodes (23): _SleepTimerSheet, _PlaylistTile, _SongPickerItem, actions, AppScaffold, body, build, scrollableAppBar (+15 more)

### Community 18 - "Isar Query Extensions"
Cohesion: 0.07
Nodes (27): AppSettingRecordQueryFilter, AppSettingRecordQueryLinks, AppSettingRecordQueryObject, AppSettingRecordQueryProperty, AppSettingRecordQuerySortBy, AppSettingRecordQuerySortThenBy, AppSettingRecordQueryWhere, AppSettingRecordQueryWhereDistinct (+19 more)

### Community 19 - "Permission State Management"
Cohesion: 0.08
Nodes (20): checkStoragePermission, _mapStatus, _permissionService, requestStoragePermission, checkStoragePermission, PermissionService, requestStoragePermission, checkPermission (+12 more)

### Community 20 - "Windows Native Window"
Cohesion: 0.14
Nodes (6): EnableFullDpiSupportIfAvailable(), EnableNonClientDpiScaling, Win32Window, child_content_, quit_on_close_, window_handle_

### Community 21 - "Settings and App Entry"
Cohesion: 0.09
Nodes (17): appPlatformUseCaseProvider, build, main, MyApp, _accentDecoration, build, _buildLanguageOption, _buildLeadingIcon (+9 more)

### Community 22 - "Animated Interface Widgets"
Cohesion: 0.09
Nodes (14): build, child, SplashBackground, build, fadeAnimation, logo, SplashContent, _buildControlButton (+6 more)

### Community 23 - "Audio Repository Implementation"
Cohesion: 0.08
Nodes (20): AudioRepositoryImpl, _audioService, currentIndex, dispose, duration, isPlaying, pause, play (+12 more)

### Community 24 - "Locale and Sharing Providers"
Cohesion: 0.09
Nodes (14): isInitialized, locale, LocaleNotifier, LocaleState, _localeUseCases, restoreLanguageCode, setLocale, message (+6 more)

### Community 25 - "Audio Repository Contract"
Cohesion: 0.08
Nodes (22): currentIndex, currentIndexStream, discontinuityStream, dispose, duration, isPlaying, pause, play (+14 more)

### Community 26 - "Playlist Provider State"
Cohesion: 0.09
Nodes (19): addSongToPlaylist, clearSelection, copyWith, createPlaylist, currentPlaylistId, deletePlaylist, errorMessage, filterSongs (+11 more)

### Community 27 - "Application Initialization"
Cohesion: 0.09
Nodes (13): AppInitializationGatewayImpl, initialize, AppInitializationGateway, initialize, AppInitializationResult, AppInitializationUseCase, call, _gateway (+5 more)

### Community 28 - "Initialization Use Case Tests"
Cohesion: 0.10
Nodes (16): checkResult, checkStoragePermission, error, getLanguageCode, getLastSongPath, getPermissionDenied, initialize, initialized (+8 more)

### Community 29 - "Playback Preference Storage"
Cohesion: 0.11
Nodes (13): getContinuePlay, getPlayMode, setContinuePlay, setPlayMode, _settingsService, getLanguageCode, getLastSongPath, getPermissionDenied (+5 more)

### Community 30 - "Song Action Dialogs"
Cohesion: 0.11
Nodes (15): build, _DeleteActionTile, DeleteFileAction, icon, iconColor, label, labelColor, onTap (+7 more)

### Community 31 - "Song Domain Entity"
Cohesion: 0.10
Nodes (19): artist, dateAddedMs, dateModifiedMs, duration, extension, getLastPlay, getNumberOfTimesPlayed, id (+11 more)

### Community 32 - "Permission Use Case Tests"
Cohesion: 0.10
Nodes (15): StoragePermissionStatus, checkResult, checkStoragePermission, getLanguageCode, getLastSongPath, getPermissionDenied, languageCode, lastSongPath (+7 more)

### Community 33 - "Song Search Screen"
Cohesion: 0.11
Nodes (15): _animationController, build, _buildBody, _buildNoResults, _clearSearch, createState, dispose, _fadeAnimation (+7 more)

### Community 34 - "Permission Domain Use Cases"
Cohesion: 0.11
Nodes (15): PermissionRepositoryImpl, checkStoragePermission, PermissionRepository, requestStoragePermission, hasDeniedBefore, loadCurrent, _permissionRepository, PermissionSnapshot (+7 more)

### Community 35 - "Launcher Icon Configuration"
Cohesion: 0.11
Nodes (18): flutter_launcher_icons, android, image_path, ios, macos, min_sdk_android, remove_alpha_ios, web (+10 more)

### Community 36 - "Playlist Song Picker"
Cohesion: 0.11
Nodes (16): _buildAppBar, _buildEmptyState, _buildSearchBar, _buildSongList, createState, dispose, initState, isSelected (+8 more)

### Community 37 - "Windows Flutter Hosting"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 38 - "Locale Domain Use Cases"
Cohesion: 0.11
Nodes (15): PreferencesRepositoryImpl, getLanguageCode, getLastSongPath, getPermissionDenied, PreferencesRepository, setLanguageCode, setLastSongPath, setPermissionDenied (+7 more)

### Community 39 - "Songs Library Screen"
Cohesion: 0.13
Nodes (14): build, _buildFilterBar, copyWith, criteria, onMoreEvent, order, _showSortSheet, songs (+6 more)

### Community 40 - "Playlist Repository Implementation"
Cohesion: 0.12
Nodes (13): addSong, createPlaylist, deletePlaylist, getCurrentPlaylistId, getPlaylistById, getPlaylists, initDefaultPlaylists, _playlistCacheService (+5 more)

### Community 41 - "Platform Domain Gateway"
Cohesion: 0.13
Nodes (12): AppPlatformGatewayImpl, AppPlatformGateway, exitApp, openAppSettings, openExternalUrl, shareSong, AppPlatformUseCase, exitApp (+4 more)

### Community 42 - "Music Repository Implementation"
Cohesion: 0.12
Nodes (11): deleteSongFromDevice, getLastScanAt, loadCachedSongs, _musicFileService, _musicQueryService, saveSongCache, scanDeviceSongs, searchSongs (+3 more)

### Community 43 - "Playlist Cache Storage"
Cohesion: 0.12
Nodes (13): addSongToPlaylist, createPlaylist, _currentPlaylistKey, deletePlaylist, _favoritesPlaylistId, getCurrentPlaylistId, getPlaylistById, getPlaylists (+5 more)

### Community 44 - "Windows Window Registration"
Cohesion: 0.15
Nodes (8): Scale(), Size, height, width, Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 45 - "Library Loading Workflow"
Cohesion: 0.14
Nodes (11): deleteSong, isScanning, lastScanAt, LibraryLoadProgress, loadLibrary, LoadSongsUseCase, _musicRepository, _playbackUseCases (+3 more)

### Community 46 - "Music Library Provider"
Cohesion: 0.15
Nodes (11): copyWith, deleteSongFromDevice, errorMessage, isLoading, isScanning, lastScanAt, loadSongs, _loadSongsUseCase (+3 more)

### Community 47 - "Home Tab Navigation"
Cohesion: 0.15
Nodes (6): build, createState, _currentIndex, HomePage, _HomePageState, _switchToSongsTab

### Community 48 - "Windows Startup Utilities"
Cohesion: 0.19
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 49 - "Song Cache Storage"
Cohesion: 0.15
Nodes (12): deleteSongByPath, getCachedSongs, getLastScanAt, _lastScanAtKey, _recordToSongModel, saveSongs, setLastScanAt, SongCacheService (+4 more)

### Community 50 - "Locale Use Case Tests"
Cohesion: 0.15
Nodes (10): getLanguageCode, getLastSongPath, getPermissionDenied, languageCode, lastSongPath, main, permissionDenied, setLanguageCode (+2 more)

### Community 51 - "Result Value Wrapper"
Cohesion: 0.17
Nodes (9): data, error, failure, isFailure, isSuccess, onFailure, onSuccess, Result (+1 more)

### Community 52 - "Music Repository Contract"
Cohesion: 0.17
Nodes (11): MusicRepositoryImpl, deleteSongFromDevice, getLastScanAt, loadCachedSongs, MusicRepository, saveSongCache, scanDeviceSongs, searchSongs (+3 more)

### Community 53 - "Playback Event Entities"
Cohesion: 0.17
Nodes (11): currentIndex, height, isAutoAdvance, left, PlaybackDiscontinuity, PlaybackProcessingState, previousIndex, ShareOrigin (+3 more)

### Community 54 - "Song Item Interaction"
Cohesion: 0.20
Nodes (8): build, currentIndex, index, _onMoreEvent, _playSong, _showDetails, song, _songItemTapLockProvider

### Community 56 - "Platform Gateway Implementation"
Cohesion: 0.18
Nodes (5): exitApp, _fileNameFor, openAppSettings, openExternalUrl, shareSong

### Community 57 - "Playlist Domain Entity"
Cohesion: 0.18
Nodes (9): copyWith, createdAt, id, isDefault, name, Playlist, songCount, songPaths (+1 more)

### Community 58 - "Web Application Manifest"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 59 - "Playback Progress Slider"
Cohesion: 0.24
Nodes (6): positionProvider, build, createState, _localDragValue, ProgressSlider, _ProgressSliderState

### Community 60 - "Music File Operations"
Cohesion: 0.20
Nodes (6): deleteSongFile, MusicFileService, directory, _expectNoForbiddenImports, main, violations

### Community 61 - "Playlist Storage Record"
Cohesion: 0.20
Nodes (7): createdAt, id, isarId, isDefault, name, songPaths, updatedAt

### Community 62 - "App Settings Storage"
Cohesion: 0.20
Nodes (7): getBool, getInt, _getOrCreate, getString, setBool, setInt, setString

### Community 63 - "Isar Storage Initialization"
Cohesion: 0.20
Nodes (4): init, _instance, IsarStorageService, isReady

### Community 65 - "Song Model Serialization"
Cohesion: 0.22
Nodes (7): currentSchemaVersion, fromMap, fromSong, _readInt, SongModel, toMap, Song

### Community 66 - "Device Music Queries"
Cohesion: 0.22
Nodes (4): allowedFoldersAndroid, _audioQuery, loadSongs, MusicQueryService

### Community 67 - "Playback Configuration Contract"
Cohesion: 0.25
Nodes (6): PlayConfigRepositoryImpl, getContinuePlay, getPlayMode, PlayConfigRepository, setContinuePlay, setPlayMode

### Community 68 - "Localization Delegate Types"
Cohesion: 0.33
Nodes (5): AppLocalizations, _AppLocalizationsDelegate, AppLocalizationsEn, of, AppLocalizationsVi

### Community 69 - "Song Entity Tests"
Cohesion: 0.33
Nodes (3): duration, main, _song

### Community 70 - "Windows CMake Build"
Cohesion: 0.47
Nodes (4): C++17 Unicode strict compiler settings, Windows CMake application and install build, Flutter Windows engine and wrappers, Windows runner executable target

### Community 71 - "Isar Collection Models"
Cohesion: 0.40
Nodes (4): AppSettingRecord, CachedSongRecord, SongCacheMetadataRecord, PlaylistRecord

### Community 72 - "Dart Analysis Configuration"
Cohesion: 0.50
Nodes (3): include, linter, rules

### Community 73 - "Isar Index Extensions"
Cohesion: 0.50
Nodes (3): AppSettingRecordByIndex, CachedSongRecordByIndex, SongCacheMetadataRecordByIndex

### Community 74 - "Isar Collection Accessors"
Cohesion: 0.50
Nodes (3): GetAppSettingRecordCollection, GetCachedSongRecordCollection, GetSongCacheMetadataRecordCollection

### Community 76 - "Local Date Conversion"
Cohesion: 0.50
Nodes (4): _, DateConverter, intToLocalDate, localDateToInt

### Community 77 - "Window Point Coordinates"
Cohesion: 0.50
Nodes (3): Point, x, y

## Knowledge Gaps
- **1091 isolated node(s):** `HiveBoxNames`, `settings`, `playlists`, `songs`, `LanguageKeys` (+1086 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1316 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **65 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PreferencesRepository` connect `Locale Domain Use Cases` to `Permission Domain Use Cases`, `Application Dependency Injection`, `Playback Use Cases`?**
  _High betweenness centrality (0.054) - this node is a cross-community bridge._
- **What connects `HiveBoxNames`, `settings`, `playlists` to the rest of the system?**
  _1091 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Isar Generated Storage` be split into smaller, more focused modules?**
  _Cohesion score 0.010975135975135976 - nodes in this community are weakly interconnected._
- **Why does `PlaylistCacheService` connect `Playlist Repository Implementation` to `Application Dependency Injection`, `Playlist Cache Storage`?**
  _High betweenness centrality (0.022) - this node is a cross-community bridge._
- **Should `Localization Base Strings` be split into smaller, more focused modules?**
  _Cohesion score 0.016666666666666666 - nodes in this community are weakly interconnected._
- **Why does `MusicRepository` connect `Music Repository Contract` to `Application Dependency Injection`, `Playback Use Cases`, `Library Loading Workflow`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Should `English Translation Strings` be split into smaller, more focused modules?**
  _Cohesion score 0.018518518518518517 - nodes in this community are weakly interconnected._
## Build Integrity and Scope
- Health warning: 37 dangling-endpoint edges, 2 self-loop edges, and 12 same-endpoint edge collapses in this undirected graph (9 would collapse in directed mode). These limit relationship completeness; the graph remains usable.
- All 8 documents and 48 images reviewed. Seven code files yielded no symbols; generated files and framework symbols dominate several communities.
- Semantic token usage was not exposed by agent tools and is unmeasured, not zero.
- Benchmark: naive baseline ~142,733 tokens (107,050 words), average query ~1,237 tokens, estimated reduction 115.4x. Its corpus counting differs from detect (38,209 words); this is an estimate, not a measured billing reduction.
- graphify-out/ was written into the working tree and currently shows in git status. Add graphify-out/ to .gitignore or commit only outputs your team should share. See https://docs.graphify.com/guides/team-workflows.
