---
title: "Milestone 14: The full test suite"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 14
aliases:
  - Milestone 14
updated: 2026-11-06
---
# Milestone 14: The full test suite

The tests mirror `lib/`: unit tests for each layer sit next to their feature's path under `test/src/features/`, written in the milestone that built the code, and three app-wide widget tests sit in `test/src/`. All of them run with plain `flutter test`, no device needed, and CI from [[Milestone 02 - Release pipeline for beta and stable|milestone 2]] runs them on every pull request and before every release.

| File | What it checks | How |
| --- | --- | --- |
| `features/app_update/domain/app_release_test.dart` | Version codes, channel rules, CPU fallback, checksums ([[Milestone 03 - In-app updates\|milestone 3]]) | Plain unit tests on domain functions |
| `features/app_update/data/releases_repository_test.dart` | GitHub JSON parsing, request URL and headers, rate-limit errors ([[Milestone 03 - In-app updates\|milestone 3]]) | The real repository over a Dio with a canned HTTP adapter |
| `features/app_update/application/app_update_service_test.dart` | Picking the update per channel, recording the check, the 20-hour rule ([[Milestone 04 - Preferences and the local database\|milestone 4]]) | `ProviderContainer` with fakes and an in-memory database |
| `features/library/domain/library_filter_test.dart` | Tri-state filters, sources, tags (all or any), sorting, `Work.matchesQuery` ([[Milestone 06 - The library\|milestone 6]]) | Plain unit tests against the sample works |
| `features/reader/data/chapters_repository_test.dart` | The demo chapter failure and normal loading ([[Milestone 08 - The reader and open works\|milestone 8]]) | The repository with zero latency |
| `theme/app_theme_test.dart` | The Dynamic theme’s schemes: brightness, surface container order, readable on-colours ([[Milestone 05 - Theming and the app shell\|milestone 5]]) | Unit tests on `schemesFromPalettes` with hand-made tonal palettes |
| `app_smoke_test.dart` | Every screen, including the update page and changelog, lays out without overflow at phone (412 × 915) and tablet (1280 × 800) size | Pushes each route on the real `AppRouter`, pumps, and fails on any framework exception |
| `app_flows_test.dart` | Coach marks; the save prompt (after N chapters and on leaving); setup → tour → library; the launch check offering an update and the download starting | Taps through the flows with an in-memory Drift database and fake releases and installer |
| `screenshots_test.dart` | Captures this guide’s screenshots | Loads Inter and Literata from `test/fonts/`, renders through a `RepaintBoundary`; only runs with `--dart-define=SCREENSHOTS=true` |

The pattern every widget test uses: override the startup providers and the outside-facing repositories instead of touching real storage or the network.

```dart
final db = AppDatabase(NativeDatabase.memory());
await tester.pumpWidget(ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    initialPrefsProvider.overrideWithValue({Prefs.setupDone.key: 'true', Prefs.tourDone.key: 'true'}),
    initialTabsProvider.overrideWithValue(TabsRepository.firstLaunchTabs),
    releasesRepositoryProvider.overrideWithValue(const FakeReleasesRepository()), // never hit GitHub
    apkInstallerProvider.overrideWithValue(FakeApkInstaller()),
    initialSessionProvider.overrideWithValue(const Session(userId: 'u1', kind: AuthKind.password, server: 'sync.noctua.app')),
  ],
  child: NoctuaApp(router: AppRouter()),
));
```

Things that bit during development, so you don’t repeat them:

- Flutter’s test font draws every glyph as a wide box, so layouts that barely fit on a device overflow in tests. Treat that as a free large-text test and fix the layout (`Expanded`, `OverflowBar`, ellipsis) rather than the test.
- `router.push` returns a future that completes only when the route is popped. Never `await` it in a test.
- The flow tests need `libsqlite3` on the machine for the in-memory database; GitHub’s Ubuntu runners have it.

## Code walkthrough: milestone 14

Every test starts the real app with the same overrides, so the providers that normally read the database, the device or GitHub get test values instead. That one pattern is what makes the whole app testable without a device.

