---
title: "Milestone 8: The reader and open works"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 8
aliases:
  - Milestone 8
updated: 2026-11-06
---
# Milestone 8: The reader and open works

The reader is where most time is spent, so it gets the most settings: twelve fonts, page colors, brightness and warm light, paged or scrolling, and an e-ink mode. Works stay open as browser-style tabs.

**Tabs feature (`tabs/`):**

1. `domain/tab_entry.dart`: `TabEntry(workId, chapter, progress)`.
2. `data/tabs_repository.dart`: `TabsRepository` (`tabsRepositoryProvider`), a repository with a cache over a list of Freezed `TabEntry`s, with `open`, `close`, `closeAll` and `updateProgress`. Each change is written through to the `open_tabs` table from [[Milestone 04 - Preferences and the local database|milestone 4]], so tabs survive a restart or a crash. Its static `restore(db, prefs)` reads the saved tabs in `main()` (seeding sample tabs on first launch), and `initialTabsProvider` hands them over. With Freezed, `copyWith(chapter: null)` sets the field to null, so keep the old value explicitly: `t.copyWith(chapter: chapter ?? t.chapter)`.
3. `presentation/open_works_page.dart`: a grid switcher with recently closed works. `widgets/tab_count_button.dart` is the Firefox-style counter that appears in every app bar.

**Reader feature (`reader/`):**

1. `presentation/reader_page.dart`:
   - The chapter text from `chapterTextProvider`: a spinner while it loads, the error view if it fails.
   - The text, with a tap to show or hide the controls (immersive mode when hidden).
   - Overlays for brightness and warm light.
   - A footer with the time and page.
   - The bottom panel: the open-works strip, page slider, and six tools (Chapters, Text, Display, Listen, AI check, Settings).
2. `presentation/reader_style.dart`: maps the font preference to a `TextStyle` (Bookerly falls back to Literata when the font isn’t bundled).
3. `presentation/widgets/`:
   - `reader_settings_sheet.dart`: the Text, Display and Settings tabs.
   - `chapters_sheet.dart`: pick a chapter without leaving the reader.
   - `read_aloud_sheet.dart`: play and pause, speed, voice, a sleep timer, and continue to the next chapter.
   - `authors_note.dart`: shows, collapses or skips author’s notes, per the setting.
4. **Save prompt:** works opened from Browse aren’t in the library yet. The reader counts chapters opened this session; when you go to the next chapter or leave, and the count has reached the “ask after” setting (default 3) or you finished the work, `showSavePrompt` offers to save it with a category and a download choice. Leaving is caught with `PopScope`:

   ```dart
   PopScope(
     canPop: _allowPop || !_promptDue(),
     onPopInvokedWithResult: (didPop, _) async {
       if (didPop) return;
       await _maybeAsk();
       setState(() => _allowPop = true);
       WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).maybePop());
     },
     child: ...,
   )
   ```
5. `data/chapters_repository.dart`: `ChaptersRepository.fetchChapterText(workId, chapter)` returns a chapter's paragraphs after a short simulated delay, and `chapterTextProvider(workId, chapter)` exposes it as an `AsyncValue`. The sample source makes chapter 13 of *Salt and Lantern* fail twice with a `ChapterLoadException`, so the loading and error states (retry, saved copy, web view, report) can be built and tested. `data/highlights_repository.dart` serves the sample highlights.
6. `presentation/highlights_page.dart` and `reader_prefs_page.dart`: highlights and notes per work, and the global reader defaults.

## Code walkthrough: milestone 8

**Step 1: the tabs repository.** `TabEntry` already exists from [[Milestone 01 - Project setup and the folder structure|milestone 1]]'s example. The repository keeps the list in memory as its state, most recent first, and writes it to Drift after every change:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:noctua/src/database/app_database.dart';
import 'package:noctua/src/features/tabs/domain/tab_entry.dart';
import 'package:noctua/src/features/work/data/works_repository.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tabs_repository.g.dart';

/// Overridden in main() with the tabs saved last session.
@Riverpod(keepAlive: true)
List<TabEntry> initialTabs(Ref ref) => const [];

/// Works open as tabs, most recent first.
///
/// A repository with a cache: its state is the open tabs, and every change is
/// written to the `open_tabs` table, so tabs survive a restart or a crash.
@Riverpod(keepAlive: true)
class TabsRepository extends _$TabsRepository {
  /// Sample tabs for a first launch, so the tab UI has something in it.
  static const firstLaunchTabs = [
    TabEntry(workId: 'salt', chapter: 12, progress: 0.31),
    TabEntry(workId: 'iron', chapter: 76, progress: 0.58),
    TabEntry(workId: 'quiet', chapter: 3, progress: 0.12),
    TabEntry(workId: 'ninefold', chapter: 27, progress: 0.94),
  ];

  /// Reads the saved tabs before the first frame. On first launch, saves and
  /// returns the sample tabs instead. [prefs] is updated with the seeded flag.
  static Future<List<TabEntry>> restore(AppDatabase db, Map<String, String> prefs) async {
    if (prefs[Prefs.tabsSeeded.key] != 'true') {
      await db.saveTabs(_rows(firstLaunchTabs));
      await db.putPreference(Prefs.tabsSeeded.key, 'true');
      prefs[Prefs.tabsSeeded.key] = 'true';
      return firstLaunchTabs;
    }
    return [for (final row in await db.loadTabs()) TabEntry(workId: row.workId, chapter: row.chapter, progress: row.progress)];
  }

