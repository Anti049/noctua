---
title: "Milestone 6: The library"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 6
aliases:
  - Milestone 6
updated: 2026-11-06
---
# Milestone 6: The library

The library is the home screen: works sorted into categories, shown as covers, a compact list or detail cards, with Mihon-style filters and multi-select.

This is the first milestone that builds a full feature, so it also sets the pattern every other feature follows.

1. **`work/domain/work.dart`** (domain): `Source` (AO3, SB, FFN), `Author` (with an optional pseud), `Work`, `Chapter`, `Series` and `SeriesRef`. Make them `@freezed` classes: you get `==`, `hashCode`, `toString` and `copyWith` for free, and every field is final. They are shared by most features. Computed getters (and `matchesQuery`, used by search in [[Milestone 09 - Updates, History, Browse and sources|milestone 9]]) need a private `const Work._();` constructor.
2. **`work/data/`** (data): `sample_works.dart` holds the sample works, chapters and series; `works_repository.dart` is the `WorksRepository` that serves them (`fetchLibraryWorks`, `fetchWork`, `fetchChapters`, `fetchSeries`…) and the `workProvider(id)` family screens watch. Only the repository reads the samples, so swapping in the sync server later changes method bodies in one file.
3. **`library/data/library_repository.dart`** (data): `libraryCategoriesProvider` (the category names) and `LibraryRepository`, a repository with a cache whose state is the set of saved work ids, with `add`, `remove` and `toggle`.
4. **`library/domain/library_filter.dart`** (domain): `TriState` (off, include, exclude), the Freezed `LibraryFilter` with `@Default` values (tri-state flags and tags, sources, match-all versus match-any) and the rules on it: `cycleFlag`, `cycleTag`, `toggleSource` and `matches(work)`; plus `sortWorks`. All plain Dart, so the rules get unit tests.
5. **`work/presentation/widgets/work_cover.dart`:** the generated cover: a solid color (or a diagonal split for crossovers), the source badge, the title shrunk until its longest word fits, the fandom and an offline badge. Also `MiniCover` for list rows.
6. **`library/presentation/library_controllers.dart`** (presentation):
   - `LibraryFilterController` (`libraryFilterControllerProvider`): holds the current `LibraryFilter`; each method delegates to the domain (`state = state.cycleFlag(key)`).
   - `libraryWorks(Ref ref, String category)`: a generated family (`libraryWorksProvider(category)`) that combines the repositories, the filter, Downloaded only and sort, and is what the grid watches.
   - `categoryCountsProvider`: the counts on the tabs.
7. **`library/presentation/library_selection_controller.dart`:** the set of selected work ids. Long-press starts selection; while it is non-empty a tap toggles and the app bar becomes a selection bar (select all, move to category, mark read, download, remove).
8. **`library/presentation/`** screens:
   - `library_page.dart`: one tab per category; the grid, list or card layout from preferences; and the Continue reading card on Reading.
   - `widgets/library_filter_sheet.dart`: Filter, Tags, Sort and Display tabs in one bottom sheet.
   - `edit_categories_page.dart`: rename, reorder (`ReorderableListView`) and delete categories.
9. Add the library keys to the `Prefs` registry (layout, grid columns, badges, sort), register the new pages in the router and rebuild.
10. **Tests:** `test/src/features/library/domain/library_filter_test.dart` checks the filter and sort rules against the sample works.

## Code walkthrough: milestone 6

**Step 1: the shared models.** `work/domain/work.dart` is imported by most features, so it stays small: data, a few derived getters, and no Flutter widgets (`Color` from `dart:ui` via `material.dart` is the one exception, for cover colors).

```dart
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'work.freezed.dart';

enum Source {
  ao3('AO3', 'Archive of Our Own'),
  sb('SB', 'SpaceBattles'),
  ffn('FFN', 'FanFiction.net');

  const Source(this.badge, this.label);
  final String badge;
  final String label;
}

@freezed
abstract class Author with _$Author {
  const factory Author(
    /// Display name (the pseud on AO3).
    String name, [

    /// The account username when [name] is a pseud of it.
    String? pseudOf,
  ]) = _Author;
}

@freezed
abstract class Work with _$Work {
  const factory Work({
    required String id,
    required String title,
    required List<Author> authors,
    required List<String> fandoms,
    required Source source,
    required List<Color> colors,
    required String category,
    @Default('Teen') String rating,
    @Default(false) bool complete,
    @Default('120k') String words,
    @Default(20) int chapters,
    int? totalChapters,
    @Default('1.2k') String kudos,
    @Default('') String summary,
    @Default([]) List<String> tags,
    @Default(0) int unread,
    @Default(false) bool downloaded,
    @Default(1) int lastChapter,
    @Default('3 days ago') String updated,
    @Default('~Fri') String nextUpdate,

    /// Series this work belongs to, with its part number.
    SeriesRef? series,

    /// Placeholder detection score, 0–1 (higher = more likely AI-generated).
    @Default(0.12) double aiLikelihood,

    /// AO3 archive warnings on the work.
    @Default([]) List<String> warnings,
  }) = _Work;
  const Work._();

  String get authorLine => authors.map((a) => a.name).join(', ');

  /// Whether a lower-case search [q] appears in the title, authors, tags or fandoms.
  bool matchesQuery(String q) =>
      title.toLowerCase().contains(q) ||
      authorLine.toLowerCase().contains(q) ||
      tags.any((t) => t.toLowerCase().contains(q)) ||
      fandoms.any((f) => f.toLowerCase().contains(q));
  String get coverFandom => fandoms.first + (fandoms.length > 1 ? ' +${fandoms.length - 1}' : '');
  bool get isCrossover => fandoms.length > 1;
}

@freezed
abstract class Chapter with _$Chapter {
  const factory Chapter({
    required int number,
    required String title,
    required String date,
    required String words,
    @Default(false) bool read,
    @Default(false) bool downloaded,
    double? progress,
  }) = _Chapter;
  const Chapter._();

  String get label => 'Ch $number · $title';
}

@freezed
abstract class SeriesRef with _$SeriesRef {
  const factory SeriesRef(String id, String name, int part, int of) = _SeriesRef;
}

@freezed
abstract class Series with _$Series {
  const factory Series({
    required String id,
    required String name,
    required String author,
    required String summary,

    /// (workId or null for works not in the sample data, title, meta)
    required List<(String?, String, String)> parts,
  }) = _Series;
}
```