**Step 1: the smoke test.** Opens every page at phone and tablet size and fails on any layout error. 32 routes × 2 sizes = 64 tests, written as one loop:

```dart
// Renders every screen once at phone and tablet sizes and fails on layout errors
// (overflows, unbounded constraints). Run with: flutter test
import 'package:auto_route/auto_route.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:noctua/src/app.dart';
import 'package:noctua/src/database/app_database.dart';
import 'package:noctua/src/features/app_update/data/apk_installer.dart';
import 'package:noctua/src/features/app_update/data/fake_apk_installer.dart';
import 'package:noctua/src/features/app_update/data/fake_releases_repository.dart';
import 'package:noctua/src/features/app_update/data/installed_app_reader.dart';
import 'package:noctua/src/features/app_update/data/releases_repository.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
import 'package:noctua/src/features/auth/data/session_repository.dart';
import 'package:noctua/src/features/auth/domain/session.dart';
import 'package:noctua/src/features/tabs/data/tabs_repository.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:noctua/src/routing/app_router.dart';
import 'package:noctua/src/routing/app_router.gr.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  final routes = <String, PageRouteInfo>{
    'setup': const SetupRoute(),
    'tour': const TourRoute(),
    'home': const HomeShellRoute(),
    'details salt': WorkDetailsRoute(workId: 'salt'),
    'details convergence': WorkDetailsRoute(workId: 'convergence'),
    'reader': ReaderRoute(workId: 'lighthouse-map', chapter: 1),
    'series': SeriesRoute(seriesId: 'keepers'),
    'author': AuthorRoute(name: 'tidewright'),
    'warning': ContentWarningRoute(workId: 'small-hours'),
    'highlights': HighlightsRoute(),
    'deep search': const DeepSearchRoute(),
    'import': const ImportRoute(),
    'repos': const ExtensionReposRoute(),
    'source settings': SourceSettingsRoute(sourceId: 'ao3'),
    'source login': SourceLoginRoute(sourceId: 'ao3'),
    'settings': const SettingsRoute(),
    'appearance': const AppearanceSettingsRoute(),
    'library settings': const LibrarySettingsRoute(),
    'covers': const CoverSettingsRoute(),
    'ai': const AiSettingsRoute(),
    'archive': const CommunityArchiveRoute(),
    'server data': const ServerDataRoute(),
    'devices': const DevicesRoute(),
    'restore': const RestoreBackupRoute(),
    'muted': const MutedTagsRoute(),
    'categories': const EditCategoriesRoute(),
    'account': const AccountRoute(),
    'source sign-ins': const AccountsSettingsRoute(),
    'data': const DataSettingsRoute(),
    'about': const AboutRoute(),
    'app update': const AppUpdateRoute(),
    'changelog': const ChangelogRoute(),
  };

  for (final size in const [Size(412, 915), Size(1280, 800)]) {
    for (final MapEntry(key: name, value: route) in routes.entries) {
      testWidgets('$name at ${size.width.round()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final router = AppRouter();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              initialPrefsProvider.overrideWithValue({
                Prefs.setupDone.key: 'true',
                Prefs.tourDone.key: 'true',
                Prefs.autoCheckAppUpdates.key: 'false',
              }),
              initialTabsProvider.overrideWithValue(TabsRepository.firstLaunchTabs),
              releasesRepositoryProvider.overrideWithValue(const FakeReleasesRepository()),
              apkInstallerProvider.overrideWithValue(FakeApkInstaller()),
              installedAppProvider.overrideWithValue(installedForTests),
              initialSessionProvider.overrideWithValue(
                const Session(userId: 'u1', kind: AuthKind.password, server: 'sync.noctua.app', username: 'reader'),
              ),
            ],
            child: NoctuaApp(router: router),
          ),
        );
        await tester.pump();
        router.push(route);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        final e = tester.takeException();
        expect(e, isNull, reason: '$e');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}

/// A stable 0.6.0 install, so the sample 0.6.1 release is an update.
const installedForTests = InstalledApp(channel: UpdateChannel.stable, versionName: '0.6.0', versionCode: 600999, abis: ['arm64-v8a']);
```