  static List<OpenTabsCompanion> _rows(List<TabEntry> tabs) => [
    for (final (i, t) in tabs.indexed)
      OpenTabsCompanion.insert(workId: t.workId, chapter: Value(t.chapter), progress: Value(t.progress), position: i),
  ];

  @override
  List<TabEntry> build() => ref.read(initialTabsProvider);

  Future<void> _persist() => ref.read(appDatabaseProvider).saveTabs(_rows(state));

  /// Opens (or focuses) a work and moves it to the front.
  void open(String workId, {int? chapter}) {
    final existing = state.where((t) => t.workId == workId).firstOrNull;
    final entry =
        existing?.copyWith(chapter: chapter ?? existing.chapter) ??
        TabEntry(workId: workId, chapter: chapter ?? ref.read(worksRepositoryProvider).fetchWork(workId).lastChapter);
    state = [entry, ...state.where((t) => t.workId != workId)];
    _persist();
  }

  void close(String workId) {
    state = state.where((t) => t.workId != workId).toList();
    _persist();
  }

  void closeAll() {
    state = const [];
    _persist();
  }

  void updateProgress(String workId, {int? chapter, double? progress}) {
    state = [for (final t in state) t.workId == workId ? t.copyWith(chapter: chapter ?? t.chapter, progress: progress ?? t.progress) : t];
    _persist();
  }
}
```

- `restore` is static because it runs in `main()`, before any provider exists. On first launch it saves the sample tabs and sets the `tabsSeeded` preference, so that happens once.
- `build()` uses `ref.read(initialTabsProvider)`, not `watch`: the initial list is read once, and the repository owns the state from then on.
- `_persist` turns each entry into an `OpenTabsCompanion` with its index as `position`. `state.indexed` yields `(index, entry)` records, destructured as `(i, t)`.
- `_persist()` is called without `await` on purpose: the UI updates immediately and the write finishes in the background. Drift serialises writes, so two quick changes can't interleave.
- `open` moves an existing tab to the front instead of adding a duplicate, and keeps its chapter unless a new one is given.
- `updateProgress` replaces one entry by mapping the whole list; with four to twenty tabs this is cheaper than it sounds and keeps the state immutable.

In `main()`, restore the tabs right after the preferences and pass them in with the other overrides:

```dart
final prefs = await db.loadPreferences();
final tabs = await TabsRepository.restore(db, prefs);
// …in ProviderScope(overrides: [...]):
initialTabsProvider.overrideWithValue(tabs),
```

Now the library's "Open in a tab" filter from [[Milestone 06 - The library|milestone 6]] can read `tabsRepositoryProvider`; put back the line you left out there.

**Step 2: opening the reader.** One helper used by every "read" button, so opening always records a tab:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noctua/src/features/tabs/data/tabs_repository.dart';
import 'package:noctua/src/features/work/data/works_repository.dart';
import 'package:noctua/src/routing/app_router.gr.dart';

/// Opens a work in a tab and goes to the reader.
void openInReader(BuildContext context, WidgetRef ref, String workId, {int? chapter}) {
  ref.read(tabsRepositoryProvider.notifier).open(workId, chapter: chapter);
  final w = ref.read(workProvider(workId));
  context.router.push(ReaderRoute(workId: workId, chapter: chapter ?? w.lastChapter));
}
```

**Step 3: the tab counter.** Firefox's square with a number, in every app bar. Watching `.length` of the list means it rebuilds only when the count could have changed:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noctua/src/features/tabs/data/tabs_repository.dart';
import 'package:noctua/src/routing/app_router.gr.dart';
import 'package:noctua/src/theme/palettes.dart';

/// The Firefox-style tab counter that opens the Open works switcher.
class TabCountButton extends ConsumerWidget {
  const TabCountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(tabsRepositoryProvider).length;
    return IconButton(
      tooltip: '$count open works',
      onPressed: () => context.router.push(const OpenWorksRoute()),
      icon: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: IconTheme.of(context).color ?? context.colors.onSurface, width: 2),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
```

`IconTheme.of(context).color` makes the outline match whatever color the app bar gives its icons, including the selection bar's.

**Step 4: the Open works page.** A segmented switch between open and recently closed works. Closed works live in the page's `State` only, so they disappear when you leave the page, like a browser's closed-tabs list:

```dart
class OpenWorksPage extends ConsumerStatefulWidget {
  const OpenWorksPage({super.key});

  @override
  ConsumerState<OpenWorksPage> createState() => _OpenWorksPageState();
}

class _OpenWorksPageState extends ConsumerState<OpenWorksPage> {
  bool _showClosed = false;
  final List<TabEntry> _closed = [];

