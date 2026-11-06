---
title: "Milestone 13: Errors, tablets and e-ink"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 13
aliases:
  - Milestone 13
updated: 2026-11-06
---
# Milestone 13: Errors, tablets and e-ink

The last UI milestone makes failures visible and reportable, and adapts the app to big screens and e-paper.

1. **Crash handling (`lib/src/exceptions/crash_guard.dart`):** `CrashGuard.install(router)` sets `FlutterError.onError` and `PlatformDispatcher.instance.onError`, then pushes `CrashRoute` with the error and stack. It is shared code in `exceptions/` and only needs the router, which it is given in `main()`.
2. **`errors/` feature:** a crash screen (restart, copy details, report), an error report form, and feedback (bug, idea or source problem). `data/github_issue.dart` builds a pre-filled GitHub issue URL that `url_launcher` opens; set `githubOwner` (from [[Milestone 03 - In-app updates|milestone 3]]) to your account. The reader’s chapter error from [[Milestone 08 - The reader and open works|milestone 8]] links here.
3. **Tablets:**
   - From 840 dp the shell swaps its bottom bar for a `NavigationRail`.
   - At the LARGE breakpoint (1200 dp and up, where `context.useTwoPanes` is true) the library becomes two panes: tapping a work sets `TabletDetailController` (in `library/presentation/`) and the details page renders in a 440 dp pane on the right instead of being pushed. Because responsive\_framework works out the breakpoint once for the whole tree, the rail (EXPANDED, from 840 dp) and the two panes always switch at the same widths on every screen.
   - The cover grid ignores the phone column setting on wide screens and fits as many \~140 dp columns as there is room for.
4. **E-ink:** the E-ink theme is pure black and white with no ripples or page transitions. Covers become outlined white cards, the reader uses the Paper page color, and Settings › E-ink display adds a full-refresh interval and page-button support.

## Code walkthrough: milestone 13

**Step 1: catching crashes.** Flutter reports errors through two hooks: `FlutterError.onError` for errors inside the framework (build, layout, paint), and `PlatformDispatcher.instance.onError` for everything else (uncaught async errors). `CrashGuard` sets both, and sends the user to a crash screen instead of a red box or a frozen app:

```dart
import 'package:flutter/foundation.dart';
import 'package:noctua/src/routing/app_router.dart';
import 'package:noctua/src/routing/app_router.gr.dart';

/// Sends uncaught errors to the crash screen instead of a red box or a dead app.
///
/// In debug builds, framework errors (layout overflows and the like) are only
/// printed, so the crash screen doesn't fire while you're iterating on UI.
abstract final class CrashGuard {
  static AppRouter? _router;
  static bool _showing = false;

  static void install(AppRouter router) {
    _router = router;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (kReleaseMode) report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true;
    };
  }

  static void report(Object error, StackTrace? stack) {
    final router = _router;
    if (router == null || _showing) return;
    _showing = true;
    // Defer: the error may have been thrown mid-build.
    Future(() => router.replaceAll([CrashRoute(error: error.toString(), stack: stack?.toString() ?? '')]));
  }

  /// Called when the user leaves the crash screen.
  static void reset() => _showing = false;
}
```

- `FlutterError.presentError` keeps the normal console output. Only release builds go to the crash screen for framework errors, so a layout overflow while you're developing doesn't throw you out of the screen you're working on.
- Returning `true` from `PlatformDispatcher.onError` marks the error as handled, so the engine doesn't also kill the isolate.
- `_showing` stops an error loop (an error on the crash screen itself) from pushing crash screens forever.
- `Future(() => …)` defers navigation to the next event-loop turn, because the error may have been thrown in the middle of a build, when navigating is not allowed.

Install it in `main()` right after creating the router, before `runApp`:

```dart
final router = AppRouter();
CrashGuard.install(router);
runApp(ProviderScope(overrides: [...], child: NoctuaApp(router: router)));
```

That is the last line `main()` needs. The finished file, with everything milestones 4, 5, 8 and 11 added:

```dart
import 'package:dynamic_color/dynamic_color.dart' show DynamicColorPlugin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noctua/flavors.dart';
import 'package:noctua/src/app.dart';
import 'package:noctua/src/database/app_database.dart';
import 'package:noctua/src/exceptions/crash_guard.dart';
import 'package:noctua/src/features/app_update/data/installed_app_reader.dart';
import 'package:noctua/src/features/auth/data/session_repository.dart';
import 'package:noctua/src/features/tabs/data/tabs_repository.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:noctua/src/routing/app_router.dart';
import 'package:noctua/src/theme/app_theme.dart';

Future<void> main() async {
  // Keep the native splash (flutter_native_splash) up until preferences, tabs
  // and the session are loaded, so the first frame is already the right screen.
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // flutter_flavorizr's Flavor, from `flutter run/build --flavor stable|beta`.
  F.appFlavor = Flavor.values.asNameMap()[appFlavor] ?? Flavor.stable;

  // Read preferences and open tabs before the first frame, so the app opens
  // in the saved theme with the saved tabs.
  final db = AppDatabase();
  final prefs = await db.loadPreferences();
  final tabs = await TabsRepository.restore(db, prefs);

  final session = await SessionRepository.restore(prefs);

  // Material You colours for the Dynamic theme (Android 12+). dynamic_color
  // returns null on older Android and other platforms, and then Dynamic is hidden.
  (ColorScheme, ColorScheme)? dynamicSchemes;
  try {
    final p = await DynamicColorPlugin.getCorePalette();
    if (p != null) {
      dynamicSchemes = schemesFromPalettes(
        primary: p.primary,
        secondary: p.secondary,
        tertiary: p.tertiary,
        neutral: p.neutral,
        neutralVariant: p.neutralVariant,
      );
    }
  } on Object {
    dynamicSchemes = null; // no plugin (tests, desktop): no Dynamic theme
  }

  // Version, channel (from the flavor) and CPU types, for in-app updates.
  final installed = await readInstalledApp();

  final router = AppRouter();
  CrashGuard.install(router);

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialPrefsProvider.overrideWithValue(prefs),
        initialTabsProvider.overrideWithValue(tabs),
        initialSessionProvider.overrideWithValue(session),
        dynamicSchemesProvider.overrideWithValue(dynamicSchemes),
        installedAppProvider.overrideWithValue(installed),
      ],
      child: NoctuaApp(router: router),
    ),
  );
  FlutterNativeSplash.remove();
}
```

**Step 2: the crash screen.** It can't be dismissed with back (`PopScope(canPop: false)`); the user chooses to restart, report or copy the log:

```dart
@RoutePage()
class CrashPage extends ConsumerStatefulWidget {
  const CrashPage({super.key, required this.error, this.stack = ''});
  final String error;
  final String stack;

  @override
  ConsumerState<CrashPage> createState() => _CrashPageState();
}

class _CrashPageState extends ConsumerState<CrashPage> {
  String get _appLabel => _versionLabel(ref);

  bool _open = false;
  bool _reopen = true;

  String get _log => 'Noctua $_appLabel\n${widget.error}\n${widget.stack}'.trim();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabCount = ref.watch(tabsRepositoryProvider).length;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: c.errorContainer,
                  child: Icon(Symbols.bug_report_rounded, size: 36, color: c.onErrorContainer),
                ),
              ),
              const SizedBox(height: 16),
              Text('Noctua stopped unexpectedly', style: context.text.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Your library, downloads and reading progress are safe. A crash report helps fix this. '
                'It never includes what you read or your sign-ins.',
                style: context.text.bodyLarge?.copyWith(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Card.filled(
                margin: EdgeInsets.zero,
                color: c.surfaceContainer,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(widget.error.split('\n').first, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: const Text('Tap to see the details'),
                      trailing: Icon(_open ? Symbols.expand_less_rounded : Symbols.expand_more_rounded),
                      onTap: () => setState(() => _open = !_open),
                    ),
                    if (_open)
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.outlineVariant)),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(_log, style: _mono(context)),
                        ),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reopen my open works'),
                subtitle: Text('$tabCount works, at the page you were on'),
                value: _reopen,
                onChanged: (v) => setState(() => _reopen = v),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.router.push(ErrorReportRoute(error: widget.error, where: 'App crash', log: _log)),
                icon: const Icon(Symbols.send_rounded),
                label: const Text('Send crash report'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  if (!_reopen) ref.read(tabsRepositoryProvider.notifier).closeAll();
                  CrashGuard.reset();
                  context.router.replaceAll([const HomeShellRoute()]);
                },
                icon: const Icon(Symbols.restart_alt_rounded),
                label: const Text('Restart Noctua'),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _log));
                  showPlaceholder(context, 'Crash log copied');
                },
                child: const Text('Copy crash log'),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

- "Restart" doesn't restart the process. It clears `CrashGuard._showing` and replaces the stack with the home shell, which rebuilds every screen from providers that survived the error.
- "Reopen my open works" defaults to on; turning it off closes all tabs first, in case one of them caused the crash.
- `SelectableText` lets the user select part of the stack trace; "Copy crash log" copies all of it.

A version label used by every report:

```dart
/// "0.7.0-beta.2 (70002) · beta", for logs and reports.
String _versionLabel(WidgetRef ref) {
  final app = ref.read(installedAppProvider);
  return '${app.versionName} (${app.versionCode}) · ${app.channel.name}';
}
```

**Step 3: reports without a backend.** Reports go to GitHub Issues. Opening the "new issue" page with the fields filled in needs no server and no token: the user reviews the text and submits it with their own account.

```dart
import 'package:noctua/src/constants/app_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens GitHub's "new issue" page with the title, body and labels filled in.
/// No backend needed: the user reviews and submits it with their own account.
Future<bool> openGithubIssue({required String title, required String body, List<String> labels = const []}) {
  final uri = Uri.https('github.com', '/$githubRepo/issues/new', {
    'title': title,
    'body': body,
    if (labels.isNotEmpty) 'labels': labels.join(','),
  });
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
```

`Uri.https(host, path, queryParameters)` handles the URL encoding of the body, including newlines and Markdown. `LaunchMode.externalApplication` opens the browser (or GitHub's app) rather than an in-app web view, so the user's GitHub sign-in is available.

The report page lets the user choose what to include and previews the exact issue text:

```dart
class _ErrorReportPageState extends ConsumerState<ErrorReportPage> {
  String get _appLabel => _versionLabel(ref);

  final _note = TextEditingController();
  final _include = {'device': true, 'log': true, 'url': true, 'shot': false};
  bool _preview = true;

  static const _parts = [
    ('device', 'Device and app info', 'Noctua version, Android version, model'),
    ('log', 'Recent log', 'Last 200 lines, with cookies stripped'),
    ('url', 'Page address', 'The page that failed'),
    ('shot', 'Screenshot', 'Of the screen before the error'),
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _body {
    final b = StringBuffer('## Error\n${widget.error}\n${widget.where}\n');
    if (_note.text.trim().isNotEmpty) b.write('\n## What I was doing\n${_note.text.trim()}\n');
    if (_include['device']!) b.write('\n## Device\nNoctua $_appLabel · Android · [device model]\n');
    if (_include['url']!) b.write('\n## Page\n[address of the page that failed]\n');
```

The body is built with a `StringBuffer`, adding a Markdown section per included part, so what the preview shows is exactly what is sent. GitHub limits a URL to about 8,000 characters; trim the log excerpt to the last lines if you include long logs.

The feedback page (`FeedbackPage`, reached from About) uses the same helper with a type picker (bug, idea, source problem) that maps to issue labels.

**Step 4: the chapter error state.** Built in [[Milestone 08 - The reader and open works|milestone 8]] (`_ChapterError`), driven by the `ChapterLoadException` from `chapterTextProvider`. Its "Report this error" button pushes `ErrorReportRoute` with the source's error (`SRC_HTTP_503: AO3 returned 503…`) and the chapter and site as `where`, so source problems arrive with enough context to reproduce.

**Step 5: tablets.** The pieces were added in earlier milestones, all keyed off the breakpoints from [[Milestone 05 - Theming and the app shell|milestone 5]]:

- `context.useNavigationRail` (EXPANDED, from 840 dp) switches the shell from a bottom bar to a rail ([[Milestone 05 - Theming and the app shell|milestone 5]], step 8).
- `context.useTwoPanes` (LARGE, from 1200 dp) makes the library a two-pane layout, with `tabletDetailControllerProvider` holding the selected work ([[Milestone 06 - The library|milestone 6]], steps 6 and 8).
- From 600 dp the cover grid sizes its columns from the width instead of the phone setting ([[Milestone 06 - The library|milestone 6]], step 7).

The detail pane reuses `WorkDetailsPage` unchanged. `ValueKey(id)` on it makes Flutter build a fresh page (and fresh expanded/sort state) when the selected work changes, rather than reusing the previous work's `State`:

```dart
SizedBox(
  width: 440,
  child: switch (ref.watch(tabletDetailControllerProvider)) {
    null => Center(child: Text('Pick a work to see its details', /* … */)),
    final id => WorkDetailsPage(key: ValueKey(id), workId: id),
  },
),
```

Test it on an emulator with a tablet profile, or in a widget test with `tester.view.physicalSize = const Size(1280, 800)` and `tester.view.devicePixelRatio = 1` ([[Milestone 14 - The full test suite|milestone 14]]).

**Step 6: e-ink.** E-ink is a theme, not a mode spread through the code. Most of it is already in place:

- `einkScheme` (black, white, grays) and `buildTheme(eink: true)` turn off ripples and page transitions, and add the `EinkMarker` extension ([[Milestone 05 - Theming and the app shell|milestone 5]], steps 1 and 3).
- Widgets that draw large color fills check `context.isEink`: covers become outlined white cards ([[Milestone 06 - The library|milestone 6]], step 3), the reader forces the Paper page color and skips the warm-light overlay ([[Milestone 08 - The reader and open works|milestone 8]], step 7).

The settings page toggles the theme and holds the e-reader options:

```dart
@RoutePage()
class EinkSettingsPage extends ConsumerWidget {
  const EinkSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.pref(Prefs.appTheme) == 'eink';
    return SettingsScaffold(
      title: 'E-ink display',
      children: [
        SwitchListTile(
          title: const Text('Use E-ink theme'),
          subtitle: const Text('Black, white and grays. No animations or ripples.'),
          value: on,
          onChanged: (v) => ref.setPref(Prefs.appTheme, v ? 'eink' : 'catppuccin'),
        ),
        const SettingsHeader('Refresh'),
        const PrefSlider.integer(Prefs.einkFullRefreshEvery, 'Full refresh every', min: 1, max: 20, format: _pages),
        const SettingsHeader('Display'),
        const PrefSwitch(Prefs.einkHighContrast, 'High contrast', subtitle: 'Thicker outlines and pure black text'),
        const PrefSwitch(Prefs.einkPageButtons, 'Page buttons', subtitle: 'Use the device’s physical page-turn buttons'),
      ],
    );
  }
}

String _pages(double v) => v.round() == 1 ? 'every page' : '${v.round()} pages';
```

`format: _pages` passes a top-level function as the slider's label formatter; a `const` constructor can only take a function that is itself a compile-time constant, which a top-level or static function is and a lambda is not.

> [!success] Checkpoint
> run on a tablet emulator (Pixel Tablet) and tap a work: details open beside the library. Switch to E-ink and every screen goes grayscale. Read chapter 13 of *Salt and Lantern* to see the error state.

![[noctua-m13-tablet.png]]
*Milestone 13: tablet layout with navigation rail and details pane*

![[noctua-m13-eink-errors.png]]
*Milestone 13: E-ink theme and the chapter error state*

---
← [[Milestone 12 - Onboarding]] · [[00 Index|Index]] · [[Milestone 14 - The full test suite]] →
