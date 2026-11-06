---
title: "Milestone 10: Settings"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 10
aliases:
  - Milestone 10
updated: 2026-11-06
---
# Milestone 10: Settings

Settings is a hub that links to pages owned by the features they configure. Only app-wide pages live in the `settings` feature itself, and it is presentation only: every value it shows is a preference from [[Milestone 04 - Preferences and the local database|milestone 4]].

1. **Shared tiles in `lib/src/common_widgets/settings_widgets.dart`:** `SettingsScaffold`, `SettingsHeader`, `PrefSwitch`, `PrefChoice`, `PrefSlider`, `PrefValue`, `NavRow` and a `confirm` dialog. Each `Pref*` tile takes a `Pref<T>` and binds itself, so most settings pages are a list of one-liners:

   ```dart
   const PrefChoice(Prefs.coverStyle, 'Style', ['Solid', 'Gradient', 'Pattern', 'Typographic']),
   const PrefSwitch(Prefs.coverShowAuthor, 'Author'),
   ```
2. **`settings/presentation/settings_page.dart`:** the hub (13 sections) and Settings search. Search runs over an index of every setting with keywords, so “wifi” finds both update checks and downloads.
3. **Pages owned by `settings`:** Appearance (theme cards for Catppuccin, Dynamic, the 13 Mihon themes, E-ink and Custom; dark mode; pure black), Data and storage, Restore from backup, Privacy and security, Advanced, and About, which now shows the update channel, Check for updates, Check automatically and the Changelog from [[Milestone 03 - In-app updates|milestone 3]].
4. **Pages owned by other features:**

| Page | Feature | Notes |
| --- | --- | --- |
| Library and updates | `library` | Categories, update checks, notifications, unsaved works, muted tags |
| Reader | `reader` | Global reading defaults with a live preview |
| Covers | `work` | Real or generated covers; style, color source, crossover handling, font, what to show |
| Downloads and export | `downloads` | Location, auto-download, EPUB options |
| Source sign-ins | `browse` | Per-source sign-in, request pacing, extension repositories |
| AI and content | `ai` | Hide AI works, warnings, opt-in AI features (off by default) |
| Community archive | `archive` | Contribute read works to a public archive; sources, anonymity, Wi-Fi only |
| Custom theme | `custom_theme` | Seed colors, per-role colors with contrast checks, colors from an image |

5. `WorkCover` now reads the cover preferences, so changing Covers settings updates every cover in the app.

## Code walkthrough: milestone 10

**Step 1: the shared settings widgets.** Every settings page in the app is a list of these. Each `Pref*` widget takes a `Pref<T>`, watches it, and writes it back, so a settings row is one line of code:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:noctua/src/common_widgets/common_widgets.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:noctua/src/theme/palettes.dart';

/// Scaffold for a settings sub-page.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({super.key, required this.title, required this.children, this.actions});
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: ListView(padding: const EdgeInsets.only(bottom: 32), children: children),
  );
}

class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => SectionLabel(title, padding: const EdgeInsets.fromLTRB(16, 24, 16, 4));
}

class PrefSwitch extends ConsumerWidget {
  const PrefSwitch(this.pref, this.title, {super.key, this.subtitle, this.enabled = true});
  final Pref<bool> pref;
  final String title;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: ref.pref(pref),
    onChanged: enabled ? (v) => ref.setPref(pref, v) : null,
  );
}

/// A row of choice chips (single select).
class PrefChoice extends ConsumerWidget {
  const PrefChoice(this.pref, this.title, this.options, {super.key, this.subtitle, this.enabled = true, this.labels});
  final Map<String, String>? labels;
  final Pref<String> pref;
  final String title;
  final List<String> options;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.pref(pref);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.bodyLarge?.copyWith(color: enabled ? null : context.colors.outline)),
          if (subtitle != null) Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                ChoiceChip(label: Text(labels?[o] ?? o), selected: value == o, onSelected: enabled ? (_) => ref.setPref(pref, o) : null),
            ],
          ),
        ],
      ),
    );
  }
}

