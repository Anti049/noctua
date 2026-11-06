---
title: "Milestone 9: Updates, History, Browse and sources"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 9
aliases:
  - Milestone 9
updated: 2026-11-06
---
# Milestone 9: Updates, History, Browse and sources

This milestone fills the other three tabs and everything to do with sources. Each feature gets a small repository in `data/` serving its sample data, so the screens read the same way they will once the server and source extensions exist.

1. **`updates/`:** `domain/update_item.dart` (`UpdateItem`, `ExpectedUpdate`), `data/updates_repository.dart` (`fetchRecentUpdates`, `fetchExpectedUpdates`), and `updates_page.dart`: new chapters grouped by day, an “Expected soon” strip with a confidence level for each prediction, and per-row download and mark-read actions.
2. **`history/`:** `data/history_repository.dart` (`fetchHistory`, `fetchWeek`), `history_page.dart` with a weekly reading chart and recent chapters, and `stats_page.dart` for reading statistics.
3. **`browse/`:**
   - `data/extensions_repository.dart`: installed, pending and available extensions, and the saved searches.
   - `browse_page.dart`: Sources, Extensions and Migrate tabs under one search bar. Sources can be pinned and have a settings shortcut; “Opened recently, not saved” lists works read without saving (this is how you reach the save prompt).
   - `extension_repos_page.dart`: add and remove extension repositories, with a trust warning.
   - `source_settings_page.dart` and `source_sign_ins_page.dart`: per-source options (adult content, ask before opening, author’s notes, request delay, cookies) and the sign-in list.
   - `source_login_page.dart`: a stand-in for the WebView login, including the Cloudflare check. `domain/source_sign_in.dart` maps a source to its signed-in preference.
   - `import_page.dart`: EPUBs, Calibre, AO3 bookmarks or a link list, then a review step showing which works matched a source.
   - `muted_tags_page.dart`: muted tags, fandoms, authors and warnings, stored as JSON lists in preferences.
4. **`downloads/`:** the download queue (pause, reorder, per-work groups) and download settings.
5. **`library/presentation/deep_search_page.dart`:** the library’s search button now searches titles, authors, fandoms and tags, plus passages inside downloaded chapters, with the match highlighted. Matching works is `Work.matchesQuery` from the domain; passages come from `ChaptersRepository.searchDownloaded`.

## Code walkthrough: milestone 9

These features are mostly screens over sample data, so the walkthrough focuses on the patterns that repeat: small repositories, Freezed rows with positional fields, lists of records driving layouts, preferences holding JSON, and local state for things nothing else needs to know.

**Step 1: Updates models and repository.** Positional Freezed constructors read naturally for small value types:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'update_item.freezed.dart';

/// A new chapter in the Updates list.
@freezed
abstract class UpdateItem with _$UpdateItem {
  const factory UpdateItem(String workId, String chapter, {@Default(false) bool downloaded, @Default(false) bool read}) = _UpdateItem;
}

/// A predicted next chapter, from the author's posting rhythm.
@freezed
abstract class ExpectedUpdate with _$ExpectedUpdate {
  const factory ExpectedUpdate(
    String workId,
    String when,
    String why,

    /// 0 = unsure, 1 = likely, 2 = very likely.
    int confidence,
  ) = _ExpectedUpdate;
}
```

```dart
import 'package:noctua/src/features/updates/domain/update_item.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'updates_repository.g.dart';

/// New chapters in the library and predicted updates. Serves sample data until
/// update checks run against real sources.
class UpdatesRepository {
  const UpdatesRepository();

  static const _today = [
    UpdateItem('salt', 'Ch 40 · The Drowned Bell'),
    UpdateItem('iron', 'Interlude 4.2', downloaded: true),
    UpdateItem('river', 'Ch 18 · Silt', downloaded: true),
  ];

  static const _yesterday = [
    UpdateItem('cartography', 'Ch 21 · Dawn Roads', downloaded: true),
    UpdateItem('halvard', 'Ch 9 · Seed Day', read: true),
  ];

  static const _expected = [
    ExpectedUpdate('iron', '~Tue', 'Posts every 6 days', 2),
    ExpectedUpdate('lamplighter', '~2 days', 'Usually weekends', 1),
    ExpectedUpdate('ninefold', 'Unsure', 'Irregular schedule', 0),
  ];