- `Source` is an enhanced enum with fields, so `work.source.badge` gives "AO3" without a lookup table.
- `Author` uses positional parameters with an optional second one: `Author('tidewright')` or `Author('Ash', 'ashfall')` for a pseud.
- `Work` has many `@Default`s so the samples only spell out what makes each one different. `totalChapters` is nullable: null means the author hasn't said how many chapters there will be (AO3's "?").
- `Series.parts` is a list of records `(String? workId, String title, String meta)`; Freezed handles records like any other field.

**Step 2: the works repository.** Sample data lives in the data layer and nowhere else. `SampleWorks` is a class with static members; the first work shows the shape:

```dart
import 'package:noctua/src/features/work/domain/work.dart';
import 'package:noctua/src/theme/palettes.dart';

/// Sample works, chapters and series, served by [WorksRepository] until the
/// sync server and source extensions exist. Only the data layer reads this.
abstract final class SampleWorks {
  static const _saltSummary =
      'A lighthouse keeper’s apprentice finds a lantern that only burns with seawater, and a letter addressed to her, '
      'dated forty years before she was born. The handwriting is her own.\n\n'
      'Now the gulls won’t stop watching the harbour, the fishing boats are coming home a day before they left, and the '
      'only person who might know why has been dead since the storm of ’61.\n\n'
      'Updates Fridays, mostly. Tags will be added as the story goes.';

  static final works = <Work>[
    Work(
      id: 'salt',
      title: 'Salt and Lantern',
      authors: const [Author('tidewright')],
      fandoms: const ['Original Work'],
```

Screens never import it. They go through `WorksRepository`, which is what the sync server and source extensions will sit behind later:

```dart
import 'package:noctua/src/features/work/data/sample_works.dart';
import 'package:noctua/src/features/work/domain/work.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'works_repository.g.dart';

/// Works, their chapters and series.
///
/// Serves sample data until the sync server and source extensions exist; then
/// these methods call them, and callers don't change. Lookups are synchronous
/// for now; when they become network calls, the providers below turn into
/// `FutureProvider`s and screens switch on their `AsyncValue`.
class WorksRepository {
  const WorksRepository();

  /// Works in the user's library, in last-read order.
  List<Work> fetchLibraryWorks() => SampleWorks.works;

  /// Any work the app knows, saved or not. Unknown ids fall back to the first
  /// work, so a stale tab or link never crashes a screen.
  Work fetchWork(String id) => SampleWorks.work(id);

  /// Newest chapter first.
  List<Chapter> fetchChapters(Work work) => SampleWorks.chapters(work);

  Series fetchSeries(String id) => SampleWorks.series[id] ?? SampleWorks.series.values.first;

  List<Series> fetchSeriesByAuthor(String author) => [
    for (final s in SampleWorks.series.values)
      if (s.author.contains(author)) s,
  ];

  /// Works opened from Browse that aren't in the library.
  List<Work> fetchRecentlyOpenedUnsaved() => [SampleWorks.unsaved, SampleWorks.weighty];
}

@Riverpod(keepAlive: true)
WorksRepository worksRepository(Ref ref) => const WorksRepository();

/// One work by id.
@riverpod
Work work(Ref ref, String id) => ref.watch(worksRepositoryProvider).fetchWork(id);
```

- The methods are synchronous for now, because the samples are in memory. When they become network calls, the methods return `Future`s, `workProvider` becomes a `FutureProvider`, and screens switch on its `AsyncValue`, the same way the update page already does.
- `workProvider(id)` is a family: each id is its own cached value, and `ref.watch(workProvider('salt'))` is how every screen from here on gets a work.
- `fetchWork` falls back to the first work for an unknown id, so a stale tab or link never crashes a screen.

The library's own data is which works are saved, and in which categories:

```dart
import 'package:noctua/src/features/work/data/works_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_repository.g.dart';

/// The user's categories, in display order. Sample data until categories are
/// stored; the edit-categories page works on a copy.
@Riverpod(keepAlive: true)
List<String> libraryCategories(Ref ref) => const ['Reading', 'Plan to read', 'Completed', 'On hold'];

/// Which works are saved in the library.
///
/// A repository with a cache: its state is the set of saved work ids. It
/// starts from the sample library; the sync server will be its source later.
@Riverpod(keepAlive: true)
class LibraryRepository extends _$LibraryRepository {
  @override
  Set<String> build() => {for (final w in ref.read(worksRepositoryProvider).fetchLibraryWorks()) w.id};

  bool contains(String workId) => state.contains(workId);

  void add(String workId) => state = {...state, workId};

  void remove(String workId) => state = {...state}..remove(workId);

  void toggle(String workId) => contains(workId) ? remove(workId) : add(workId);
}
```

`LibraryRepository` is a repository with a cache, like [[Milestone 04 - Preferences and the local database|milestone 4]]'s preferences. Its state is the set of saved ids; `add` and `remove` build a new set each time, because Riverpod only notices a new object, not a mutated one (`({...state}..remove(id))` copies then removes, in one expression). It starts from the sample library; the sync server becomes its source later.

**Step 3: the generated cover.** `WorkCover` draws a placeholder cover from the work's colors and the Covers settings ([[Milestone 10 - Settings|milestone 10]] adds the settings page; the defaults work now):