class PrefSlider extends ConsumerWidget {
  const PrefSlider.integer(Pref<int> this.intPref, this.title, {super.key, required this.min, required this.max, this.format})
    : doublePref = null,
      step = 1;
  const PrefSlider.decimal(
    Pref<double> this.doublePref,
    this.title, {
    super.key,
    required this.min,
    required this.max,
    this.step = 1,
    this.format,
  }) : intPref = null;

  final Pref<int>? intPref;
  final Pref<double>? doublePref;
  final String title;
  final double min;
  final double max;
  final double step;
  final String Function(double)? format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = intPref != null ? ref.pref(intPref!).toDouble() : ref.pref(doublePref!);
    final v = raw.clamp(min, max);
    final label = format?.call(v) ?? (intPref != null ? '${v.round()}' : v.toStringAsFixed(1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: context.text.bodyLarge)),
              Text(label, style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
            ],
          ),
          Slider(
            value: v,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            label: label,
            onChanged: (x) {
              if (intPref != null) {
                ref.setPref(intPref!, x.round());
              } else {
                ref.setPref(doublePref!, x);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// A row showing a current value; tapping cycles through [options] or runs [onTap].
class PrefValue extends ConsumerWidget {
  const PrefValue(this.pref, this.title, {super.key, this.options, this.subtitle});
  final Pref<String> pref;
  final String title;
  final String? subtitle;
  final List<String>? options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.pref(pref);
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle == null ? value : '$subtitle\n$value'),
      isThreeLine: subtitle != null,
      onTap: () async {
        final opts = options;
        if (opts == null) {
          showPlaceholder(context, 'Pick $title');
          return;
        }
        final picked = await showDialog<String>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: Text(title),
            children: [
              RadioGroup<String>(
                groupValue: value,
                onChanged: (v) => Navigator.pop(dialog, v),
                child: Column(
                  children: [for (final o in opts) RadioListTile<String>(value: o, title: Text(o))],
                ),
              ),
            ],
          ),
        );
        if (picked != null) ref.setPref(pref, picked);
      },
    );
  }
}

class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.title, this.subtitle, this.icon, this.onTap, this.danger = false});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? context.colors.error : null;
    return ListTile(
      leading: icon == null ? null : Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: danger ? null : const Icon(Symbols.chevron_right_rounded),
      onTap: onTap ?? () => showPlaceholder(context, title),
    );
  }
}

/// Confirm dialog for destructive rows.
Future<bool> confirm(BuildContext context, String title, String body, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(action)),
        ],
      ),
    ) ??
    false;
