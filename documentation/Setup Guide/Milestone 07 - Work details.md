---
title: "Milestone 7: Work details"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 7
aliases:
  - Milestone 7
updated: 2026-11-06
---
# Milestone 7: Work details

Tapping a work opens its details page: cover, title, authors, fandoms, a Mihon-style summary, tags, actions and the chapter list.

1. **`work/presentation/work_details_page.dart`:**
   - One `_expanded` flag opens title, authors, fandoms, summary and tags together.
   - The summary clamps to 3 lines with a fade, and tags scroll sideways until expanded.
   - Author names are `TapGestureRecognizer` spans that push `AuthorRoute`.
   - A series row (“Part 2 of 4 in The Keepers of Harrow Point”) pushes `SeriesRoute`.
   - Four action tiles: Add to library (through `LibraryRepository`), Auto-update, Export EPUB, Check for AI.
   - The chapter list sorts newest or oldest first, and two floating buttons open a new tab or resume reading.
2. **`work/presentation/series_page.dart` and `author_page.dart`:** reading order with “Add missing parts to library”; author profile with follow, pseuds, series and works.
3. **`work/presentation/content_warning_page.dart`:** an interstitial for Explicit works or works with archive warnings. `openWithWarning(context, ref, work)` decides whether to show it or go straight to the reader, and every “read” button calls it.
4. **`ai/` feature** (presentation only for now; a detector would add `data/` and `domain/`): `ai_check_sheet.dart` runs the (placeholder) check and shows the score, the three signals (author tags, reader reports, text detector) and a report button. `AiWarningBanner` sits under the header when the score passes the threshold set in Settings. Keeping AI in its own feature means turning it off or replacing the detector touches one folder.

## Code walkthrough: milestone 7

**Step 1: the page and its local state.** The details page keeps two booleans in its `State`: whether the header is expanded and the chapter sort order. Neither is worth a provider, because nothing outside this page cares. The work comes from `workProvider(widget.workId)` and its chapters from `WorksRepository.fetchChapters`, and library membership from `libraryRepositoryProvider`, so the heart button and the library grid stay in sync.

```dart
@RoutePage()
class WorkDetailsPage extends ConsumerStatefulWidget {
  const WorkDetailsPage({super.key, required this.workId});
  final String workId;

  @override
  ConsumerState<WorkDetailsPage> createState() => _WorkDetailsPageState();
}

class _WorkDetailsPageState extends ConsumerState<WorkDetailsPage> {
  /// One expanded state for the whole header: title, authors, fandoms,
  /// summary and tags all open and close together.
  bool _expanded = false;
  bool _newestFirst = true;

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(workProvider(widget.workId));
    final inLibrary = ref.watch(libraryRepositoryProvider).contains(w.id);
    var chapters = ref.watch(worksRepositoryProvider).fetchChapters(w);
    if (!_newestFirst) chapters = chapters.reversed.toList();
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Download chapters',
            icon: const Icon(Symbols.download_rounded),
            onPressed: () => showPlaceholder(context, 'Queued unread chapters'),
          ),
          const TabCountButton(),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (v) => showPlaceholder(context, v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'Opening on ${w.source.label}', child: Text('Open on ${w.source.label}')),
              const PopupMenuItem(value: 'Link copied', child: Text('Copy link')),
              const PopupMenuItem(value: 'Moved', child: Text('Change category')),
              const PopupMenuItem(value: 'Migrating', child: Text('Migrate to another source')),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.list(
              children: [
                _Header(work: w, expanded: _expanded, onExpand: () => setState(() => _expanded = !_expanded)),
                const SizedBox(height: 4),
                if (w.series != null) _SeriesRow(series: w.series!),
                AiWarningBanner(work: w),
                const SizedBox(height: 12),
                _ActionRow(work: w, inLibrary: inLibrary),
                const SizedBox(height: 12),
                _Stats(work: w),
                const SizedBox(height: 16),
                _Summary(work: w, expanded: _expanded, onToggle: () => setState(() => _expanded = !_expanded)),
                const SizedBox(height: 8),
                _Tags(tags: w.tags, wrap: _expanded),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('${w.chapters} chapters', style: context.text.titleMedium)),
                    TextButton.icon(
                      onPressed: () => setState(() => _newestFirst = !_newestFirst),
                      icon: const Icon(Symbols.sort_rounded, size: 18),
                      label: Text(_newestFirst ? 'Newest first' : 'Oldest first'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SliverList.builder(
            itemCount: chapters.length,
            itemBuilder: (context, i) {
              final ch = chapters[i];
              final dim = ch.read ? c.outline : null;
              return ListTile(
                title: Text(
                  ch.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: dim),
                ),
                subtitle: Text(
                  ch.progress != null ? '${ch.date} · ${(ch.progress! * 100).round()}% read' : '${ch.date} · ${ch.words}',
                  style: TextStyle(color: dim),
                ),
                trailing: ch.downloaded
                    ? Icon(Symbols.offline_pin_rounded, fill: 1, color: context.noctua.success, semanticLabel: 'Downloaded')
                    : IconButton(
                        tooltip: 'Download chapter',
                        icon: const Icon(Symbols.download_rounded),
                        onPressed: () => showPlaceholder(context, 'Queued ${ch.label}'),
                      ),
                onTap: () => openWithWarning(context, ref, w, chapter: ch.number),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon-only so the pair still fits with large text sizes.
          FloatingActionButton(
            heroTag: 'newTab',
            tooltip: 'Open in a new tab',
            backgroundColor: c.secondaryContainer,
            foregroundColor: c.onSecondaryContainer,
            onPressed: () {
              ref.read(tabsRepositoryProvider.notifier).open(w.id);
              showPlaceholder(context, 'Opened in a new tab');
            },
            child: const Icon(Symbols.tab_rounded),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'resume',
            onPressed: () => openWithWarning(context, ref, w),
            icon: const Icon(Symbols.play_arrow_rounded, fill: 1),
            label: Text(w.lastChapter > 1 ? 'Resume Ch ${w.lastChapter}' : 'Start reading'),
          ),
        ],
      ),
    );
  }
```