```dart
/// Generated cover, drawn from Settings › Covers: style, crossover handling,
/// and which details to print. E-ink draws it as an outlined white card.
class WorkCover extends ConsumerWidget {
  const WorkCover({
    super.key,
    required this.work,
    this.showTitle = true,
    this.showSource = true,
    this.showUnread = true,
    this.showDownloaded = true,
    this.radius = 12,
  });

  final Work work;
  final bool showTitle;
  final bool showSource;
  final bool showUnread;
  final bool showDownloaded;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eink = context.isEink;
    final style = ref.pref(Prefs.coverStyle);
    final crossover = ref.pref(Prefs.coverCrossover);
    final font = ref.pref(Prefs.coverFont);
    final pTitle = ref.pref(Prefs.coverShowTitle);
    final pSource = ref.pref(Prefs.coverShowSource);
    final pFandom = ref.pref(Prefs.coverShowFandom);
    final pAuthor = ref.pref(Prefs.coverShowAuthor);
    final pRating = ref.pref(Prefs.coverShowRating);
    final pWords = ref.pref(Prefs.coverShowWords);

    final colors = crossover == 'First fandom' ? [work.colors.first] : work.colors;
    final decoration = eink
        ? BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.black, width: 1.5),
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: style == 'Typographic' ? Color.lerp(colors.first, Colors.black, 0.55) : colors.first,
            gradient: coverGradient(colors, style: style, crossover: crossover),
          );
    final fg = eink ? Colors.black : const Color(0xFFCDD6F4);
    final typographic = style == 'Typographic';

    return AspectRatio(
      aspectRatio: 2 / 3,
      child: DecoratedBox(
        decoration: decoration,
        child: Stack(
          children: [
            if (style == 'Pattern' && !eink) Positioned.fill(child: CustomPaint(painter: _PatternPainter(radius))),
            LayoutBuilder(
              builder: (context, box) {
                // Shrink the title until its longest word fits on one line.
                final longest = work.title.split(' ').fold<int>(1, (m, w) => w.length > m ? w.length : m);
                final size = ((box.maxWidth - 16) / (longest * 0.6)).clamp(10.0, typographic ? 20.0 : 15.0);
                final meta = TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.8));
                final extras = [if (pRating) work.rating, if (pWords) '${work.words} words'].join(' · ');
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // On very small covers the unread count drops below the source badge instead of overflowing.
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          runSpacing: 4,
                          children: [
                            if (showSource && pSource) SourceBadge(work.source) else const SizedBox.shrink(),
                            if (showUnread && work.unread > 0) CountBadge(work.unread),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (showTitle && pTitle) ...[
                        Text(
                          work.title,
                          maxLines: typographic ? 5 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: coverFontStyle(font, size).copyWith(height: 1.15, color: fg),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (pAuthor) Text(work.authorLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                      if (extras.isNotEmpty) Text(extras, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                      Row(
                        children: [
                          Expanded(
                            child: pFandom
                                ? Text(work.coverFandom, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta)
                                : const SizedBox(),
                          ),
                          if (showDownloaded && work.downloaded)
                            Icon(Symbols.offline_pin_rounded, size: 14, fill: 1, color: eink ? Colors.black : context.noctua.success),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

- `AspectRatio(2 / 3)` makes every cover book-shaped whatever width the grid gives it.
- The `LayoutBuilder` reads the cover's actual width to size the title: the longest word must fit on one line, so `size` is the width divided by roughly 0.6 × the word's length, clamped between 10 and 15 (20 for the Typographic style).
- The top row is a `Wrap` with `spaceBetween`: on wide covers the source badge and unread count sit at opposite corners, and on very small covers the count drops to a second line instead of overflowing.
- On e-ink the cover becomes a white card with a black border, because large color fills ghost on e-paper.

Crossover works have two colors. `coverGradient` turns them into a hard diagonal split (two stops at 0.5), soft gradient or stripes:

```dart
/// Background for a generated cover; null means a flat fill.
Gradient? coverGradient(List<Color> c, {required String style, required String crossover}) {
  if (c.length > 1) {
    if (crossover == 'Stripes') {
      final stops = <double>[];
      final colors = <Color>[];
      const bands = 6;
      for (var i = 0; i < bands; i++) {
        colors
          ..add(c[i % c.length])
          ..add(c[i % c.length]);
        stops
          ..add(i / bands)
          ..add((i + 1) / bands);
      }
      return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors, stops: stops);
    }
    if (style == 'Gradient') return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c[0], c[0], c[1], c[1]],
      stops: const [0, 0.5, 0.5, 1],
    );
  }
  if (style == 'Gradient') {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(c.first, Colors.white, 0.15)!, Color.lerp(c.first, Colors.black, 0.35)!],
    );
  }
  return null;
}