```

- `SettingsScaffold` is a `Scaffold` with a title and a `ListView` of children, so every settings page has the same padding and scroll behavior.
- `PrefChoice` shows the current value as its subtitle and opens a radio dialog. `labels` maps stored values to display text, so the store can keep stable ids (`'grid'`) while the UI says "Cover grid".
- `PrefSlider` has two named constructors, `.integer` for `Pref<int>` and `.decimal` for `Pref<double>`; each sets the other preference field to null, so one widget serves both.
- `confirm` returns `Future<bool>`: `?? false` covers dismissing the dialog without choosing.

**Step 2: the hub.** The 13 sections are data, as a list of records, so the hub page is a single loop:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:noctua/src/routing/app_router.gr.dart';
import 'package:noctua/src/theme/palettes.dart';

typedef _Section = (IconData icon, String title, String subtitle, PageRouteInfo route);

const List<_Section> _sections = [
  (Symbols.account_circle_rounded, 'Account and sync', 'Sign-in, what syncs, server', AccountRoute()),
  (Symbols.palette_rounded, 'Appearance', 'Theme, dark mode, library display', AppearanceSettingsRoute()),
  (Symbols.collections_bookmark_rounded, 'Library and updates', 'Categories, update checks, unsaved works', LibrarySettingsRoute()),
  (Symbols.imagesmode_rounded, 'Covers', 'Generated cover style and details', CoverSettingsRoute()),
  (Symbols.menu_book_rounded, 'Reader', 'Text, page mode, navigation', ReaderPrefsRoute()),
  (Symbols.download_rounded, 'Downloads and export', 'Storage, auto-download, EPUB', DownloadSettingsRoute()),
  (Symbols.key_rounded, 'Source sign-ins', 'AO3, SpaceBattles, FFN · request pacing', AccountsSettingsRoute()),
  (Symbols.edit_note_rounded, 'AI and content', 'AI filtering and warnings, AI features, muted tags', AiSettingsRoute()),
  (Symbols.inventory_2_rounded, 'Community archive', 'Help preserve the works you read', CommunityArchiveRoute()),
  (Symbols.database_rounded, 'Data and storage', 'Backup, restore, cache', DataSettingsRoute()),
  (Symbols.shield_rounded, 'Privacy and security', 'App lock, incognito, hide in recents', PrivacySettingsRoute()),
  (Symbols.code_rounded, 'Advanced', 'Logs, network, developer options', AdvancedSettingsRoute()),
  (Symbols.info_rounded, 'About', 'Version, updates, changelog, licenses', AboutRoute()),
];

@RoutePage()
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Settings'),
      actions: [
        IconButton(
          tooltip: 'Search settings',
          icon: const Icon(Symbols.search_rounded),
          onPressed: () => context.router.push(const SettingsSearchRoute()),
        ),
      ],
    ),
    body: ListView(
      children: [
        for (final (icon, title, sub, route) in _sections)
          ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(sub), onTap: () => context.router.push(route)),
      ],
    ),
  );
```

- The `typedef _Section = (IconData icon, String title, String subtitle, PageRouteInfo route)` names the record's fields for readability; the loop still destructures them positionally.
- Each route is a `const` route object (`AboutRoute()`), so the list itself can be `const`.

**Step 3: settings search.** An index of every setting as records `(section, title, group, keywords)`. The section is an index into `_sections`, so a result can show "Library and updates › Update checks" and open the right page:

```dart
/// Searchable index of every setting: (section, title, group, extra keywords).
const _index = <(int, String, String, String)>[
  (0, 'Sign out', '', 'log out logout account'),
  (0, 'What syncs', 'Sync', 'library progress tabs settings cloud'),
  (0, 'Change password', 'Security', 'account'),
  (0, 'Create account', '', 'guest anonymous link register'),
  (1, 'App theme', '', 'color catppuccin mocha latte'),
  (1, 'Dark mode', '', 'night light system'),
  (1, 'Custom theme', '', 'seed color roles image wallpaper material you'),
  (1, 'E-ink display', '', 'eink e-reader kindle kobo boox refresh'),
```

```dart
  // …one row per setting, about 60 in all…
];
```

```dart
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final _controller = TextEditingController();
  String get _q => _controller.text;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  @override
  Widget build(BuildContext context) {
    final words = _q.toLowerCase().split(RegExp(r'\s+')).map(_norm).where((w) => w.isNotEmpty).toList();
    final results = words.isEmpty
        ? const <(int, String, String, String)>[]
        : _index.where((e) {
            final hay = _norm('${e.$2} ${e.$3} ${e.$4} ${_sections[e.$1].$2}');
            return words.every(hay.contains);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search settings', border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: words.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Try', style: context.text.titleSmall?.copyWith(color: context.colors.primary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in const ['wifi', 'font', 'dark', 'backup', 'lock', 'epub'])
                      ActionChip(label: Text(s), onPressed: () => setState(() => _controller.text = s)),
                  ],
                ),
              ],
            )
          : results.isEmpty
          ? Center(child: Text('No settings match “$_q”', style: context.text.bodyLarge))
          : ListView(
              children: [
                for (final (section, title, group, _) in results)
                  ListTile(
                    leading: Icon(_sections[section].$1),
                    title: Text(title),
                    subtitle: Text([_sections[section].$2, if (group.isNotEmpty) group].join(' › ')),
                    onTap: () => context.router.push(_sections[section].$4),
                  ),
              ],
            ),
    );
  }
}
```