- `workId` is a constructor parameter, so auto_route generates `WorkDetailsRoute(workId: …)` with it as a required argument.
- The page body is one `CustomScrollView`: the header parts go in a `SliverList.list` (a fixed list of widgets), and the chapters in a `SliverList.builder`, so only visible chapter rows are built even for a 400-chapter work.
- Every chapter tap goes through `openWithWarning` (step 5), never straight to the reader.
- The two floating buttons have distinct `heroTag`s; two FABs with the default tag on one page throw during route transitions.
- The trailing 96 dp `SizedBox` keeps the last chapter from hiding under the buttons.
- `TabCountButton` and `AiWarningBanner` come from [[Milestone 08 - The reader and open works|milestone 8]] and step 6 below.

**Step 2: the header.** Title, authors, fandoms and status beside the cover. Collapsed, it shows two authors and two fandoms with "+N more"; expanded, it shows everything, including the account behind each pseud:

```dart
class _Header extends StatelessWidget {
  const _Header({required this.work, required this.expanded, required this.onExpand});
  final Work work;
  final bool expanded;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = context.text.bodyMedium?.copyWith(color: c.onSurfaceVariant);
    final link = context.text.bodyMedium?.copyWith(color: c.primary, fontWeight: FontWeight.w500);

    final authors = expanded ? work.authors : work.authors.take(2).toList();
    final hiddenAuthors = work.authors.length - authors.length;
    final fandoms = expanded ? work.fandoms : work.fandoms.take(2).toList();
    final hiddenFandoms = work.fandoms.length - fandoms.length;
    final lines = expanded ? null : 2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: WorkCover(work: work, showUnread: false)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                work.title,
                maxLines: expanded ? null : 3,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: context.text.headlineSmall?.copyWith(fontSize: 22, height: 28 / 22),
              ),
              const SizedBox(height: 4),
              // Authors: first two, then "+N more". Pseuds show "(username)" once expanded.
              Text.rich(
                TextSpan(
                  children: [
                    for (final (i, a) in authors.indexed) ...[
                      TextSpan(
                        text: a.name,
                        style: link,
                        recognizer: TapGestureRecognizer()..onTap = () => context.router.push(AuthorRoute(name: a.pseudOf ?? a.name)),
                      ),
                      if (expanded && a.pseudOf != null)
                        TextSpan(
                          text: ' (${a.pseudOf})',
                          style: meta?.copyWith(color: c.outline),
                        ),
                      if (i < authors.length - 1) TextSpan(text: expanded && i == authors.length - 2 ? ' and ' : ', ', style: meta),
                    ],
                    if (hiddenAuthors > 0) TextSpan(text: ' +$hiddenAuthors more', style: link),
                  ],
                ),
                maxLines: lines,
                overflow: lines == null ? null : TextOverflow.ellipsis,
              ),
              GestureDetector(
                onTap: hiddenAuthors > 0 || hiddenFandoms > 0 ? onExpand : null,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: fandoms.join(', '), style: meta),
                      if (hiddenFandoms > 0) TextSpan(text: ' +$hiddenFandoms', style: link),
                    ],
                  ),
                  maxLines: lines,
                  overflow: lines == null ? null : TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    work.complete ? Symbols.check_circle_rounded : Symbols.schedule_rounded,
                    fill: 1,
                    size: 18,
                    color: context.noctua.success,
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text('${work.rating} · ${work.complete ? 'Complete' : 'Ongoing'} · ${work.updated}', style: meta)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- Author names are `TextSpan`s with a `TapGestureRecognizer`, so they wrap like text but tap like links. Each pushes `AuthorRoute` with the account name (`pseudOf ?? name`), because the author page is per account, not per pseud.
- The joiner logic writes "A, B and C" when expanded, and plain commas otherwise.
- `maxLines: null` means unlimited, which is how one `lines` variable switches every text between clamped and expanded.
- Recognizers created inside `build` are never disposed. That's harmless for a handful of names, but if the analyzer or DevTools flags it, move the header into a `StatefulWidget` that creates the recognizers once and disposes them in `dispose`.

**Step 3: actions, series and stats.** The action row builds four identical tiles with a local helper function, so the layout lives in one place:

```dart
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.work, required this.inLibrary});
  final Work work;
  final bool inLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Widget action(IconData icon, String label, VoidCallback onTap, {bool on = false}) => Expanded(
      child: Material(
        color: on ? c.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, fill: on ? 1 : 0, color: on ? c.onPrimaryContainer : c.onSurface),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(color: on ? c.onPrimaryContainer : c.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Row(
      children: [
        action(
          Symbols.favorite_rounded,
          inLibrary ? 'In library' : 'Add to library',
          () => ref.read(libraryRepositoryProvider.notifier).toggle(work.id),
          on: inLibrary,
        ),
        const SizedBox(width: 8),
        action(Symbols.notifications_rounded, 'Auto-update', () => showPlaceholder(context, 'Auto-update on')),
        const SizedBox(width: 8),
        action(Symbols.ios_share_rounded, 'Export EPUB', () => showPlaceholder(context, 'Exporting EPUB')),
        const SizedBox(width: 8),
        action(Symbols.smart_toy_rounded, 'Check for AI', () => showAiCheck(context, work)),
      ],
    );
  }
}