TextStyle coverFontStyle(String font, double size) => switch (font) {
  'Inter' => GoogleFonts.inter(fontSize: size, fontWeight: FontWeight.w700),
  'Playfair Display' => GoogleFonts.playfairDisplay(fontSize: size, fontWeight: FontWeight.w700),
  'JetBrains Mono' => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: FontWeight.w600),
  _ => GoogleFonts.literata(fontSize: size, fontWeight: FontWeight.w600),
};

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key});
  final Source source;

  @override
  Widget build(BuildContext context) {
    final eink = context.isEink;
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: eink ? Colors.black : const Color(0x8C11111B), borderRadius: BorderRadius.circular(4)),
      child: Text(
        source.badge,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

/// Small rounded-square swatch used in lists (updates, history, tabs).
class MiniCover extends StatelessWidget {
  const MiniCover(this.work, {super.key, this.width = 40, this.height = 56});
  final Work work;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final eink = context.isEink;
    final c = work.colors;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: eink ? Colors.white : c.first,
        border: eink ? Border.all(color: Colors.black) : null,
        gradient: !eink && c.length > 1
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c[0], c[0], c[1], c[1]],
                stops: const [0, 0.5, 0.5, 1],
              )
            : null,
      ),
    );
  }
}
```

**Step 4: the filter rules (domain).** Mihon's filters are business rules, so they live in the domain as plain Dart:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:noctua/src/features/work/domain/work.dart';

part 'library_filter.freezed.dart';

/// A Mihon-style filter checkbox: ignore, must match, or must not match.
enum TriState {
  off,
  include,
  exclude;

  TriState get next => TriState.values[(index + 1) % 3];

  /// Whether a work with [value] passes this rule.
  bool allows(bool value) => switch (this) {
    TriState.off => true,
    TriState.include => value,
    TriState.exclude => !value,
  };
}

/// What the library's filter sheet is set to.
@freezed
abstract class LibraryFilter with _$LibraryFilter {
  const factory LibraryFilter({
    @Default({}) Map<String, TriState> flags,
    @Default({Source.ao3, Source.sb, Source.ffn}) Set<Source> sources,
    @Default({}) Map<String, TriState> tags,
    @Default(true) bool matchAll,
  }) = _LibraryFilter;
  const LibraryFilter._();

  int get activeFilterCount => flags.values.where((v) => v != TriState.off).length + (Source.values.length - sources.length);
  int get activeTagCount => tags.values.where((v) => v != TriState.off).length;
  int get activeCount => activeFilterCount + activeTagCount;

  LibraryFilter cycleFlag(String key) => copyWith(flags: {...flags, key: (flags[key] ?? TriState.off).next});
  LibraryFilter cycleTag(String tag) => copyWith(tags: {...tags, tag: (tags[tag] ?? TriState.off).next});
  LibraryFilter toggleSource(Source s) => copyWith(sources: sources.contains(s) ? ({...sources}..remove(s)) : {...sources, s});

  /// Whether [work] passes every flag, source and tag rule. [isOpen] says
  /// whether the work is open as a tab (the "Open in a tab" flag).
  bool matches(Work work, {bool isOpen = false}) {
    if (!sources.contains(work.source)) return false;
    bool flag(String key, bool value) => (flags[key] ?? TriState.off).allows(value);
    final flagsOk =
        flag('downloaded', work.downloaded) &&
        flag('unread', work.unread > 0) &&
        flag('started', work.lastChapter > 1) &&
        flag('completed', work.complete) &&
        flag('stale', work.updated == 'abandoned?' || work.updated == '2023') &&
        flag('open', isOpen);
    return flagsOk && _tagsOk(work);
  }

  bool _tagsOk(Work work) {
    final rules = tags.entries.where((e) => e.value != TriState.off).toList();
    if (rules.isEmpty) return true;
    final all = {...work.tags, ...work.fandoms};
    if (rules.any((e) => e.value == TriState.exclude && all.contains(e.key))) return false;
    final includes = rules.where((e) => e.value == TriState.include).map((e) => e.key);
    if (includes.isEmpty) return true;
    return matchAll ? includes.every(all.contains) : includes.any(all.contains);
  }
}

/// Sorts [works] by one of the library's sort options. "Last read" keeps the
/// given order, which is already most recent first.
List<Work> sortWorks(List<Work> works, String sort, {required bool descending}) {
  int words(Work w) => (double.tryParse(w.words.replaceAll('k', '')) ?? 0).round();
  final list = [...works];
  switch (sort) {
    case 'Title':
      list.sort((a, b) => a.title.compareTo(b.title));
    case 'Word count':
      list.sort((a, b) => words(a).compareTo(words(b)));
    case 'Unread chapters':
      list.sort((a, b) => a.unread.compareTo(b.unread));
    default:
      return list;
  }
  return descending ? list.reversed.toList() : list;
}
```

- `TriState` is the Mihon filter checkbox: off, include (must match), exclude (must not match). `next` cycles through them by index, and `allows(value)` turns a state into a test: off passes everything, include requires `value`, exclude requires `!value`.
- `LibraryFilter` stores maps from a key to its `TriState`, so new filters don't need new fields. The getters count active filters for the badges on the filter button and sheet tabs.
- `cycleFlag`, `cycleTag` and `toggleSource` return a new filter instead of changing this one: Freezed models are immutable, and the controller assigns the result to `state`.
- `matches(work, isOpen: …)` is the whole filter in one method. Tags and fandoms are matched together (`{...work.tags, ...work.fandoms}`), and any excluded tag rejects a work before the include rules run.
- `sortWorks` is a top-level function: "Last read" keeps the repository's order, the others sort a copy.

Because none of this touches Flutter or Riverpod, the test needs nothing but the sample works:

```dart
// Domain: library filters and sorting are plain Dart, so they're tested without widgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:noctua/src/features/library/domain/library_filter.dart';
import 'package:noctua/src/features/work/data/sample_works.dart';
import 'package:noctua/src/features/work/domain/work.dart';

void main() {
  final works = SampleWorks.works;

  test('TriState cycles off → include → exclude and back', () {
    expect(TriState.off.next, TriState.include);
    expect(TriState.include.next, TriState.exclude);
    expect(TriState.exclude.next, TriState.off);
    expect(TriState.include.allows(false), isFalse);
    expect(TriState.exclude.allows(false), isTrue);
  });

  test('the default filter lets every work through', () {
    const f = LibraryFilter();
    expect(works.where(f.matches), hasLength(works.length));
    expect(f.activeCount, 0);
  });

  test('flags include, then exclude', () {
    final include = const LibraryFilter().cycleFlag('downloaded');
    expect(works.where(include.matches).every((w) => w.downloaded), isTrue);
    final exclude = include.cycleFlag('downloaded');
    expect(works.where(exclude.matches).every((w) => !w.downloaded), isTrue);
    expect(exclude.activeFilterCount, 1);
  });

  test('turning a source off hides its works', () {
    final f = const LibraryFilter().toggleSource(Source.ao3);
    expect(works.where(f.matches).any((w) => w.source == Source.ao3), isFalse);
  });

  test('tags: match all versus match any', () {
    final a = works.first.tags.first;
    final b = works.last.tags.first;
    final all = const LibraryFilter().cycleTag(a).cycleTag(b);
    final any = all.copyWith(matchAll: false);
    expect(works.where(any.matches).length, greaterThanOrEqualTo(works.where(all.matches).length));
    expect(works.where(all.matches).every((w) => w.tags.contains(a) && w.tags.contains(b)), isTrue);
  });

  test('sortWorks sorts by title and keeps last-read order by default', () {
    final byTitle = sortWorks(works, 'Title', descending: false).map((w) => w.title).toList();
    expect(byTitle, [...byTitle]..sort());
    expect(sortWorks(works, 'Title', descending: true).first.title, byTitle.last);
    expect(sortWorks(works, 'Last read', descending: false), works);
  });

  test('Work.matchesQuery searches title, authors, tags and fandoms', () {
    final w = works.first;
    expect(w.matchesQuery(w.title.toLowerCase()), isTrue);
    expect(w.matchesQuery(w.fandoms.first.toLowerCase()), isTrue);
    expect(w.matchesQuery('zzzz-no-such-thing'), isFalse);
  });
}
```