  void _close(TabEntry t) {
    setState(() => _closed.insert(0, t));
    ref.read(tabsRepositoryProvider.notifier).close(t.workId);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(tabsRepositoryProvider);
    final list = _showClosed ? _closed : tabs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open works'),
        actions: [
          IconButton(
            tooltip: 'Search open works',
            icon: const Icon(Symbols.search_rounded),
            onPressed: () => showPlaceholder(context, 'Search open works'),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (v) => showPlaceholder(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'Sorted by last opened', child: Text('Sort by last opened')),
              PopupMenuItem(value: 'Closing works older than a week', child: Text('Close works older than a week')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text('Open · ${tabs.length}')),
                  ButtonSegment(value: true, label: Text('Recently closed · ${_closed.length}')),
                ],
                selected: {_showClosed},
                onSelectionChanged: (s) => setState(() => _showClosed = s.first),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _showClosed ? 'Nothing closed yet' : 'No open works',
                      style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
```

The rest of the page is a two-column grid of `_TabCard`s with a close button and the progress through the current chapter. Tapping any card (open or closed) calls `openInReader`, which also reopens a closed work as a tab; a reopened card is removed from the closed list.

**Step 5: reader styles.** `reader_style.dart` maps the font preference to a `TextStyle`. Bookerly is Amazon's font and can't be bundled, so it is requested by family name with Literata as the fallback: if you add a font asset called Bookerly, Flutter uses it; otherwise it silently renders Literata.

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Reader fonts offered in the font picker, in display order.
const readerFonts = [
  'Bookerly',
  'Literata',
  'Merriweather',
  'Source Serif 4',
  'Lora',
  'EB Garamond',
  'Crimson Pro',
  'Libre Baskerville',
  'Noto Serif',
  'Atkinson Hyperlegible',
  'Lexend',
  'Inter',
];

/// Short labels for the picker grid.
String readerFontLabel(String font) => switch (font) {
  'Source Serif 4' => 'Source Serif',
  'EB Garamond' => 'Garamond',
  'Crimson Pro' => 'Crimson',
  'Libre Baskerville' => 'Baskerville',
  'Atkinson Hyperlegible' => 'Atkinson',
  _ => font,
};

/// Text style for a reader font. Bookerly is proprietary and isn't bundled:
/// if you add it as an asset font family named "Bookerly" it's used, otherwise
/// Flutter falls back to Literata.
TextStyle readerTextStyle(String font, {double? size, double? height, Color? color, FontWeight? weight}) {
  if (font == 'Bookerly') {
    final literata = GoogleFonts.literata(fontSize: size, height: height, color: color, fontWeight: weight);
    return literata.copyWith(fontFamily: 'Bookerly', fontFamilyFallback: [literata.fontFamily!]);
  }
  try {
    return GoogleFonts.getFont(font, fontSize: size, height: height, color: color, fontWeight: weight);
  } catch (_) {
    return GoogleFonts.literata(fontSize: size, height: height, color: color, fontWeight: weight);
  }
}
```

`GoogleFonts.getFont(name)` looks a font up by its display name and throws for unknown names, hence the `try`. Page colors are a small palette in `lib/src/theme/palettes.dart`:

```dart
/// Reader page colors, independent of the app theme.
class PagePalette {
  const PagePalette(this.name, this.paper, this.ink);
  final String name;
  final Color paper;
  final Color ink;
}

const pagePalettes = <String, PagePalette>{
  'Mocha': PagePalette('Mocha', Color(0xFF1E1E2E), Color(0xFFCDD6F4)),
  'Latte': PagePalette('Latte', Color(0xFFEFF1F5), Color(0xFF4C4F69)),
  'Sepia': PagePalette('Sepia', Color(0xFFF3EBDC), Color(0xFF3B3024)),
  'Paper': PagePalette('Paper', Color(0xFFFBFAF7), Color(0xFF1E1F24)),
  'Black': PagePalette('Black', Color(0xFF000000), Color(0xFFBAC2DE)),
};
```

**Step 6: the reader page state.** The reader is a `ConsumerStatefulWidget`: the chapter, page, whether controls are showing, and the save-prompt bookkeeping are all local to one reading session.

```dart
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.workId, this.chapter = 1});
  final String workId;
  final int chapter;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late int _chapter = widget.chapter;
  int _page = 0;
  bool _controls = true;
  late final PageController _pages = PageController();

  // Save prompt for unsaved works: chapters opened this session, and when we last asked.
  late final _readChapters = <int>{widget.chapter};
  int _askedAt = 0;
  bool _neverAsk = false;
  bool _allowPop = false;

  Work get _work => ref.read(workProvider(widget.workId));

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _pages.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    SystemChrome.setEnabledSystemUIMode(_controls ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  /// Whether leaving now (or moving on) should first offer to save the work.
  bool _promptDue() {
    final w = _work;
    if (_neverAsk || ref.read(libraryRepositoryProvider).contains(w.id)) return false;
    if (!ref.readPref(Prefs.savePromptEnabled)) return false;
    if (_askedAt > 0 && !ref.readPref(Prefs.savePromptAskAgain)) return false;
    final sinceAsked = _readChapters.length - _askedAt;
    final finished = _chapter >= w.chapters && sinceAsked > 0;
    return sinceAsked >= ref.readPref(Prefs.savePromptAfter) || finished;
  }

  Future<void> _maybeAsk() async {
    if (!_promptDue()) return;
    final r = await showSavePrompt(context, ref, _work, chaptersRead: _readChapters.length, finished: _chapter >= _work.chapters);
    _askedAt = _readChapters.length;
    if (r == SavePromptResult.never) _neverAsk = true;
    // Let the prompt finish its closing animation before the page underneath
    // changes; swapping the chapter text mid-transition trips an accessibility
    // (semantics) assertion in Flutter.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _goChapter(int n) async {
    if (n < 1 || n > _work.chapters) return;
    if (n > _chapter) await _maybeAsk();
    if (!mounted) return;
    _readChapters.add(n);
    setState(() {
      _chapter = n;
      _page = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    ref.read(tabsRepositoryProvider.notifier).updateProgress(_work.id, chapter: n, progress: 0);
  }

  /// Throws away the failed result, so the provider fetches the chapter again.
  void _retry() => ref.invalidate(chapterTextProvider(_work.id, _chapter));

  /// Placeholder pagination: three paragraphs per page. The real reader
```

- `late int _chapter = widget.chapter` initialises from the route argument the first time it's read, without needing `initState`.
- Immersive mode: `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)` hides the status and navigation bars while reading; `edgeToEdge` brings them back. `dispose` always restores them, so leaving the reader mid-immersive doesn't strand the rest of the app without system bars.
- `_promptDue` is the save-prompt rule in one place: not for saved works, not after "Don't ask for this work", not again unless "Ask again" is on, and only after N new chapters or on finishing.
- `_goChapter` asks before moving forward (`n > _chapter`), never when going back, then checks `mounted` because the dialog may have been open while the user left.
- `_retry` is one line: `ref.invalidate(chapterTextProvider(...))` throws the failed result away, so the provider fetches the chapter again (step 12).
- After the save prompt closes, `_maybeAsk` waits 300 ms for its closing animation before the chapter changes underneath it; swapping the page mid-transition trips an accessibility assertion in Flutter.
- `_paginate` is a placeholder: three paragraphs per page. A real implementation measures text with `TextPainter` against the page size, the same technique as [[Milestone 07 - Work details|milestone 7]]'s summary.

**Step 7: the reader layout.** One `Stack`: the text, two light overlays, the footer, and the controls on top.

```dart
    for (var i = 0; i < paragraphs.length; i += 3) paragraphs.sublist(i, (i + 3).clamp(0, paragraphs.length)),
  ];

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(workProvider(widget.workId));
    final appDark = Theme.of(context).brightness == Brightness.dark;
    final eink = context.isEink;
    final followApp = ref.pref(Prefs.readerFollowApp);
    final pageColor = eink
        ? 'Paper'
        : followApp
        ? (appDark ? 'Mocha' : 'Latte')
        : ref.pref(Prefs.readerPageColor);
    final palette = pagePalettes[pageColor] ?? pagePalettes['Mocha']!;
    final brightness = ref.pref(Prefs.readerBrightness);
    final warmth = ref.pref(Prefs.readerWarmth);
    final paged = ref.pref(Prefs.readerPageMode) == 'Paged within chapter';
    final showFooter = ref.pref(Prefs.readerProgressFooter);
    final text = ref.watch(chapterTextProvider(w.id, _chapter));
    final error = text.error;
    final failing = error != null;
    final inLibrary = ref.watch(libraryRepositoryProvider).contains(w.id);

    final paragraphs = text.value ?? const <String>[];
    final pages = paragraphs.isEmpty ? const [<String>[]] : _paginate(paragraphs);
    final chapters = ref.watch(worksRepositoryProvider).fetchChapters(w);
    final chapterTitle = chapters.firstWhere((c) => c.number == _chapter, orElse: () => chapters.first);

    return PopScope(
      canPop: _allowPop || !_promptDue(),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _maybeAsk();
        if (!mounted) return;
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      },
      child: Scaffold(
        backgroundColor: palette.paper,
        body: Stack(
          children: [
            // Text
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: SafeArea(
                  child: failing
                      ? _ChapterError(
                          chapter: _chapter,
                          // After a retry the provider is loading again but keeps the old error.
                          retrying: text.isLoading,
                          attempts: error is ChapterLoadException ? error.attempt : 1,
                          ink: palette.ink,
                          onRetry: _retry,
                          onPrevious: () => _goChapter(_chapter - 1),
                        )
                      : paged
                      ? PageView.builder(
                          controller: _pages,
                          itemCount: pages.length,
                          onPageChanged: (p) {
                            setState(() => _page = p);
                            ref.read(tabsRepositoryProvider.notifier).updateProgress(w.id, progress: (p + 1) / pages.length);
                          },
                          // Placeholder pagination; the real reader measures pages to fit the screen.
                          itemBuilder: (_, i) => SingleChildScrollView(
                            child: _PageText(paragraphs: pages[i], heading: i == 0 ? chapterTitle.label : null, ink: palette.ink),
                          ),
                        )
                      : SingleChildScrollView(
                          child: _PageText(paragraphs: paragraphs, heading: chapterTitle.label, ink: palette.ink),
                        ),
                ),
              ),
            ),

            // Brightness and warm light, drawn over the page.
            if (brightness < 100)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Colors.black.withValues(alpha: (100 - brightness) / 100 * 0.8)),
                ),
              ),
            if (warmth > 0 && !eink)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: const Color(0xFFFF8A3D).withValues(alpha: warmth / 100 * 0.22)),
                ),
              ),

            if (showFooter && !_controls && !failing)
              Positioned(
                left: 24,
                right: 24,
                bottom: 8,
                child: SafeArea(
                  top: false,
                  child: DefaultTextStyle(
                    style: TextStyle(fontSize: 11, color: palette.ink.withValues(alpha: 0.6)),
                    child: Row(
                      children: [
                        Text(TimeOfDay.now().format(context)),
                        const Spacer(),
                        Text(
                          paged
                              ? 'Page ${_page + 1} of ${pages.length} · ${((_page + 1) / pages.length * 100).round()}%'
                              : 'Ch $_chapter of ${w.chapters}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (_controls) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TopBar(work: w, chapter: chapterTitle),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomControls(
                  work: w,
                  inLibrary: inLibrary,
                  page: _page,
                  pageCount: paged ? pages.length : 1,
                  onPage: (p) {
                    setState(() => _page = p);
                    if (_pages.hasClients) _pages.jumpToPage(p);
                  },
                  onPrev: () => _goChapter(_chapter - 1),
                  onNext: () => _goChapter(_chapter + 1),
                  chapter: _chapter,
                  chapterLabel: chapterTitle.label,
                  paragraphs: paragraphs,
                  onChapter: _goChapter,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
```

- The page color follows the app theme (Mocha or Latte) unless "Follow app theme" is off, and e-ink always uses Paper.
- `ref.watch(chapterTextProvider(w.id, _chapter))` gives an `AsyncValue<List<String>>`. Its `value` is the paragraphs (empty while loading), and its `error` decides between the text and the error view. Changing `_chapter` watches a different family member, so the next chapter loads on its own.
- The `GestureDetector` with `HitTestBehavior.opaque` catches taps anywhere on the page, including empty margins, to toggle the controls.
- Brightness and warm light are translucent `ColoredBox`es above the text. `IgnorePointer` lets taps through to the page. This dims the page without needing the system brightness permission.
- `PopScope` catches the back gesture: when a save prompt is due it blocks the pop, shows the prompt, then sets `_allowPop` and pops again on the next frame (`addPostFrameCallback`), because `PopScope` reads `canPop` when the frame builds.
- The footer shows only while controls are hidden, so the two never overlap.

**Step 8: the text.** Every typography setting is its own preference, watched individually, so dragging the text-size slider rebuilds only the text. While the chapter loads, `paragraphs` is empty and the heading shows with a spinner under it, so the page's widget tree keeps its shape:

```dart
class _PageText extends ConsumerWidget {
  const _PageText({required this.paragraphs, required this.ink, this.heading});
  final List<String> paragraphs;
  final String? heading;
  final Color ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final font = ref.pref(Prefs.readerFont);
    final size = ref.pref(Prefs.readerFontSize);
    final height = ref.pref(Prefs.readerLineHeight);
    final gap = ref.pref(Prefs.readerParagraphSpacing);
    final justify = ref.pref(Prefs.readerJustify);
    final indent = ref.pref(Prefs.readerIndent);
    final margin = ref.pref(Prefs.readerMargin);
    final style = readerTextStyle(font, size: size, height: height, color: ink);

    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 24, margin, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null) ...[
            Text(
              heading!,
              style: style.copyWith(fontSize: size * 1.25, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: size),
            AuthorsNote(ink: ink, style: style),
          ],
          // Still loading: the heading shows at once and the text follows.
          if (paragraphs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: ink)),
            ),
          for (final p in paragraphs)
            Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: Text(indent ? ' $p' : p, style: style, textAlign: justify ? TextAlign.justify : TextAlign.start),
            ),
        ],
      ),
    );
  }
}
```

The author's note above each chapter follows the AO3 setting (Show, Collapse or Skip):

```dart
/// Author's note shown above a chapter, per Settings › AO3 › Author's notes.
class AuthorsNote extends ConsumerStatefulWidget {
  const AuthorsNote({super.key, required this.ink, required this.style});
  final Color ink;
  final TextStyle style;

  @override
  ConsumerState<AuthorsNote> createState() => _AuthorsNoteState();
}

class _AuthorsNoteState extends ConsumerState<AuthorsNote> {
  bool _open = false;

  static const _text =
      'Thank you all for the comments on the last chapter! This one took a while: the gulls refused to cooperate. '
      'Content note: brief description of a storm at sea.';

  @override
  Widget build(BuildContext context) {
    final mode = ref.pref(Prefs.authorsNotes);
    if (mode == 'Skip') return const SizedBox.shrink();
    final open = mode == 'Show' || _open;
    final ink = widget.ink;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(color: ink.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: mode == 'Show' ? null : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Symbols.sticky_note_2_rounded, size: 18, color: ink.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Author’s note',
                      style: TextStyle(color: ink.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (mode != 'Show')
                    Icon(open ? Symbols.expand_less_rounded : Symbols.expand_more_rounded, color: ink.withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                _text,
                style: widget.style.copyWith(fontSize: (widget.style.fontSize ?? 16) * 0.85, color: ink.withValues(alpha: 0.85)),
              ),
            ),
        ],
      ),
    );
  }
}
```

**Step 9: the bottom panel.** The "not in your library" banner, the open-works strip and the tools:

```dart
class _BottomControls extends ConsumerWidget {
  const _BottomControls({
    required this.work,
    required this.inLibrary,
    required this.page,
    required this.pageCount,
    required this.onPage,
    required this.onPrev,
    required this.onNext,
    required this.chapter,
    required this.chapterLabel,
    required this.paragraphs,
    required this.onChapter,
  });

  final int chapter;
  final String chapterLabel;
  final List<String> paragraphs;
  final ValueChanged<int> onChapter;

  final Work work;
  final bool inLibrary;
  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final tabs = ref.watch(tabsRepositoryProvider);

    return Material(
      color: c.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Works read but not saved yet: one tap to keep them.
              if (!inLibrary)
                Container(
                  margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Icon(Symbols.bookmark_add_rounded, size: 20, color: c.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Not in your library · cache cleared after 30 days',
                          style: context.text.bodySmall?.copyWith(color: c.onSecondaryContainer),
                        ),
                      ),
                      TextButton(onPressed: () => ref.read(libraryRepositoryProvider.notifier).toggle(work.id), child: const Text('Add')),
                    ],
                  ),
                ),
              // Open works strip
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: tabs.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final t = tabs[i];
                          final tw = ref.watch(workProvider(t.workId));
                          final active = t.workId == work.id;
                          return ChoiceChip(
                            selected: active,
                            showCheckmark: false,
                            avatar: Text(tw.source.badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(tw.title, overflow: TextOverflow.ellipsis),
                            ),
                            onSelected: active ? null : (_) => context.router.replace(ReaderRoute(workId: tw.id, chapter: t.chapter)),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Show all open works',
                      icon: const Icon(Symbols.grid_view_rounded),
```

Tapping another work in the strip uses `context.router.replace`, so switching works doesn't pile readers onto the back stack.

**Step 10: reader settings.** A bottom sheet with a transparent barrier, so the page stays fully visible and every change previews live behind it:

```dart
/// Reader settings as a bottom sheet over the page, so changes preview live.
Future<void> showReaderSettings(BuildContext context, {int initialTab = 0}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  barrierColor: Colors.transparent,
  builder: (_) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.58,
    child: ReaderSettingsPanel(initialTab: initialTab),
  ),
);
```

Most rows are three small widgets bound to a `Pref`:

```dart
class _SliderRow extends ConsumerWidget {
  const _SliderRow(this.pref, this.title, {required this.min, required this.max, required this.step, required this.format});
  final Pref<double> pref;
  final String title;
  final double min;
  final double max;
  final double step;
  final String Function(double) format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.pref(pref).clamp(min, max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: context.text.bodyLarge)),
              Text(format(v), style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
            ],
          ),
          Slider(
            value: v,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            onChanged: (x) => ref.setPref(pref, double.parse(x.toStringAsFixed(2))),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends ConsumerWidget {
  const _ChoiceRow(this.pref, this.title, this.options);
  final Pref<String> pref;
  final String title;
  final List<String> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.pref(pref);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.bodyLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final o in options) ChoiceChip(label: Text(o), selected: v == o, onSelected: (_) => ref.setPref(pref, o))],
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends ConsumerWidget {
  const _ToggleRow(this.pref, this.title, [this.subtitle]);
  final Pref<bool> pref;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: ref.pref(pref),
    onChanged: (v) => ref.setPref(pref, v),
  );
}
```

`double.parse(x.toStringAsFixed(2))` rounds slider values before saving, so the stored value is `1.65` rather than `1.6500000000000001`. A tab is then just a list of these:

```dart
class _LayoutTab extends StatelessWidget {
  const _LayoutTab();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _SliderRow(Prefs.readerMargin, 'Side margins', min: 8, max: 48, step: 2, format: (v) => '${v.round()} px'),
      const _ChoiceRow(Prefs.readerPageMode, 'Page mode', ['Paged within chapter', 'Continuous scroll']),
      const _ChoiceRow(Prefs.readerPageTurn, 'Page turn', ['Slide', 'Curl', 'Fade', 'None']),
      const _ToggleRow(Prefs.readerProgressFooter, 'Progress footer', 'Clock, page and chapter %'),
      const _ToggleRow(Prefs.readerTwoColumns, 'Two columns in landscape'),
    ],
```

**Step 11: the save prompt.** A dialog that returns a value. `showDialog<SavePromptResult>` completes with whatever the pressed button passes to `Navigator.pop`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:noctua/src/common_widgets/common_widgets.dart';
import 'package:noctua/src/features/library/data/library_repository.dart';
import 'package:noctua/src/features/work/domain/work.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';

/// What the reader does after the save prompt closes.
enum SavePromptResult { saved, notNow, never }

/// Asks whether to keep a work the reader has been reading without saving.
Future<SavePromptResult> showSavePrompt(
  BuildContext context,
  WidgetRef ref,
  Work work, {
  required int chaptersRead,
  required bool finished,
}) async {
  final download = ref.readPref(Prefs.savePromptDownload);
  var category = ref.readPref(Prefs.defaultCategory);
  var downloadToo = download != 'Don\'t download';
  final result = await showDialog<SavePromptResult>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setD) => AlertDialog(
        icon: const Icon(Symbols.bookmark_add_rounded),
        title: Text(finished ? 'Keep this one?' : 'Enjoying it?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              finished
                  ? 'You finished ${work.title}. Save it to your library so it doesn’t get cleaned up?'
                  : 'You’ve read $chaptersRead ${chaptersRead == 1 ? 'chapter' : 'chapters'} of ${work.title}. Save it to your library to keep your place and get new chapters?',
            ),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              initialSelection: category,
              label: const Text('Category'),
              expandedInsets: EdgeInsets.zero,
              onSelected: (v) => category = v ?? category,
              dropdownMenuEntries: [for (final c in ref.read(libraryCategoriesProvider)) DropdownMenuEntry(value: c, label: c)],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: downloadToo,
              title: Text(download == 'Unread only' ? 'Download unread chapters' : 'Download all chapters'),
              onChanged: (v) => setD(() => downloadToo = v ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, SavePromptResult.never), child: const Text('Don’t ask for this work')),
          TextButton(onPressed: () => Navigator.pop(d, SavePromptResult.notNow), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(d, SavePromptResult.saved), child: const Text('Save')),
        ],
      ),
    ),
  );
  final r = result ?? SavePromptResult.notNow;
  if (r == SavePromptResult.saved) {
    ref.read(libraryRepositoryProvider.notifier).toggle(work.id);
    if (context.mounted) showPlaceholder(context, 'Saved to $category${downloadToo ? ' · downloading' : ''}');
  }
  return r;
}
```

- The dialog's category and download choice live in local variables; `StatefulBuilder` gives the dialog its own `setState` (`setD`) for the checkbox.
- Dismissing the dialog by tapping outside returns null, treated as "Not now".
- `context.mounted` is checked before showing the snackbar, since the reader may have been popped while the dialog was open.

**Step 12: the chapters repository.** Chapter text is data, so it comes from a repository. Until source extensions exist it serves sample paragraphs, with a simulated delay so the loading state is visible, and one chapter that fails twice so the error state can be built and tested without a network:

```dart
import 'package:noctua/src/features/work/domain/work.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chapters_repository.g.dart';