/// "Part 2 of 4 in The Keepers of Harrow Point" → Series page.
class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.series});
  final SeriesRef series;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.router.push(SeriesRoute(seriesId: series.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Symbols.library_books_rounded, color: c.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Part ${series.part} of ${series.of} in ',
                          style: TextStyle(color: c.onSurfaceVariant),
                        ),
                        TextSpan(
                          text: series.name,
                          style: TextStyle(color: c.primary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Symbols.chevron_right_rounded, color: c.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.work});
  final Work work;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (work.words, 'words'),
      ('${work.chapters}/${work.totalChapters ?? '?'}', 'chapters'),
      (work.kudos, 'kudos'),
      (work.complete ? '—' : work.nextUpdate, 'next update'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(color: context.colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (final (v, l) in stats)
            Expanded(
              child: Column(
                children: [
                  Text(v, style: context.text.titleMedium),
                  Text(l, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

`_Stats` uses a list of records `(value, label)` and destructures them in the loop; `totalChapters ?? '?'` matches AO3's "12/?" for works without a planned length.

**Step 4: the Mihon-style summary.** The summary clamps to three lines with a fade, but only when the text is actually longer than three lines. Finding that out needs a `TextPainter`, which lays text out without drawing it:

```dart
/// Mihon-style summary: 3 lines with a fade and a chevron when longer.
class _Summary extends StatelessWidget {
  const _Summary({required this.work, required this.expanded, required this.onToggle});
  final Work work;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant, height: 20 / 14);
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: work.summary, style: style),
          maxLines: 3,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        final headerClamped = work.authors.length > 2 || work.fandoms.length > 2 || work.title.length > 60;
        final canToggle = overflows || headerClamped;

        return Column(
          children: [
            Stack(
              children: [
                Text(
                  work.summary,
                  style: style,
                  maxLines: expanded || !overflows ? null : 3,
                  overflow: expanded || !overflows ? null : TextOverflow.clip,
                ),
                if (canToggle && !expanded && overflows)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 32,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [bg.withValues(alpha: 0), bg],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (canToggle)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: expanded ? 'Show less' : 'Show the full summary',
                onPressed: onToggle,
                icon: Icon(expanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded),
              ),
          ],
        );
      },
    );
  }
}

/// Tags scroll sideways while collapsed and wrap to show all when expanded.
class _Tags extends StatelessWidget {
  const _Tags({required this.tags, required this.wrap});
  final List<String> tags;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    Widget chip(String t) => Chip(label: Text(t), visualDensity: VisualDensity.compact);
    if (wrap) {
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tags) chip(t)]);
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chip(tags[i]),
      ),
    );
  }
}
```

- `TextPainter(..., maxLines: 3)..layout(maxWidth: box.maxWidth)` measures at the real width (from `LayoutBuilder`) and font scale, then `didExceedMaxLines` says whether clamping hides anything. `dispose()` frees the painter's native resources.
- The fade is a gradient from the background color (transparent) to the background color (opaque), laid over the last lines with `Positioned` and wrapped in `IgnorePointer` so taps reach the text.
- The chevron also appears when the header is what's clamped (`headerClamped`), because the same `_expanded` flag opens both.
- `_Tags` swaps between a horizontally scrolling `ListView` and a `Wrap`. `clipBehavior: Clip.none` lets chip shadows and ink extend past the 40 dp strip.

**Step 5: the content warning.** Every "read" button calls one function, so the rule lives in one place:

```dart
/// Opens [w] in the reader, via the content warning when the reader asked for one.
void openWithWarning(BuildContext context, WidgetRef ref, Work w, {int? chapter}) {
  final ask = ref.readPref(Prefs.ao3WarnFirst);
  if (ask && (w.rating == 'Explicit' || w.warnings.isNotEmpty)) {
    context.router.push(ContentWarningRoute(workId: w.id));
  } else {
    openInReader(context, ref, w.id, chapter: chapter);
  }
}
```

`ref.readPref` reads once without subscribing, which is right inside a callback. The page itself shows the rating and warnings and offers three ways out:

```dart
/// Shown before opening a work whose rating or warnings the reader asked to be told about.
@RoutePage()
class ContentWarningPage extends ConsumerWidget {
  const ContentWarningPage({super.key, required this.workId});
  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(workProvider(workId));
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.warning_rounded, size: 48, color: c.error),
              const SizedBox(height: 16),
              Text('This work may not be for everyone', style: context.text.headlineSmall),
              const SizedBox(height: 8),
              Text(w.title, style: context.text.titleMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(w.rating),
                    backgroundColor: c.errorContainer,
                    labelStyle: TextStyle(color: c.onErrorContainer),
                  ),
                  for (final warn in w.warnings) Chip(label: Text(warn)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'The author rated and tagged it this way. Noctua asks before opening works like this because of your AO3 settings.',
                style: context.text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () {
                  context.router.maybePop();
                  openInReader(context, ref, w.id);
                },
                child: const Text('Continue to the work'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => context.router.maybePop(),
                child: const Text('Go back'),
              ),
              TextButton(
                onPressed: () {
                  ref.setPref(Prefs.ao3WarnFirst, false);
                  context.router.maybePop();
                  openInReader(context, ref, w.id);
                },
                child: const Text('Continue and don’t ask again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

`context.router.maybePop()` closes the warning first, so pressing back in the reader returns to the details page rather than to the warning. "Continue and don't ask again" writes the preference and then continues, so the next Explicit work opens directly.

`openInReader` is [[Milestone 08 - The reader and open works|milestone 8]]'s helper; until then, push `ReaderRoute(workId: w.id)` directly.

**Step 6: the AI check.** A feature of its own (`features/ai/`), so it can be removed or replaced in one folder. The sheet animates a fake check with a `Timer`, then shows the score and the three signals:

```dart
/// Bottom sheet that runs the (placeholder) AI check on one work.
Future<void> showAiCheck(BuildContext context, Work work) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _AiCheckSheet(work: work),
);

class _AiCheckSheet extends ConsumerStatefulWidget {
  const _AiCheckSheet({required this.work});
  final Work work;

  @override
  ConsumerState<_AiCheckSheet> createState() => _AiCheckSheetState();
}

class _AiCheckSheetState extends ConsumerState<_AiCheckSheet> {
  double _progress = 0;
  Timer? _timer;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 60), (t) {
      setState(() => _progress = (_progress + 0.05).clamp(0, 1));
      if (_progress >= 1) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.work;
    final c = context.colors;
    final done = _progress >= 1;
    final score = w.aiLikelihood;
    final flagged = score >= 0.4;
    final level = score >= 0.7 ? 'Likely AI' : (flagged ? 'Possibly AI' : 'Likely written by a person');
```

- `Timer.periodic` advances `_progress` every 60 ms; the timer cancels itself at 100% and `dispose` cancels it if the sheet closes early. A timer that outlives its widget would call `setState` after dispose and throw.
- The score thresholds (0.4 "possibly", 0.7 "likely") are the same numbers the banner below uses.
- When the real detector exists, replace the timer with a `FutureProvider.family` keyed by work ID and `switch` on its `AsyncValue`, like the update page does.

The banner on the details page reads two AI preferences (add the keys to the registry now; [[Milestone 10 - Settings|milestone 10]] builds the AI and content page that changes them), and renders nothing when they say not to warn:

```dart
/// Notice on the work page when the work is likely AI and the reader asked to be warned.
class AiWarningBanner extends ConsumerWidget {
  const AiWarningBanner({super.key, required this.work});
  final Work work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threshold = ref.pref(Prefs.aiWarnLevel) == 'medium' ? 0.4 : 0.7;
    if (!ref.pref(Prefs.aiWarn) || work.aiLikelihood < threshold) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: c.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: Icon(Symbols.smart_toy_rounded, color: c.onErrorContainer),
          title: Text('Likely AI-generated', style: TextStyle(color: c.onErrorContainer)),
          subtitle: Text('Reader reports and the text detector both flag it.', style: TextStyle(color: c.onErrorContainer)),
          trailing: TextButton(onPressed: () => showAiCheck(context, work), child: const Text('Details')),
        ),
      ),
    );
  }
}
```

Returning `const SizedBox.shrink()` instead of `null` keeps the parent `SliverList.list` simple: it always has the same children.

**Step 7: series and author pages.** The series page lists the parts in reading order and offers to add the missing ones. The interesting part is how it finds them:

```dart
@RoutePage()
class SeriesPage extends ConsumerWidget {
  const SeriesPage({super.key, required this.seriesId});
  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(worksRepositoryProvider).fetchSeries(seriesId);
    final library = ref.watch(libraryRepositoryProvider);
    final c = context.colors;
    final known = [for (final (id, _, _) in s.parts) ?id];
    final missing = known.where((id) => !library.contains(id)).toList();
```

`[for (final (id, _, _) in s.parts) ?id]` destructures each record, ignores the title and meta (`_`), and uses `?id` (a null-aware element) to keep only parts that exist in the sample data. The series itself comes from `WorksRepository.fetchSeries`, and the "Add missing parts to library" button adds each of those through `libraryRepositoryProvider.notifier`.

The author page follows the same pattern: a header with a Follow button, pseud chips, then that author's series (`fetchSeriesByAuthor`) and works from `WorksRepository`, filtered by `authors.any((a) => a.name == name || a.pseudOf == name)`, so works posted under any of the account's pseuds are included.

**Step 8: routes.** Add the four pages and run build_runner:

```dart
AutoRoute(page: WorkDetailsRoute.page),
AutoRoute(page: SeriesRoute.page),
AutoRoute(page: AuthorRoute.page),
AutoRoute(page: ContentWarningRoute.page),
```

> [!success] Checkpoint
> open *Salt and Lantern* from the library. The series row links to the series page, author names open the author page, and Check for AI on *The Grand Convergence* shows a “Possibly AI” result.

![[noctua-m07-work-details.png]]
*Milestone 7: work details, series page and AI check*

---
← [[Milestone 06 - The library]] · [[00 Index|Index]] · [[Milestone 08 - The reader and open works]] →