- `_norm` lowercases and strips everything but letters and digits, so "Wi-Fi", "wifi" and "WiFi" all match.
- The query is split into words and every word must appear (`words.every(hay.contains)`), so "dark mode" matches "Dark mode" but "dark backup" matches nothing.
- `hay` includes the section title, so typing a section name lists all its settings.
- Record fields can also be read by position: `e.$2` is the title. That's used inside the `where`, where destructuring would be clumsier.

Keep the index in sync when you add a setting; a test that every `Prefs` key appears in the index (or is marked internal) catches forgotten ones.

**Step 4: Appearance.** Theme cards for every built-in theme, the dark-mode switch and library display:

```dart
@RoutePage()
class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.pref(Prefs.appTheme);
    final dark = ref.pref(Prefs.darkMode);
    final systemDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final showDark = dark == 'dark' || (dark == 'system' && systemDark);
    final custom = schemeFromSeeds(
      brightness: showDark ? Brightness.dark : Brightness.light,
      primary: Color(ref.pref(Prefs.customPrimary)),
    );

    final dynamic = ref.watch(dynamicSchemesProvider);
    ColorScheme pick((ColorScheme, ColorScheme) pair) => showDark ? pair.$2 : pair.$1;
    final cards = [
      ('catppuccin', 'Catppuccin', showDark ? mochaScheme : latteScheme),
      if (dynamic != null) ('dynamic', 'Dynamic', pick(dynamic)),
      for (final t in mihonThemes) (t.id, t.label, showDark ? t.dark : t.light),
      ('eink', 'E-ink', einkScheme),
      ('custom', 'Custom', custom),
    ];

    return SettingsScaffold(
      title: 'Appearance',
      children: [
        const SettingsHeader('Theme'),
        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final (id, label, scheme) in cards)
                _ThemeCard(label: label, scheme: scheme, selected: theme == id, onTap: () => ref.setPref(Prefs.appTheme, id)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Symbols.brightness_auto_rounded)),
              ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Symbols.dark_mode_rounded)),
              ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Symbols.light_mode_rounded)),
            ],
            selected: {dark},
            onSelectionChanged: theme == 'eink' ? null : (s) => ref.setPref(Prefs.darkMode, s.first),
          ),
        ),
        if (theme == 'eink')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'E-ink is always light, for contrast on e-paper.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        if (theme != 'eink')
          const PrefSwitch(Prefs.pureBlack, 'Pure black dark mode', subtitle: 'Black background in dark mode, for OLED screens'),
        NavRow(
          icon: Symbols.format_paint_rounded,
          title: 'Custom theme',
          subtitle: 'From seed colors, color roles or an image',
          onTap: () => context.router.push(const CustomThemeRoute()),
        ),
        NavRow(
          icon: Symbols.chrome_reader_mode_rounded,
          title: 'E-ink display',
          subtitle: 'Refresh, contrast, page buttons — for e-readers',
          onTap: () => context.router.push(const EinkSettingsRoute()),
        ),
        const SettingsHeader('Library display'),
        const PrefChoice(
          Prefs.libraryLayout,
          'Layout',
          ['grid', 'list', 'widgets'],
          labels: {'grid': 'Cover grid', 'list': 'Compact list', 'widgets': 'Widgets'},
        ),
        const PrefSlider.integer(Prefs.gridColumns, 'Grid columns', min: 2, max: 5),
        const PrefSwitch(Prefs.showUnreadBadge, 'Unread badges'),
        const PrefSwitch(Prefs.showDownloadedBadge, 'Downloaded badges'),
        const PrefValue(Prefs.dateFormat, 'Date format', options: ['Relative (3 days ago)', 'Short (Mar 2)', 'ISO (2026-03-02)']),
      ],
    );
  }
```