/// A chapter that couldn't be loaded from its source.
class ChapterLoadException implements Exception {
  const ChapterLoadException({required this.code, required this.message, required this.attempt});

  /// Short code for reports, e.g. `SRC_HTTP_503`.
  final String code;
  final String message;

  /// How many times this chapter has been tried, including this one.
  final int attempt;

  @override
  String toString() => '$code: $message';
}

/// Chapter text, from downloads or the work's source.
///
/// Serves sample text until source extensions exist. To demo the error state,
/// chapter 13 of Salt and Lantern fails twice before it loads.
class ChaptersRepository {
  ChaptersRepository({this.latency = const Duration(milliseconds: 200)});

  /// Simulated network time, so loading states are visible.
  final Duration latency;

  final _failuresLeft = {'salt:13': 2};
  final _attempts = <String, int>{};

  static const _sample = [
    'The lantern had gone out again. Mara knelt on the cold stone of the gallery and tipped the last of the bucket into '
        'its brass well, and the flame came back the colour of deep water, blue at the heart and green where it licked the glass.',
    'Below, the gulls had stopped their circling. They sat in a line along the rail like a jury waiting for a verdict, every '
        'head turned toward the harbour, where the fishing boats should have been and were not.',
    '“You saw it too,” she said to the nearest one. It blinked, unhelpful, and she laughed despite herself.',
    'The letter was still in her coat. She had not opened it. She had read the address a hundred times — her name, the '
        'lighthouse, the date forty years gone — and every time the handwriting looked more like her own.',
    'Somewhere out past the breakwater a bell rang once, low and drowned, though there had been no bell in the bay since '
        'the storm took the old church.',
    'Mara counted to ten. The bell rang again. The gulls, as one, turned their heads to look at her.',
    'She went down the spiral stair with the lantern held out in front of her like a question, and the light went ahead '
        'of her, green and patient, as if it already knew the way.',
    'At the bottom, the door to the sea was open. She was certain she had locked it.',
  ];