- `GoogleFonts.config.allowRuntimeFetching = false` stops google_fonts from trying to download fonts during tests. Text falls back to the test font, which is fine for layout checks.
- `tester.view.physicalSize` with `devicePixelRatio = 1` sets the logical screen size; `addTearDown(tester.view.reset)` restores it for the next test.
- The overrides replace every outside dependency: an in-memory database, fixed preferences (setup and tour done, automatic update checks off so no snackbar appears), sample tabs, the fake releases repository and installer, a fixed installed version and a signed-in session.
- Navigation happens through the real router (`router.push(route)`), so route arguments are checked too.
- `pump` with a duration advances the fake clock; six steps of 300 ms let page transitions and short timers finish. `pumpAndSettle` would hang on pages with repeating animations.
- `tester.takeException()` returns the first error the framework caught, including overflows ("A RenderFlex overflowed by 12 pixels"). Expecting null is what turns a layout bug into a failing test.
- The final `pumpWidget(const SizedBox())` plus a 3-second pump disposes the app and lets pending timers run, so no test leaves timers behind (which fails the test).
- `installedForTests` is a stable 0.6.0 install, so the fake repository's 0.6.1 release is an update and its 0.7.0 beta is not.

**Step 2: flow tests.** Interactions across screens: taps, dialogs, preferences. A shared `_start` helper takes extra preferences for each test:

```dart
Future<AppRouter> _start(WidgetTester tester, Map<String, String> prefs) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final router = AppRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialPrefsProvider.overrideWithValue({
          Prefs.setupDone.key: 'true',
          Prefs.tourDone.key: 'true',
          Prefs.autoCheckAppUpdates.key: 'false',
          ...prefs,
        }),
        initialTabsProvider.overrideWithValue(TabsRepository.firstLaunchTabs),
        releasesRepositoryProvider.overrideWithValue(const FakeReleasesRepository()),
        apkInstallerProvider.overrideWithValue(FakeApkInstaller()),
        installedAppProvider.overrideWithValue(installedForTests),
        initialSessionProvider.overrideWithValue(
          const Session(userId: 'u1', kind: AuthKind.password, server: 'sync.noctua.app', username: 'reader'),
        ),
      ],
      child: NoctuaApp(router: router),
    ),
  );
  await tester.pump();
  return router;
}
```

Then each flow is a short script. The save prompt, for example:

```dart
  testWidgets('save prompt appears after N chapters of an unsaved work', (tester) async {
    final router = await _start(tester, {Prefs.savePromptAfter.key: '2'});
    router.push(ReaderRoute(workId: 'lighthouse-map', chapter: 1));
    await _settle(tester);
    await tester.tap(find.byTooltip('Next chapter'));
    await _settle(tester);
    expect(find.text('Enjoying it?'), findsNothing, reason: 'only one chapter read so far');
    await tester.tap(find.byTooltip('Next chapter'));
    await _settle(tester);
    expect(find.text('Enjoying it?'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.text('Enjoying it?'), findsNothing);
  });
```

- `find.byTooltip('Next chapter')` finds buttons by their tooltip, which every icon button has for accessibility anyway, so tests don't need extra keys.
- `reason:` on an `expect` explains the intent when it fails.
- Preferences passed to `_start` set up the scenario (`savePromptAfter: 2`) without touching any UI.

The in-app update flow runs the launch check, opens the update page and watches the fake download:

```dart
  testWidgets('launch check offers the update, and the update page downloads it', (tester) async {
    await _start(tester, {Prefs.autoCheckAppUpdates.key: 'true'});
    await _settle(tester);
    expect(find.text('Noctua 0.6.1 is available'), findsOneWidget, reason: 'stable install skips the 0.7.0 beta');
    await tester.tap(find.text('View'));
    await _settle(tester);
    expect(find.text('Noctua 0.6.1'), findsOneWidget);
    expect(find.text('Mihon themes and pure black dark mode'), findsOneWidget);
    await tester.tap(find.textContaining('Download and install'));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.textContaining('Downloading'), findsOneWidget);
    await _settle(tester);
    expect(find.text('Opening the installer…'), findsOneWidget);
  });
```