**Step 5: the library controllers (presentation).** What the screens watch, built from the repositories and the domain rules:

```dart
import 'package:noctua/src/features/library/data/library_repository.dart';
import 'package:noctua/src/features/library/domain/library_filter.dart';
import 'package:noctua/src/features/tabs/data/tabs_repository.dart';
import 'package:noctua/src/features/work/data/works_repository.dart';
import 'package:noctua/src/features/work/domain/work.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_controllers.g.dart';

/// The filter sheet's state, shared by the sheet and the library page. The
/// rules themselves live on [LibraryFilter] in the domain layer.
@Riverpod(keepAlive: true)
class LibraryFilterController extends _$LibraryFilterController {
  @override
  LibraryFilter build() => const LibraryFilter();

  void cycleFlag(String key) => state = state.cycleFlag(key);
  void cycleTag(String tag) => state = state.cycleTag(tag);
  void toggleSource(Source s) => state = state.toggleSource(s);
  void setMatchAll(bool v) => state = state.copyWith(matchAll: v);
  void reset() => state = const LibraryFilter();
}

/// Works shown in one library category: saved works in that category that pass
/// the filter and "Downloaded only", in the chosen sort order.
@riverpod
List<Work> libraryWorks(Ref ref, String category) {
  final saved = ref.watch(libraryRepositoryProvider);
  final filter = ref.watch(libraryFilterControllerProvider);
  final downloadedOnly = ref.pref(Prefs.downloadedOnly);
  final openIds = {for (final t in ref.watch(tabsRepositoryProvider)) t.workId};
  final works = [
    for (final w in ref.watch(worksRepositoryProvider).fetchLibraryWorks())
      if (saved.contains(w.id) &&
          w.category == category &&
          (!downloadedOnly || w.downloaded) &&
          filter.matches(w, isOpen: openIds.contains(w.id)))
        w,
  ];
  return sortWorks(works, ref.pref(Prefs.librarySort), descending: ref.pref(Prefs.librarySortDesc));
}

/// Saved works per category, ignoring the filter (for the tab badges).
@riverpod
Map<String, int> categoryCounts(Ref ref) {
  final saved = ref.watch(libraryRepositoryProvider);
  final works = ref.watch(worksRepositoryProvider).fetchLibraryWorks();
  return {for (final c in ref.watch(libraryCategoriesProvider)) c: works.where((w) => saved.contains(w.id) && w.category == c).length};
}
```

- `LibraryFilterController` holds the filter for the sheet and the page. Each method is one line that delegates to the domain, which keeps the rules testable without a widget.
- `libraryWorks` is a family: `libraryWorksProvider('Reading')` and `libraryWorksProvider('Completed')` are separate cached values. It is `@riverpod` (auto-dispose), so a category nobody is looking at is recomputed fresh next time.
- Everything the result depends on is `watch`ed: saved ids, the filter, the "Downloaded only" mode, sort settings, and open tabs (for the "Open in a tab" filter). Changing any of them recomputes the list.

The open-tabs filter reads `tabsRepositoryProvider`, which [[Milestone 08 - The reader and open works|milestone 8]] builds. Until then, drop the `openIds` line and pass `isOpen: false`.

Selection is its own provider, so the app bar, every tile and the back button can all react to it:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_selection_controller.g.dart';

/// Works selected with a long press; empty when not in selection mode.
@Riverpod(keepAlive: true)
class LibrarySelectionController extends _$LibrarySelectionController {
  @override
  Set<String> build() => {};