  /// A paragraph to preview reader settings with.
  String get sampleParagraph => _sample.first;

  /// Paragraphs of one chapter. Throws [ChapterLoadException] when the source
  /// can't be reached.
  Future<List<String>> fetchChapterText(String workId, int chapter) async {
    await Future<void>.delayed(latency);
    final key = '$workId:$chapter';
    final attempt = _attempts[key] = (_attempts[key] ?? 0) + 1;
    final left = _failuresLeft[key] ?? 0;
    if (left > 0) {
      _failuresLeft[key] = left - 1;
      throw ChapterLoadException(code: 'SRC_HTTP_503', message: 'AO3 returned 503 Service Unavailable', attempt: attempt);
    }
    return [for (var i = 0; i < 3; i++) ..._sample];
  }

  /// Passages containing [query] in the downloaded chapters of [works], as
  /// (work id, paragraph number, text).
  List<(String, int, String)> searchDownloaded(List<Work> works, String query) {
    final q = query.toLowerCase();
    return [
      for (final w in works.where((w) => w.downloaded).take(3))
        for (final (i, p) in _sample.indexed)
          if (p.toLowerCase().contains(q)) (w.id, i + 1, p),
    ];
  }
}

@Riverpod(keepAlive: true)
ChaptersRepository chaptersRepository(Ref ref) => ChaptersRepository();