The `pump(450 ms)` between tapping download and checking "Downloading" lands in the middle of `FakeApkInstaller`'s 200 ms steps, so the progress state is visible to the test.

**Step 3: the layer tests.** The files under `test/src/features/` were written alongside their features, one per layer, and need no widgets:

- Domain: plain `test()` calls on Dart functions and models (`app_release_test.dart`, `library_filter_test.dart`). The more rules live in the domain, the more of the app is covered by these fast tests.
- Data: the real repository against a fake source, such as a Dio with a canned HTTP adapter (`releases_repository_test.dart`) or the sample chapter source (`chapters_repository_test.dart`).
- Application: a `ProviderContainer` with the same overrides as the app and an in-memory database (`app_update_service_test.dart`).

Presentation is covered by the smoke and flow tests above, which drive the real controllers through the screens.

**Step 4: screenshots.** `test/src/screenshots_test.dart` renders the screens in this guide with real fonts and writes PNGs. It is skipped unless you pass `--dart-define=SCREENSHOTS=true`, so it doesn't slow down CI:

```bash
flutter test test/src/screenshots_test.dart --dart-define=SCREENSHOTS=true   # writes build/screenshots/*.png
```

Three techniques make it work. First, real fonts: widget tests normally draw every glyph as a box, so the test registers Inter, Literata and Material Symbols from files with `FontLoader`, under every name google_fonts asks for:

```dart
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  final config = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  final symbols = Uri.parse(
    ((config['packages'] as List).cast<Map<String, dynamic>>()).firstWhere((p) => p['name'] == 'material_symbols_icons')['rootUri']
        as String,
  ).toFilePath();
  // google_fonts asks for '<Family>_<variant>' (Inter_regular, Inter_600, Literata_italic…), so register
  // the variable fonts under every variant name it can use.
  const variants = [
    'regular',
    'italic',
    '100',
    '200',
    '300',
    '500',
    '600',
    '700',
    '800',
    '900',
    '100italic',
    '200italic',
    '300italic',
    '500italic',
    '600italic',
    '700italic',
    '800italic',
    '900italic',
  ];
  for (final family in ['Inter', 'Literata']) {
    await load(family, ['test/fonts/$family.ttf']);
    for (final v in variants) {
      await load('${family}_$v', ['test/fonts/$family.ttf']);
    }
  }
  await load('Roboto', ['test/fonts/Inter.ttf']);
  // Framework icons (back arrow, overflow menu) use MaterialIcons, which ships with the Flutter SDK.
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
```

Second, capturing: the app is wrapped in a `RepaintBoundary` with a key, and `toImage` renders that boundary to a bitmap. Image encoding is real async work, so it runs inside `tester.runAsync`, outside the fake clock:

```dart
Future<void> _shot(WidgetTester tester, String name) async {
  // Mid-download shots must not wait, or the fake download finishes first.
  await _settle(tester, name.contains('downloading') ? 0 : 4);
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/screenshots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}
```

Third, the logo asset is decoded the same way before the app starts, because asset images also decode outside the fake clock and would otherwise be blank in the first frames.

Each screenshot is then a few lines:

```dart
shot('m03_downloading', (t) async {
  unawaited((await _start(t)).push(const AppUpdateRoute()));
  await _settle(t);
  await t.tap(find.textContaining('Download and install'));
  await t.pump(const Duration(milliseconds: 650));
});
```

**Step 5: run everything.** The same commands CI runs:

```bash
dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

`flutter test` runs all the test files in parallel; on a laptop it takes well under a minute.

> [!success] Checkpoint
> `flutter analyze` reports no issues and `flutter test` passes all 97 tests in about 25 seconds (the 31 screenshot tests are skipped unless you ask for them).

---
← [[Milestone 13 - Errors, tablets and e-ink]] · [[00 Index|Index]] · [[Release checklist and next steps]] →