- The cards preview the scheme for the brightness the user will actually see: the explicit setting, or the system's (`MediaQuery.platformBrightnessOf`) when it's "System".
- `if (dynamic != null)` inside the list literal leaves the Dynamic card out on devices without Material You colours.
- `onSelectionChanged: theme == 'eink' ? null : …` disables the dark-mode switch for E-ink, which is always light.
- `PrefSlider.integer(Prefs.gridColumns, …, min: 2, max: 5)` is the "Grid columns" setting [[Milestone 06 - The library|milestone 6]]'s library reads.

Each card draws a miniature screen from the scheme's own colors:

```dart
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.label, required this.scheme, required this.selected, required this.onTap});
  final String label;
  final ColorScheme scheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              width: 88,
              height: 120,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? context.colors.primary : context.colors.outlineVariant, width: selected ? 3 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 10,
                    width: 48,
                    decoration: BoxDecoration(color: s.onSurface, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: s.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: s.primaryContainer, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 10,
                        decoration: BoxDecoration(color: s.primary, borderRadius: BorderRadius.circular(5)),
                      ),
                      const Spacer(),
                      if (selected) Icon(Symbols.check_circle_rounded, size: 16, fill: 1, color: s.primary),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: context.text.labelMedium),
        ],
      ),
    );
  }
}
```

**Step 5: the custom theme.** Three ways to build a theme: seed colors, individual roles, or colors picked from an image. Seeds go through flex_color_scheme's `SeedColorScheme.fromSeeds`, which generates the full Material 3 tonal palette:

```dart
const customVariants = <String, String>{
  'tonalSpot': 'Tonal spot',
  'vibrant': 'Vibrant',
  'expressive': 'Expressive',
  'fidelity': 'Fidelity',
  'content': 'Content',
  'neutral': 'Neutral',
  'monochrome': 'Monochrome',
};

FlexSchemeVariant _variant(String name) =>
    FlexSchemeVariant.values.firstWhere((v) => v.name == name, orElse: () => FlexSchemeVariant.tonalSpot);

/// Generates a full M3 scheme from 1–3 seed colors. Primary is required;
/// secondary/tertiary are derived from primary when not given.
ColorScheme schemeFromSeeds({
  required Brightness brightness,
  required Color primary,
  Color? secondary,
  Color? tertiary,
  String variant = 'tonalSpot',
  double contrast = 0,
}) => SeedColorScheme.fromSeeds(
  brightness: brightness,
  primaryKey: primary,
  secondaryKey: secondary,
  tertiaryKey: tertiary,
  variant: _variant(variant),
  contrastLevel: contrast,
);
```