/// The text of one chapter. Invalidate it to retry after an error.
/// No automatic retry: the reader shows the error and the user decides when
/// to try again (Riverpod retries failed providers by default).
Duration? noRetry(int retryCount, Object error) => null;

@Riverpod(retry: noRetry)
Future<List<String>> chapterText(Ref ref, String workId, int chapter) =>
    ref.watch(chaptersRepositoryProvider).fetchChapterText(workId, chapter);
```

- `ChapterLoadException` carries a short code for reports, a message, and which attempt this was; the error view shows "Still failing after N tries" from it.
- `chapterTextProvider` is an auto-disposed family, so leaving the reader frees the text, and each chapter is cached separately while the reader is open.
- `@Riverpod(retry: noRetry)` turns off Riverpod 3's automatic retry for this provider. Retrying with back-off is right for many providers, but here the user should see the error and decide when to try again.
- `sampleParagraph` gives the reader-defaults page something to preview, and `searchDownloaded` is used by [[Milestone 09 - Updates, History, Browse and sources|milestone 9]]'s deep search.

`_retry` invalidates the provider. While it fetches again, the `AsyncValue` is loading but still carries the previous error, which is exactly the "Trying AO3 again…" state. The error view is the last widget in `reader_page.dart`. It takes everything it shows as parameters, so it has no state of its own:

```dart
/// "Couldn't load chapter" state, shown in place of the text.
class _ChapterError extends StatelessWidget {
  const _ChapterError({
    required this.chapter,
    required this.retrying,
    required this.attempts,
    required this.ink,
    required this.onRetry,
    required this.onPrevious,
  });