  /// New chapters, newest day first, as (day label, updates).
  List<(String, List<UpdateItem>)> fetchRecentUpdates() => [('Today', _today), ('Yesterday', _yesterday)];

  /// Works likely to update soon, with how confident the prediction is.
  List<ExpectedUpdate> fetchExpectedUpdates() => _expected;
}

@Riverpod(keepAlive: true)
UpdatesRepository updatesRepository(Ref ref) => const UpdatesRepository();
```

Every sample-data repository in this milestone has the same shape: a `const` class with `fetchX` methods that return domain models, and a `keepAlive` provider. History (`fetchHistory`, `fetchWeek`) and Browse's extensions (`fetchPendingUpdates`, `fetchInstalled`, `fetchAvailable`) follow it exactly. Records such as `(String day, List<UpdateItem> items)` keep grouping out of the screens.

`confidence` is an `int` index rather than an enum so it can index straight into a list of colors (step 2). If the predictions ever come from a server, swap it for an enum with a `color` getter.

**Step 2: the Updates page.** The "checking" state is local, because only this page shows it. Pull-to-refresh and the refresh button call the same method:

```dart
class UpdatesPage extends ConsumerStatefulWidget {
  const UpdatesPage({super.key});

  @override
  ConsumerState<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends ConsumerState<UpdatesPage> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final predict = ref.pref(Prefs.predictUpdates);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Updates'),
            Text(
              _checking ? 'Checking 94 works…' : 'Checked 12 min ago · 7 new',
              style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Check for updates', icon: const Icon(Symbols.refresh_rounded), onPressed: _checking ? null : _check),
          const TabCountButton(),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (v) => showPlaceholder(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'Downloading all new chapters', child: Text('Download all new')),
              PopupMenuItem(value: 'Marked all as read', child: Text('Mark all as read')),
            ],
          ),
        ],
        bottom: _checking ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: RefreshIndicator(
        onRefresh: _check,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (predict) const _ExpectedSoon(),
            for (final (day, items) in ref.watch(updatesRepositoryProvider).fetchRecentUpdates()) ...[
              SectionLabel(day),
              for (final u in items) _UpdateRow(u),
            ],
          ],
        ),
      ),
    );
  }