- `variant` picks how far the palette strays from the seed (Tonal spot is Material You's default; Fidelity keeps the seed color exact; Monochrome drops chroma).
- `contrastLevel` runs from 0 (standard) to 1 (high contrast), Material's accessibility contrast setting.
- Secondary and tertiary are stored as `0` when unset, so `s2 == 0 ? null : Color(s2)` lets the generator derive them from primary.

Role overrides are stored as JSON maps from role name to ARGB, and applied over the generated scheme:

```dart
Map<String, int> decodeRoles(String json) {
  try {
    return (jsonDecode(json) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
  } catch (_) {
    return {};
  }
}

String encodeRoles(Map<String, int> roles) => jsonEncode(roles);

ColorScheme applyRoles(ColorScheme s, Map<String, int> roles) {
  var out = s;
  roles.forEach((role, argb) => out = withRole(out, role, Color(argb)));
  return out;
}

/// WCAG contrast ratio, used to flag weak on-color pairs in the role editor.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
```

`contrastRatio` is the WCAG formula. The roles editor shows it next to every "on" color against its background and marks anything under 4.5:1, so a custom theme can't quietly make text unreadable.

With those, `appThemes` gains its `custom` case:

```dart
    case 'custom':
      final primary = Color(ref.pref(Prefs.customPrimary));
      final s2 = ref.pref(Prefs.customSecondary), s3 = ref.pref(Prefs.customTertiary);
      final variant = ref.pref(Prefs.customVariant);
      final contrast = ref.pref(Prefs.customContrast);
      ColorScheme make(Brightness b, String rolesJson) => applyRoles(
        schemeFromSeeds(
          brightness: b,
          primary: primary,
          secondary: s2 == 0 ? null : Color(s2),
          tertiary: s3 == 0 ? null : Color(s3),
          variant: variant,
          contrast: contrast,
        ),
        decodeRoles(rolesJson),
      );
      return AppThemes(
        buildTheme(make(Brightness.light, ref.pref(Prefs.customRolesLight)), extras: NoctuaColors.latte),
        buildTheme(
          pureBlack
              ? pureBlackOf(make(Brightness.dark, ref.pref(Prefs.customRolesDark)))
              : make(Brightness.dark, ref.pref(Prefs.customRolesDark)),
          extras: NoctuaColors.mocha,
        ),
        mode,
      );
```

`make` is a local function: it builds one brightness from the seeds, then applies that brightness's role overrides. Pure black still applies on top in dark mode.

**Step 6: About.** The update rows from [[Milestone 03 - In-app updates|milestone 3]] move here; they call `AppUpdateController`, and the screen never touches the update repositories. Play builds hide them entirely:

```dart
@RoutePage()
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final app = ref.watch(installedAppProvider);
    final appVersion = '${app.versionName} (${app.versionCode})';
    return SettingsScaffold(
      title: 'About',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              const NoctuaLogo(size: 80),
              const SizedBox(height: 8),
              Text('Noctua', style: context.text.headlineSmall),
              Text(
                'Version $appVersion · ${app.channel.label.toLowerCase()}',
                style: context.text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const UpdateAvailableTile(),
        const SettingsHeader('Updates'),
        if (isPlayStoreBuild)
          const ListTile(leading: Icon(Symbols.shop_rounded), title: Text('Updates come from Google Play'))
        else ...[
          ListTile(
            leading: const Icon(Symbols.alt_route_rounded),
            title: const Text('Update channel'),
            subtitle: Text(
              app.channel == UpdateChannel.beta
                  ? 'Beta: gets every beta and stable release. This is the Noctua Beta app.'
                  : 'Stable: gets stable releases only. Install Noctua Beta alongside to test early builds.',
            ),
          ),
          NavRow(
            icon: Symbols.system_update_rounded,
            title: 'Check for updates',
            subtitle: 'From GitHub Releases',
            onTap: () => context.router.push(const AppUpdateRoute()),
          ),
          const PrefSwitch(Prefs.autoCheckAppUpdates, 'Check automatically', subtitle: 'When the app opens, at most once a day'),
        ],
        NavRow(icon: Symbols.history_edu_rounded, title: 'Changelog', onTap: () => context.router.push(const ChangelogRoute())),
        const SettingsHeader('Help'),
        NavRow(
          icon: Symbols.tour_rounded,
          title: 'Feature tour',
          subtitle: 'The six-page intro from first launch',
          onTap: () => replayTour(context, ref),
        ),
        NavRow(
          icon: Symbols.feedback_rounded,
          title: 'Report a problem or suggest a feature',
          subtitle: 'Bug, idea or source problem · via GitHub',
          onTap: () => context.router.push(const FeedbackRoute()),
        ),
        NavRow(
          icon: Symbols.description_rounded,
          title: 'Open-source licenses',
          onTap: () => showLicensePage(context: context, applicationName: 'Noctua', applicationVersion: appVersion),
        ),
      ],
    );
  }
```

- The update channel is read-only text: it comes from which app is installed, not a setting.
- `UpdateAvailableTile` ([[Milestone 03 - In-app updates|milestone 3]]) shows only when the last check found an update.
- `showLicensePage` is Flutter's built-in licences screen, filled automatically from every package's `LICENSE`.

**Step 7: pages owned by features.** Each feature owns its settings page, built from the same widgets. Covers, for example, previews three real covers at the top so every change is visible immediately:

```dart
@RoutePage()
class CoverSettingsPage extends ConsumerWidget {
  const CoverSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final samples = [
      for (final id in const ['salt', 'convergence', 'iron']) ref.watch(workProvider(id)),
    ];
    return SettingsScaffold(
      title: 'Covers',
      children: [
        SizedBox(
          height: 190,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final w in samples)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(width: 116, child: WorkCover(work: w)),
                ),
            ],
          ),
        ),
        const PrefSwitch(
          Prefs.coverUseReal,
          'Use the work’s own cover when it has one',
          subtitle: 'Cover art from the source or an imported EPUB. Generated covers fill the gaps.',
        ),
        const SettingsHeader('Generated covers'),
        const PrefChoice(Prefs.coverStyle, 'Style', ['Solid', 'Gradient', 'Pattern', 'Typographic']),
        const PrefChoice(Prefs.coverColorFrom, 'Color from', [
          'Fandom',
          'Author',
          'Title',
          'Theme accent',
        ], subtitle: 'Works from the same fandom share a color by default'),
        const PrefChoice(Prefs.coverCrossover, 'Crossovers', ['Split', 'First fandom', 'Stripes']),
        const PrefValue(Prefs.coverFont, 'Title font', options: ['Literata', 'Inter', 'Playfair Display', 'JetBrains Mono']),
        const SettingsHeader('Show on the cover'),
        const PrefSwitch(Prefs.coverShowTitle, 'Title'),
        const PrefSwitch(Prefs.coverShowSource, 'Source badge'),
        const PrefSwitch(Prefs.coverShowFandom, 'Fandom'),
        const PrefSwitch(Prefs.coverShowAuthor, 'Author'),
        const PrefSwitch(Prefs.coverShowRating, 'Rating'),
        const PrefSwitch(Prefs.coverShowWords, 'Word count'),
        NavRow(
          title: 'Reset cover settings',
          icon: Symbols.restart_alt_rounded,
          onTap: () => ref.read(preferencesRepositoryProvider.notifier).reset(const [
            Prefs.coverUseReal,
            Prefs.coverStyle,
            Prefs.coverColorFrom,
            Prefs.coverCrossover,
            Prefs.coverFont,
            Prefs.coverShowTitle,
            Prefs.coverShowSource,
            Prefs.coverShowFandom,
            Prefs.coverShowAuthor,
            Prefs.coverShowRating,
            Prefs.coverShowWords,
          ]),
        ),
      ],
    );
  }
```

`reset(const [...])` deletes just these keys, so they fall back to their defaults without touching any other setting. Because `WorkCover` watches the same preferences ([[Milestone 06 - The library|milestone 6]], step 3), the library grid updates as well; that is the checkpoint for this milestone.

**Step 8: routes.** Register every settings page. The hub's list is the checklist: each record's route must exist in the router, or build_runner's output won't contain it and the `const` list won't compile.

> [!success] Checkpoint
> every row in Settings opens a working page. Change Covers › Style to Gradient and the library covers change immediately.

![[noctua-m10-settings.png]]
*Milestone 10: Settings hub, Covers and AI and content*

---
← [[Milestone 09 - Updates, History, Browse and sources]] · [[00 Index|Index]] · [[Milestone 11 - Accounts and sync]] →