  void toggle(String id) => state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
  void selectAll(Iterable<String> ids) => state = {...state, ...ids};
  void clear() => state = {};
}
```

**Step 6: the library page.** A `DefaultTabController` with one tab per category, and an app bar that becomes a selection bar while anything is selected:

```dart
@RoutePage()
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchKey = GlobalKey();
  final _tabsKey = GlobalKey();
  final _filterKey = GlobalKey();
  final _tabCountKey = GlobalKey();
  final _gridKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(categoryCountsProvider);
    final filter = ref.watch(libraryFilterControllerProvider);
    final showCounts = ref.pref(Prefs.showTabCounts);
    final selected = ref.watch(librarySelectionControllerProvider);
    final coach = ref.pref(Prefs.coachPending);

    final scaffold = DefaultTabController(
      length: ref.watch(libraryCategoriesProvider).length,
      child: Scaffold(
        appBar: selected.isNotEmpty
            ? _selectionBar(context, selected)
            : AppBar(
                title: const Text('Library'),
                // M3: at most two actions plus overflow.
                actions: [
                  IconButton(
                    key: _searchKey,
                    tooltip: 'Search library and downloads',
                    icon: const Icon(Symbols.search_rounded),
                    onPressed: () => context.router.push(const DeepSearchRoute()),
                  ),
                  KeyedSubtree(key: _tabCountKey, child: const TabCountButton()),
                  PopupMenuButton<String>(
                    tooltip: 'More options',
                    icon: const Icon(Symbols.more_vert_rounded),
                    onSelected: (v) => showPlaceholder(context, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'Updating library', child: Text('Update library')),
                      PopupMenuItem(value: 'Updating category', child: Text('Update this category')),
                      PopupMenuItem(value: 'Opening a random work', child: Text('Open random work')),
                    ],
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          key: _tabsKey,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          dividerColor: Colors.transparent,
                          tabs: [
                            for (final c in ref.watch(libraryCategoriesProvider))
                              Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(c),
                                    if (showCounts) ...[const SizedBox(width: 6), _TabCount(counts[c] ?? 0)],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: _filterKey,
                        tooltip: 'Filter, tags, sort and display',
                        onPressed: () => showLibraryFilterSheet(context),
                        icon: Badge(
                          isLabelVisible: filter.activeCount > 0,
                          label: Text('${filter.activeCount}'),
                          child: const Icon(Symbols.filter_list_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: TabBarView(
          key: _gridKey,
          children: [for (final c in ref.watch(libraryCategoriesProvider)) _CategoryView(category: c, query: '')],
        ),
      ),
    );
```

- `TabCountButton` and the search button come from milestones 8 and 9; add placeholder `IconButton`s for now.
- The `Badge` on the filter icon shows the active filter count from `LibraryFilter.activeCount`.
- The `GlobalKey`s on the search button, tabs, filter button and tab counter exist for [[Milestone 12 - Onboarding|milestone 12]]'s coach marks, which need to find those widgets on screen.

The rest of `build` handles the back button and the two-pane layout:

```dart
    return PopScope(
      canPop: selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(librarySelectionControllerProvider.notifier).clear();
      },
      child: Stack(
        children: [
          if (_twoPane(context))
            Row(
              children: [
                Expanded(child: scaffold),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 440,
                  child: switch (ref.watch(tabletDetailControllerProvider)) {
                    null => Center(
                      child: Text(
                        'Pick a work to see its details',
                        style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                    final id => WorkDetailsPage(key: ValueKey(id), workId: id),
                  },
                ),
              ],
            )
          else
            scaffold,
```

`PopScope(canPop: selected.isEmpty)` makes the system back gesture clear the selection instead of leaving the app. `onPopInvokedWithResult` runs either way; `didPop` is false when the pop was blocked, which is exactly when to clear. The two-pane `Row` is [[Milestone 13 - Errors, tablets and e-ink|milestone 13]]'s tablet layout; on phones `scaffold` is used directly.

The selection bar and the "Move to category" sheet:

```dart
  PreferredSizeWidget _selectionBar(BuildContext context, Set<String> selected) {
    final sel = ref.read(librarySelectionControllerProvider.notifier);
    return AppBar(
      backgroundColor: context.colors.surfaceContainerHigh,
      leading: IconButton(tooltip: 'Cancel selection', icon: const Icon(Symbols.close_rounded), onPressed: sel.clear),
      title: Text('${selected.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Symbols.select_all_rounded),
          onPressed: () => sel.selectAll(ref.read(libraryRepositoryProvider)),
        ),
        IconButton(tooltip: 'Move to category', icon: const Icon(Symbols.label_rounded), onPressed: () => _moveSheet(context, selected)),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'remove') {
              for (final id in selected) {
                ref.read(libraryRepositoryProvider.notifier).toggle(id);
              }
            }
            showPlaceholder(context, switch (v) {
              'read' => 'Marked ${selected.length} as read',
              'download' => 'Queued ${selected.length} works',
              _ => 'Removed ${selected.length} from library',
            });
            sel.clear();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'read', child: Text('Mark as read')),
            PopupMenuItem(value: 'download', child: Text('Download unread')),
            PopupMenuItem(value: 'remove', child: Text('Remove from library')),
          ],
        ),
      ],
    );
  }

  void _moveSheet(BuildContext context, Set<String> selected) {
    final picked = <String>{};
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Move ${selected.length} works', style: context.text.titleMedium),
              for (final c in ref.watch(libraryCategoriesProvider))
                CheckboxListTile(
                  value: picked.contains(c),
                  title: Text(c),
                  onChanged: (v) => setSheet(() => v == true ? picked.add(c) : picked.remove(c)),
                ),
              ListTile(
                leading: const Icon(Symbols.edit_rounded),
                title: const Text('Edit categories'),
                onTap: () {
                  Navigator.pop(sheet);
                  context.router.push(const EditCategoriesRoute());
                },
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: () {
                    Navigator.pop(sheet);
                    showPlaceholder(context, 'Moved to ${picked.isEmpty ? 'Default' : picked.join(', ')}');
                    ref.read(librarySelectionControllerProvider.notifier).clear();
                  },
                  child: const Text('Move'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

The sheet keeps its checkbox state in a local `Set` and rebuilds with `StatefulBuilder`, because a bottom sheet is a separate route and doesn't rebuild when the page calls `setState`.

**Step 7: one category.** Each tab is a `_CategoryView` that watches its family member and picks the layout from preferences:

```dart
class _CategoryView extends ConsumerWidget {
  const _CategoryView({required this.category, required this.query});
  final String category;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.pref(Prefs.libraryLayout);
    // The setting is for phones; wider screens keep covers about phone-sized (~140 dp) instead of stretching them.
    final width = MediaQuery.sizeOf(context).width - (context.useTwoPanes ? 520 : 0);
    final columns = width >= 600 ? (width / 140).floor() : ref.pref(Prefs.gridColumns);
    final showContinue = ref.pref(Prefs.showContinueCard);
    var works = ref.watch(libraryWorksProvider(category));
    if (query.isNotEmpty) {
      works = works
          .where(
            (w) =>
                w.title.toLowerCase().contains(query) ||
                w.authorLine.toLowerCase().contains(query) ||
                w.fandoms.any((f) => f.toLowerCase().contains(query)),
          )
          .toList();
    }

    if (works.isEmpty) {
      return _EmptyCategory(filtered: ref.watch(libraryFilterControllerProvider).activeCount > 0 || query.isNotEmpty);
    }

    return CustomScrollView(
      slivers: [
        if (showContinue && category == 'Reading' && query.isEmpty) const SliverToBoxAdapter(child: _ContinueCard(workId: 'salt')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          sliver: switch (layout) {
            'list' => SliverList.builder(itemCount: works.length, itemBuilder: (_, i) => _ListRow(works[i])),
            'widgets' => SliverList.builder(itemCount: works.length, itemBuilder: (_, i) => _WidgetCard(works[i])),
            _ => SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
                // Cover (2:3) + 6 dp gap + the title lines, so rows sit snugly at any width.
                mainAxisExtent:
                    (width - 24 - 8 * (columns - 1)) / columns * 1.5 +
                    6 +
                    (columns >= 4 ? 1 : 2) * 20 * MediaQuery.textScalerOf(context).scale(1),
              ),
              itemCount: works.length,
              itemBuilder: (_, i) => _GridTile(works[i], titleLines: columns >= 4 ? 1 : 2),
            ),
          },
        ),
      ],
    );
  }
```

- On phones the grid uses the "Grid columns" setting. From 600 dp it computes columns from the width instead (`width / 140`), so tablet covers stay phone-sized rather than stretching to the setting's 3 columns.
- `mainAxisExtent` fixes each grid cell's height: the cover's height (width × 1.5 for 2:3), a 6 dp gap, and one or two lines of title scaled by the user's font size (`MediaQuery.textScalerOf`). Without it the grid would guess an aspect ratio and clip titles at large font sizes.
- `switch (layout)` returns a different sliver per layout, so the Continue card can sit above any of them in the same `CustomScrollView`.

**Step 8: taps, long presses and tiles.** Mihon's selection model in three small functions:

```dart
/// Two panes on large windows: the library on the left, work details on the right.
bool _twoPane(BuildContext context) => context.useTwoPanes;

void _openDetails(BuildContext context, WidgetRef ref, Work w) {
  if (_twoPane(context)) {
    ref.read(tabletDetailControllerProvider.notifier).show(w.id);
  } else {
    context.router.push(WorkDetailsRoute(workId: w.id));
  }
}

/// In selection mode a tap toggles; otherwise it opens the work.
void _tap(BuildContext context, WidgetRef ref, Work w) {
  if (ref.read(librarySelectionControllerProvider).isNotEmpty) {
    ref.read(librarySelectionControllerProvider.notifier).toggle(w.id);
  } else {
    _openDetails(context, ref, w);
  }
```

The grid tile watches only whether its own work is selected, with `select`, so selecting one work rebuilds one tile rather than the whole grid:

```dart
class _GridTile extends ConsumerWidget {
  const _GridTile(this.work, {this.titleLines = 2});
  final Work work;
  final int titleLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.pref(Prefs.showUnreadBadge);
    final downloaded = ref.pref(Prefs.showDownloadedBadge);
    final source = ref.pref(Prefs.showSourceBadge);
    final selected = ref.watch(librarySelectionControllerProvider.select((s) => s.contains(work.id)));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _tap(context, ref, work),
      onLongPress: () => _longPress(context, ref, work),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              WorkCover(work: work, showUnread: unread, showDownloaded: downloaded, showSource: source),
              if (selected)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.primary, width: 3),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Symbols.check_circle_rounded, fill: 1, color: context.colors.onPrimary),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(work.title, maxLines: titleLines, overflow: TextOverflow.ellipsis, style: context.text.labelLarge),
        ],
      ),
    );
  }
}
```

The widgets layout card (the layout is a preference, so it is restored after a restart):

```dart
/// "Widgets" layout: a detail card showing title, author(s) and fandom(s).
class _WidgetCard extends ConsumerWidget {
  const _WidgetCard(this.work);
  final Work work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Card.filled(
      color: c.surfaceContainer,
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      shape: ref.watch(librarySelectionControllerProvider.select((s) => s.contains(work.id)))
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: c.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: () => _tap(context, ref, work),
        onLongPress: () => _longPress(context, ref, work),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 64, child: WorkCover(work: work, showTitle: false, radius: 8)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(work.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      work.authorLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(color: c.primary),
                    ),
                    Text(
                      work.fandoms.join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${work.source.badge} · ${work.words} words · Ch ${work.lastChapter}/${work.chapters}'
                      '${work.unread > 0 ? ' · ${work.unread} new' : ''}',
                      style: context.text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

The empty state distinguishes "nothing saved" from "everything filtered out", and offers to clear filters in the second case:

```dart
class _EmptyCategory extends ConsumerWidget {
  const _EmptyCategory({required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(filtered ? Symbols.filter_alt_off_rounded : Symbols.auto_stories_rounded, size: 48, color: context.colors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            filtered ? 'Nothing matches your filters' : 'Nothing here yet',
            style: context.text.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            filtered ? 'Try clearing a filter, or turn off Downloaded only.' : 'Works you add from Browse land in this category.',
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (filtered)
            FilledButton.tonal(
              onPressed: () {
                ref.read(libraryFilterControllerProvider.notifier).reset();
                ref.setPref(Prefs.downloadedOnly, false);
              },
              child: const Text('Clear filters'),
            ),
        ],
      ),
    ),
  );
}
```

**Step 9: the filter sheet.** A modal bottom sheet with four tabs. `isScrollControlled: true` lets it be taller than half the screen; the fixed height (78% of the screen) keeps it the same size on every tab.

```dart
/// Mihon-style library sheet: Filter · Tags · Sort · Display.
Future<void> showLibraryFilterSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => SizedBox(height: MediaQuery.sizeOf(context).height * 0.78, child: const _LibrarySheet()),
);

class _LibrarySheet extends ConsumerWidget {
  const _LibrarySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterControllerProvider);
    final shown = ref.watch(libraryCategoriesProvider).fold<int>(0, (n, c) => n + ref.watch(libraryWorksProvider(c)).length);

    Tab tab(String label, int count) => Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[const SizedBox(width: 6), Badge(label: Text('$count'))],
        ],
      ),
    );

    return DefaultTabController(
      length: 4,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          return Column(
            children: [
              TabBar(
                tabs: [
                  tab('Filter', filter.activeFilterCount),
                  tab('Tags', filter.activeTagCount),
                  const Tab(text: 'Sort'),
                  const Tab(text: 'Display'),
                ],
              ),
              const Expanded(child: TabBarView(children: [_FilterTab(), _TagsTab(), _SortTab(), _DisplayTab()])),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    TextButton(onPressed: ref.read(libraryFilterControllerProvider.notifier).reset, child: const Text('Reset')),
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => controller.index == 1
                          ? TextButton(
                              onPressed: () => showPlaceholder(context, 'Saved as a library tab'),
                              child: const Text('Save as tab'),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const Spacer(),
                    FilledButton(onPressed: () => Navigator.pop(context), child: Text('Show $shown works')),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
```

- The footer button reads "Show N works" by summing every category's `libraryWorks`, so the count updates live as filters change.
- `ListenableBuilder(listenable: controller)` rebuilds just the "Save as tab" button when the tab changes, without making the whole sheet stateful.

The Filter tab is a list of tri-state rows built from a list of records:

```dart
IconData _triIcon(TriState s) => switch (s) {
  TriState.include => Symbols.check_box_rounded,
  TriState.exclude => Symbols.disabled_by_default_rounded,
  TriState.off => Symbols.check_box_outline_blank_rounded,
};

class _FilterTab extends ConsumerWidget {
  const _FilterTab();

  static const _flags = [
    ('downloaded', 'Downloaded', 'Saved for offline reading'),
    ('unread', 'Unread', 'Has chapters you haven’t read'),
    ('started', 'Started', 'At least one chapter read'),
    ('completed', 'Completed', 'Marked complete by the author'),
    ('stale', 'Possibly abandoned', 'No update in 12 months'),
    ('open', 'Open in a tab', 'Currently in Open works'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterControllerProvider);
    final n = ref.read(libraryFilterControllerProvider.notifier);
    return ListView(
      children: [
        for (final (key, title, sub) in _flags)
          ListTile(
            leading: Icon(
              _triIcon(filter.flags[key] ?? TriState.off),
              fill: 1,
              color: (filter.flags[key] ?? TriState.off) == TriState.off ? null : context.colors.primary,
            ),
            title: Text(title),
            subtitle: Text(sub),
            onTap: () => n.cycleFlag(key),
          ),
        const SectionLabel('Sources'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final s in Source.values)
                FilterChip(label: Text(s.badge), selected: filter.sources.contains(s), onSelected: (_) => n.toggleSource(s)),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
```

Tags use a tri-state chip: plain when off, a check when included, and the error colors with a cross when excluded:

```dart
class _TriChip extends StatelessWidget {
  const _TriChip({required this.label, required this.state, required this.onTap});
  final String label;
  final TriState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final exclude = state == TriState.exclude;
    return FilterChip(
      showCheckmark: false,
      selected: state != TriState.off,
      selectedColor: exclude ? c.errorContainer : null,
      avatar: switch (state) {
        TriState.include => const Icon(Symbols.check_rounded, size: 18),
        TriState.exclude => Icon(Symbols.close_rounded, size: 18, color: c.onErrorContainer),
        TriState.off => null,
      },
      label: Text(label, style: exclude ? TextStyle(color: c.onErrorContainer) : null),
      onSelected: (_) => onTap(),
    );
  }
}
```

Sort writes straight to preferences. Tapping the active sort flips its direction; tapping another selects it:

```dart
class _SortTab extends ConsumerWidget {
  const _SortTab();

  static const _sorts = [
    ('Last read', 'Most recent first', 'Oldest first'),
    ('Latest chapter', 'Newest first', 'Oldest first'),
    ('Predicted next update', 'Soonest first', 'Latest first'),
    ('Date added', 'Newest first', 'Oldest first'),
    ('Title', 'Z to A', 'A to Z'),
    ('Word count', 'Longest first', 'Shortest first'),
    ('Unread chapters', 'Most first', 'Fewest first'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.pref(Prefs.librarySort);
    final desc = ref.pref(Prefs.librarySortDesc);
    return ListView(
      children: [
        for (final (label, down, up) in _sorts)
          ListTile(
            leading: SizedBox(
              width: 24,
              child: sort == label
                  ? Icon(desc ? Symbols.arrow_downward_rounded : Symbols.arrow_upward_rounded, color: context.colors.primary)
                  : null,
            ),
            title: Text(label),
            subtitle: sort == label ? Text(desc ? down : up) : null,
            selected: sort == label,
            onTap: () {
              if (sort == label) {
                ref.setPref(Prefs.librarySortDesc, !desc);
              } else {
                ref.setPref(Prefs.librarySort, label);
              }
            },
          ),
      ],
    );
  }
}
```

**Step 10: routes.** Annotate `LibraryPage` and `EditCategoriesPage` with `@RoutePage()`, add `AutoRoute(page: EditCategoriesRoute.page)` to the router, and run build_runner. `EditCategoriesPage` is a `ReorderableListView` over a copy of `libraryCategoriesProvider` with rename and delete dialogs; it keeps its edits in local state because categories aren't stored yet.

> [!success] Checkpoint
> the library shows the sample works in three columns of covers. The filter badge counts active filters. Long-press a cover to select it, then tap a second one; the app bar shows “2 selected”.

![[noctua-m06-library-layouts.png]]
*Milestone 6: cover grid and the widgets layout restored from preferences*

![[noctua-m06-library-filters.png]]
*Milestone 6: filter sheet and multi-select*

---
← [[Milestone 05 - Theming and the app shell]] · [[00 Index|Index]] · [[Milestone 07 - Work details]] →