```

- `RefreshIndicator(onRefresh: _check)` spins until the returned future completes, so the gesture and the button share one code path.
- `onPressed: _checking ? null : _check` disables the button mid-check; a null `onPressed` is how every Material button is disabled.
- The app bar's `bottom` slot shows a thin `LinearProgressIndicator` only while checking.
- `if (predict)` hides the whole "Expected soon" card when the user turned predictions off in Settings.
- `for (final (day, items) in …fetchRecentUpdates())` destructures each record into a section label and its rows.

The prediction card maps confidence 0, 1, 2 to outline, tertiary and primary dots. Both widgets are `ConsumerWidget`s that look works up with `workProvider`:

```dart
class _ExpectedSoon extends ConsumerWidget {
  const _ExpectedSoon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final works = ref.watch(worksRepositoryProvider);
    final dots = [c.outline, c.tertiary, c.primary];
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: c.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.event_upcoming_rounded, size: 18, color: c.primary),
                const SizedBox(width: 8),
                Text('Expected soon', style: context.text.titleSmall?.copyWith(color: c.primary)),
                const Spacer(),
                Text('On-device estimate', style: context.text.labelSmall?.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 4),
            for (final e in ref.watch(updatesRepositoryProvider).fetchExpectedUpdates())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: dots[e.confidence], shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(works.fetchWork(e.workId).title, style: context.text.bodyLarge),
                          Text(e.why, style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Text(e.when, style: context.text.labelLarge),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UpdateRow extends ConsumerWidget {
  const _UpdateRow(this.u);
  final UpdateItem u;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(workProvider(u.workId));
    final c = context.colors;
    return ListTile(
      leading: MiniCover(w),
      title: Text(
        w.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: u.read ? c.outline : null),
      ),
      subtitle: Text(u.chapter, style: TextStyle(color: u.read ? c.outline : c.onSurfaceVariant)),
      trailing: u.downloaded
          ? Icon(Symbols.offline_pin_rounded, fill: 1, color: context.noctua.success, semanticLabel: 'Downloaded')
          : IconButton(
              tooltip: 'Download chapter',
              icon: const Icon(Symbols.download_rounded),
              onPressed: () => showPlaceholder(context, 'Queued ${u.chapter}'),
            ),
      onTap: () => openInReader(context, ref, w.id, chapter: w.chapters),
    );
  }
}
```

Tapping a new chapter opens the reader at the work's latest chapter through `openInReader`, so it also becomes a tab.

**Step 3: History's weekly card.** A bar chart doesn't need a chart package when it's seven bars: a `Row` of `Container`s whose heights are proportional to minutes read.

```dart
class _WeekCard extends ConsumerWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final week = ref.watch(historyRepositoryProvider).fetchWeek();
    const maxMin = 80;
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: c.surfaceContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.router.push(const StatsRoute()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('This week', style: context.text.titleSmall?.copyWith(color: c.primary)),
                  const Spacer(),
                  Text('Statistics', style: context.text.labelLarge?.copyWith(color: c.primary)),
                  Icon(Symbols.chevron_right_rounded, color: c.primary),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        for (final (v, l) in const [('4h 12m', 'read'), ('38k', 'words'), ('14', 'chapters')])
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: v, style: context.text.titleMedium),
                                TextSpan(
                                  text: ' $l',
                                  style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Tiny bar chart: minutes read per day.
                  SizedBox(
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, (day, m)) in week.indexed)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  width: 8,
                                  height: (m / maxMin * 30).clamp(3, 30).toDouble(),
                                  decoration: BoxDecoration(
                                    color: i == week.length - 1 ? c.primary : c.outlineVariant,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(day, style: context.text.labelSmall?.copyWith(fontSize: 9)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- `crossAxisAlignment: CrossAxisAlignment.end` lines the bars up along the bottom.
- `(m / maxMin * 30).clamp(3, 30)` scales minutes to at most 30 px, with a 3 px minimum so a zero-minute day is still visible as a stub.
- Today (index 6) uses the primary color, the rest `outlineVariant`.
- The whole card is an `InkWell` that pushes `StatsRoute`, a fuller statistics page built the same way.

The rest of the History page is a search field and recent chapters grouped by day, each row reopening the reader at that chapter.

**Step 4: Browse.** A `SearchBar` in the app bar's title slot and three tabs. `BrowsePage` itself is stateless; each tab manages its own state:

```dart
/// Browse: Sources · Extensions · Migrate, under one search bar.
@RoutePage()
class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: SearchBar(
          hintText: 'Search works or paste a link',
          leading: const Icon(Symbols.search_rounded),
          elevation: const WidgetStatePropertyAll(0),
          constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
          onSubmitted: (q) => showPlaceholder(context, 'Searching AO3 for “$q”'),
        ),
        actions: const [TabCountButton()],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Sources'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Extensions'),
                  SizedBox(width: 6),
                  Badge(label: Text('1')),
                ],
              ),
            ),
            Tab(text: 'Migrate'),
          ],
        ),
      ),
      body: const TabBarView(children: [_SourcesTab(), _ExtensionsTab(), _MigrateTab()]),
    ),
  );
}
```

`SearchBar` is Material 3's pill-shaped search field. `elevation: WidgetStatePropertyAll(0)` flattens it into the app bar; the `constraints` stop it growing taller than the toolbar.

The Sources tab watches the three sign-in preferences to show a signed-in dot per source, and keeps the pinned set in local state. Mapping a `Source` to its preference is a domain rule, so the sign-in list, the login page and the Sources tab agree:

```dart
import 'package:noctua/src/features/work/domain/work.dart';
import 'package:noctua/src/preferences/pref.dart';

Source sourceById(String id) => Source.values.firstWhere((s) => s.name == id, orElse: () => Source.ao3);

Pref<bool> signInPrefFor(Source s) => switch (s) {
  Source.ao3 => Prefs.signedInAo3,
  Source.sb => Prefs.signedInSb,
  Source.ffn => Prefs.signedInFfn,
};
```

`sourceById` turns a route parameter (`'ao3'`) back into the enum, with a safe fallback for unknown values.

**Step 5: the sign-in stand-in.** The real login will be a WebView, which can sit behind Cloudflare's "checking your browser" page. The stand-in shows that state for 1.4 s, then a username and password form:

```dart
class _SourceLoginPageState extends ConsumerState<SourceLoginPage> {
  bool _cloudflare = true;
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _cloudflare = false);
    });
  }

  @override
```

`Future.delayed(..., () { if (mounted) setState(...); })` is the one-shot version of the timer pattern: check `mounted` because the page may close first. On "Sign in", the page sets `signInPrefFor(source)` to true and pops.

**Step 6: muted tags as JSON preferences.** The preference store only holds strings, so lists are stored as JSON text. Decoding never throws into the UI:

```dart
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:noctua/src/common_widgets/settings_widgets.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:noctua/src/theme/palettes.dart';

@RoutePage()
class MutedTagsPage extends ConsumerWidget {
  const MutedTagsPage({super.key});

  static List<String> _list(String raw) {
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } on Object {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget group(Pref<String> pref, String title, String hint) {
      final items = _list(ref.pref(pref));
      void save(List<String> v) => ref.setPref(pref, jsonEncode(v));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsHeader(title),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in items) InputChip(label: Text(t), onDeleted: () => save([...items]..remove(t))),
                ActionChip(
                  avatar: const Icon(Symbols.add_rounded, size: 18),
                  label: const Text('Add'),
                  onPressed: () async {
                    final controller = TextEditingController();
                    final v = await showDialog<String>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: Text('Mute a ${hint.toLowerCase()}'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(hintText: hint),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(d, controller.text.trim()), child: const Text('Mute')),
                        ],
                      ),
                    );
                    controller.dispose();
                    if (v != null && v.isNotEmpty && !items.contains(v)) save([...items, v]);
                  },
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SettingsScaffold(
      title: 'Muted',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Works matching anything here are left out of Browse, search and Updates. Your library is never filtered.',
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
        const PrefChoice(Prefs.mutedMode, 'Muted works', ['hide', 'collapse'], labels: {'hide': 'Hide', 'collapse': 'Show collapsed'}),
        group(Prefs.mutedTags, 'Tags', 'Tag'),
        group(Prefs.mutedFandoms, 'Fandoms', 'Fandom'),
        group(Prefs.mutedAuthors, 'Authors', 'Author'),
        group(Prefs.mutedWarnings, 'Archive warnings', 'Warning'),
        const SizedBox(height: 24),
      ],
    );
  }
}
```

- `_list` falls back to an empty list if the stored text is corrupt.
- `save([...items]..remove(t))` copies the list, removes one item and stores the new JSON; `setPref` then notifies every widget watching that preference.
- The dialog's `TextEditingController` is created per dialog and disposed after `await showDialog` returns.
- `SettingsScaffold`, `SettingsHeader` and `PrefChoice` are [[Milestone 10 - Settings|milestone 10]]'s shared settings widgets; build them now if you're following in order, or use a plain `Scaffold` and `ListTile`s until then.

**Step 7: the download queue.** Grouped rows from a list of records, nested two deep: each work has a list of `(chapter, state, progress)` records.

```dart
class _DownloadQueuePageState extends ConsumerState<DownloadQueuePage> {
  bool _paused = false;

  static const _queue = [
    ('salt', [('Ch 40 · The Drowned Bell', 'active', 0.64)]),
    ('iron', [('Interlude 4.3', 'waiting', 0.2), ('Chapter 4.4', 'queued', 0.0)]),
    ('halvard', [('Ch 9 · Seed Day', 'active', 0.12), ('Ch 10 · First Rain', 'queued', 0.0)]),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download queue'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (v) => showPlaceholder(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'Cleared queue', child: Text('Clear queue')),
              PopupMenuItem(value: 'Sorted by work', child: Text('Sort by work')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final (id, items) in _queue) ...[
            SectionLabel(ref.watch(workProvider(id)).title, trailing: SourceBadge(ref.watch(workProvider(id)).source)),

            for (final (name, state, pct) in items)
              ListTile(
                leading: const Icon(Symbols.drag_indicator_rounded),
                title: Text(name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(
                    value: state == 'queued' ? 0 : pct,
                    color: state == 'waiting' ? c.tertiary : null,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                trailing: Text(
                  _paused
                      ? 'Paused'
                      : switch (state) {
                          'active' => '${(pct * 100).round()}%',
                          'waiting' => 'Waiting',
                          _ => 'Queued',
                        },
                  style: context.text.labelMedium?.copyWith(color: state == 'waiting' ? c.tertiary : c.onSurfaceVariant),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'SpaceBattles is rate limited; it resumes in about 40 s. Other sources keep going.',
              style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _paused = !_paused),
        icon: Icon(_paused ? Symbols.play_arrow_rounded : Symbols.pause_rounded),
        label: Text(_paused ? 'Resume' : 'Pause'),
      ),
    );
  }
}
```

`for (final (id, items) in _queue) ...[ ... ]` spreads a header and its rows into the list in one loop. The trailing text is a `switch` expression on the state string, overridden by "Paused" when the queue is paused.

**Step 8: deep search.** One text field searches works (title, author, tag, fandom) and passages inside downloaded chapters, and highlights the match:

```dart
/// Search across titles, tags and the text of downloaded chapters.
@RoutePage()
class DeepSearchPage extends ConsumerStatefulWidget {
  const DeepSearchPage({super.key});

  @override
  ConsumerState<DeepSearchPage> createState() => _DeepSearchPageState();
}

class _DeepSearchPageState extends ConsumerState<DeepSearchPage> {
  final _q = TextEditingController();
  String _scope = 'Everything';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final c = context.colors;
    final works = q.isEmpty || _scope == 'Chapter text'
        ? const <Work>[]
        : ref.watch(worksRepositoryProvider).fetchLibraryWorks().where((w) => w.matchesQuery(q)).toList();
    final passages = q.isEmpty || _scope == 'Titles and tags'
        ? const <(String, int, String)>[]
        : ref
              .read(chaptersRepositoryProvider)
              .searchDownloaded(ref.watch(worksRepositoryProvider).fetchLibraryWorks(), q)
              .take(12)
              .toList();

    Widget highlighted(String text) {
      final i = text.toLowerCase().indexOf(q);
      if (i < 0) return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis);
      final start = (i - 60).clamp(0, text.length);
      final snippet = '${start > 0 ? '…' : ''}${text.substring(start)}';
      final j = snippet.toLowerCase().indexOf(q);
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: snippet.substring(0, j)),
            TextSpan(
              text: snippet.substring(j, j + q.length),
              style: TextStyle(backgroundColor: c.primaryContainer, color: c.onPrimaryContainer),
            ),
            TextSpan(text: snippet.substring(j + q.length)),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Scaffold(
```

- Works match through `Work.matchesQuery` (domain) and passages through `ChaptersRepository.searchDownloaded` (data), so the page only lays out results.
- `onChanged: (_) => setState(() {})` re-runs the search on every keystroke; with a few hundred works that is instant. For a large library, move the search into a provider with a debounce.
- Passages are records `(workId, paragraph, text)`, capped at 12 with `.take(12)`.
- `highlighted` cuts the paragraph to start 60 characters before the match, then splits it into three `TextSpan`s: before, the match with a `primaryContainer` background, and after. `indexOf` is run on the lowercased text so the search is case-insensitive while the display keeps the original case.

**Step 9: routes.** Register the new pages (Stats, ExtensionRepos, SourceSettings, SourceSignIns, SourceLogin, Import, MutedTags, DownloadQueue, DownloadSettings, DeepSearch), point the library's search button at `DeepSearchRoute`, and replace [[Milestone 05 - Theming and the app shell|milestone 5]]'s placeholder tab pages with the real ones.

> [!success] Checkpoint
> all five tabs have content. Browse › Extensions › Manage opens the repository list, and the library search finds “lighthouse” in chapter text.

![[noctua-m09-tabs.png]]
*Milestone 9: Updates, Browse and History*

---
← [[Milestone 08 - The reader and open works]] · [[00 Index|Index]] · [[Milestone 10 - Settings]] →