  final int chapter;
  final bool retrying;
  final int attempts;
  final Color ink;
  final VoidCallback onRetry;
  final VoidCallback onPrevious;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (retrying) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Trying AO3 again…', style: TextStyle(color: ink)),
          ],
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: c.errorContainer,
              child: Icon(Symbols.cloud_off_rounded, size: 32, color: c.onErrorContainer),
            ),
            const SizedBox(height: 16),
            Text(
              'Couldn’t load chapter $chapter',
              style: context.text.headlineSmall?.copyWith(color: ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'AO3 is busy or down for maintenance (error 503). This usually clears up within a few minutes.',
              style: context.text.bodyMedium?.copyWith(color: ink.withValues(alpha: 0.8)),
              textAlign: TextAlign.center,
            ),
            if (attempts > 1) ...[
              const SizedBox(height: 8),
              Text('Still failing after $attempts tries', style: context.text.bodySmall?.copyWith(color: c.error)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: onRetry, icon: const Icon(Symbols.refresh_rounded), label: const Text('Try again')),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => showPlaceholder(context, 'Opening the saved copy'),
                icon: const Icon(Symbols.offline_pin_rounded),
                label: const Text('Read saved copy from Oct 2'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => showPlaceholder(context, 'Opening web view'),
                icon: const Icon(Symbols.public_rounded),
                label: const Text('Open in web view'),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: onPrevious,
                  icon: const Icon(Symbols.skip_previous_rounded),
                  label: const Text('Previous chapter'),
                ),
                TextButton.icon(
                  onPressed: () => context.router.push(
                    ErrorReportRoute(
                      error: 'SRC_HTTP_503: AO3 returned 503 Service Unavailable',
                      where: 'Chapter $chapter · archiveofourown.org',
                    ),
                  ),
                  icon: const Icon(Symbols.flag_rounded),
                  label: const Text('Report this error'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'SRC_HTTP_503 · archiveofourown.org · AO3 source v1.0',
              style: context.text.labelSmall?.copyWith(color: ink.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}
```

Add a data-layer test that pins the demo failure, so a change to the sample source can't silently remove the error state:

```dart
// Data: the sample chapter source, including the failure used to demo the error state.
import 'package:flutter_test/flutter_test.dart';
import 'package:noctua/src/features/reader/data/chapters_repository.dart';

void main() {
  test('Salt and Lantern chapter 13 fails twice, then loads', () async {
    final repo = ChaptersRepository(latency: Duration.zero);
    for (final attempt in [1, 2]) {
      await expectLater(
        repo.fetchChapterText('salt', 13),
        throwsA(isA<ChapterLoadException>().having((e) => e.attempt, 'attempt', attempt)),
      );
    }
    expect(await repo.fetchChapterText('salt', 13), isNotEmpty);
  });

  test('other chapters load first time', () async {
    expect(await ChaptersRepository(latency: Duration.zero).fetchChapterText('iron', 2), isNotEmpty);
  });
}
```

**Step 13: routes.** Add the reader, open works, highlights and reader-defaults pages:

```dart
AutoRoute(page: ReaderRoute.page),
AutoRoute(page: OpenWorksRoute.page),
AutoRoute(page: HighlightsRoute.page),
AutoRoute(page: ReaderPrefsRoute.page),
```

`ReaderRoute` takes `workId` and an optional `chapter` (default 1), matching the page's constructor.

> [!success] Checkpoint
> read chapter 12 of *Salt and Lantern* and switch tabs from the strip. Then open *The Lighthouse Map* from Browse ([[Milestone 09 - Updates, History, Browse and sources|milestone 9]]), read past three chapters, and press back: the save prompt appears.

![[noctua-m08-reader.png]]
*Milestone 8: reader, save prompt and open works*

---
← [[Milestone 07 - Work details]] · [[00 Index|Index]] · [[Milestone 09 - Updates, History, Browse and sources]] →
