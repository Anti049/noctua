---
title: "Milestone 1: Project setup and the folder structure"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 1
aliases:
  - Milestone 1
updated: 2026-11-06
---
# Milestone 1: Project setup and the folder structure

By the end of this milestone you have an empty Flutter app with every dependency installed, code generation working, and the folder structure every later milestone fills in.

1. Create the project, Android only for now:

   ```bash
   flutter create --org dev.noctua --platforms android noctua
   cd noctua
   ```
2. Replace the dependencies in `pubspec.yaml`:

   ```yaml
   environment:
     sdk: ^3.9.0
   
   dependencies:
     flutter:
       sdk: flutter
   
     # State (with code generation) and navigation
     flutter_riverpod: ^3.0.0
     riverpod_annotation: ^4.0.2
     auto_route: ^10.1.0
   
     # Data: immutable models, local database, networking
     freezed_annotation: ^3.1.0
     drift: ^2.28.0
     drift_flutter: ^0.2.6
     dio: ^5.11.1
     flutter_secure_storage: ^11.2.0
   
     # Look and layout
     flex_color_scheme: ^8.3.0
     dynamic_color: ^2.1.0
     material_color_utilities: any # the version Flutter pins
     responsive_framework: ^1.5.1
     google_fonts: ^6.3.0
     material_symbols_icons: ^4.2815.0
     flutter_native_splash: ^2.4.8
   
     # In-app updates and platform info ([[Milestone 03 - In-app updates|milestone 3]])
     ota_update: ^7.1.0
     package_info_plus: ^10.2.2
     device_info_plus: ^13.3.0
   
     image_picker: ^1.1.2
     url_launcher: ^6.3.1
   
   dev_dependencies:
     flutter_test:
       sdk: flutter
     flutter_lints: ^6.0.0
   
     # Code generation
     build_runner: ^2.5.4
     riverpod_generator: ^4.0.3
     freezed: ^3.2.5
     auto_route_generator: ^10.1.0
     drift_dev: ^2.28.0
   
     # App identity ([[Milestone 02 - Release pipeline for beta and stable|milestone 2]])
     flutter_flavorizr: ^2.6.0
     flutter_launcher_icons: ^0.14.4
   ```
3. Set the lints in `analysis_options.yaml`. The last two keep imports consistent across a deep feature tree:

   ```yaml
   include: package:flutter_lints/flutter.yaml
   formatter:
     page_width: 140
   analyzer:
     exclude: ["**/*.g.dart", "**/*.gr.dart", "**/*.freezed.dart", build/**]
   linter:
     rules:
       prefer_const_constructors: true
       prefer_single_quotes: true
       always_use_package_imports: true
       directives_ordering: true
   ```
4. Create the folder skeleton from [[02 Architecture|the Architecture section]]. Shared code sits directly under `lib/src/`; each feature gets the four layer folders, created only when it needs them:

   ```
   lib/
     main.dart                bootstrap: open the database, load state, runApp
     src/
       app.dart               NoctuaApp ([[Milestone 05 - Theming and the app shell|milestone 5]])
       common_widgets/        widgets used by several features
       constants/             app_config.dart, breakpoints.dart
       database/              Drift database ([[Milestone 04 - Preferences and the local database|milestone 4]])
       exceptions/            crash guard ([[Milestone 13 - Errors, tablets and e-ink|milestone 13]])
       networking/            the shared Dio client ([[Milestone 03 - In-app updates|milestone 3]])
       preferences/           Pref<T>, the Prefs registry, PreferencesRepository ([[Milestone 04 - Preferences and the local database|milestone 4]])
       routing/               auto_route router and the home shell ([[Milestone 05 - Theming and the app shell|milestone 5]])
       theme/                 schemes and ThemeData ([[Milestone 05 - Theming and the app shell|milestone 5]])
       utils/                 small extensions, e.g. AsyncValue.showSnackbarOnError
       features/
         <feature>/
           presentation/      screens, widgets/, controllers
           application/       services (only when needed)
           domain/            models and business rules
           data/              repositories (+ fakes)
   test/
     src/                     mirrors lib/src/
   ```
5. Pin the layer rules before writing code ([[02 Architecture|the Architecture section]] explains them): dependencies point down (presentation → application → data → domain), domain imports no Flutter and no I/O, and shared folders never import a feature. `always_use_package_imports` makes every import a full `package:noctua/src/...` path, so a wrong-way import is easy to spot in review.
6. Add the build script you will run after every model, route or table change:

   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

**Code generation conventions.** Every provider and model in the guide is generated, so the same shapes repeat everywhere. A provider is an annotated function (a computed or injected value) or class (state with methods); the generator names it after the function or class, so `libraryWorks` becomes `libraryWorksProvider`. Use `keepAlive: true` for anything that holds app state; leave it off for values computed per screen. The library feature shows all three shapes, one per layer:

```dart
// features/library/domain/library_filter.dart: a Freezed model with its rules
@freezed
abstract class LibraryFilter with _$LibraryFilter {
  const factory LibraryFilter({
    @Default({}) Map<String, TriState> flags,
    @Default(true) bool matchAll,
  }) = _LibraryFilter;
  const LibraryFilter._();                      // lets the class have getters and methods
  int get activeCount => flags.values.where((v) => v != TriState.off).length;
  bool matches(Work work, {bool isOpen = false}) { … }
}

// features/library/presentation/library_controllers.dart: a controller (class provider)
@Riverpod(keepAlive: true)
class LibraryFilterController extends _$LibraryFilterController {  // → libraryFilterControllerProvider
  @override
  LibraryFilter build() => const LibraryFilter();
  void reset() => state = const LibraryFilter();
}

// a computed value (function provider) with an argument
@riverpod
List<Work> libraryWorks(Ref ref, String category) { … }           // → libraryWorksProvider(category)
```

Two naming rules avoid clashes: a provider class can’t share its name with a model or a Drift table (the open-tabs repository is `TabsRepository`; the Drift table is `OpenTabs`), and values `main()` reads before the first frame are providers that throw or return a default, overridden in `ProviderScope`.

## Code walkthrough: milestone 1

This milestone has little app code, but it sets up the two code generators every later file depends on. The examples below are real files from later milestones, picked because they are the smallest of their kind.

**Step 1: tell build_runner about Drift's options.** `build.yaml` sits next to `pubspec.yaml` and configures the generators. Only Drift needs an option: storing `DateTime` columns as ISO-8601 text keeps the database readable in any SQLite browser.

```yaml
targets:
  $default:
    builders:
      drift_dev:
        options:
          store_date_time_values_as_text: true
```

**Step 2: the smallest generated provider.** This one is a presentation-layer controller from [[Milestone 13 - Errors, tablets and e-ink|milestone 13]]: it remembers which work the tablet layout shows beside the library. A provider is a class (or function) with `@riverpod` / `@Riverpod(...)` and a `part` line naming the generated file. The class extends `_$ClassName`, which the generator writes, and overrides `build()` to return the initial state. Methods change `state`, and every widget watching the provider rebuilds.

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tablet_detail_controller.g.dart';

/// Work shown in the details pane on wide screens (null = none picked yet).
@Riverpod(keepAlive: true)
class TabletDetailController extends _$TabletDetailController {
  @override
  String? build() => null;

  void show(String? id) => state = id;
}
```

What you write versus what you get:

- `part 'tablet_detail_controller.g.dart';` must match the file name exactly, or build_runner writes nothing.
- `@Riverpod(keepAlive: true)` keeps the state for the whole session. Plain `@riverpod` disposes it when nothing is listening, which is right for values computed for one screen.
- The generator names the provider after the class with a lower-case first letter plus `Provider`: `TabletDetailController` becomes `tabletDetailControllerProvider`.
- Read it with `ref.watch(tabletDetailControllerProvider)` (rebuilds on change) and call methods with `ref.read(tabletDetailControllerProvider.notifier).show(id)` (no rebuild).

The generated file starts like this. You never edit it, but it helps to know `overrideWithValue` is generated for every provider, because tests and `main()` rely on it:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND
part of 'tablet_detail_controller.dart';

@ProviderFor(TabletDetailController)
final tabletDetailControllerProvider = TabletDetailControllerProvider._();

final class TabletDetailControllerProvider extends $NotifierProvider<TabletDetailController, String?> {
  // …
  Override overrideWithValue(String? value) { … }
}
```

**Step 3: the smallest Freezed model.** Domain models are Freezed classes; this one is from the `tabs` feature ([[Milestone 08 - The reader and open works|milestone 8]]). A Freezed class is `abstract`, mixes in `_$Name`, and declares a `const factory` constructor that redirects to `_Name`. Fields come from the constructor parameters; `@Default` gives a parameter a default value so it can be left out.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'tab_entry.freezed.dart';

/// One open work, like a browser tab.
@freezed
abstract class TabEntry with _$TabEntry {
  const factory TabEntry({required String workId, @Default(1) int chapter, @Default(0) double progress}) = _TabEntry;
}
```

Freezed generates `==` and `hashCode` (two `TabEntry`s with the same values are equal, so Riverpod skips rebuilds when nothing changed), a readable `toString`, and `copyWith`:

```dart
const a = TabEntry(workId: 'w1');          // chapter 1, progress 0
final b = a.copyWith(chapter: 4);          // TabEntry(workId: w1, chapter: 4, progress: 0.0)
assert(a != b && b == const TabEntry(workId: 'w1', chapter: 4));
```

Two rules to remember for the rest of the guide:

- A model that needs getters or methods also declares a private constructor, `const Name._();`. Without it, Freezed refuses to generate.
- `copyWith(field: null)` sets a nullable field to null. When an argument may be null and should mean "keep the old value", write `copyWith(field: field ?? old.field)`.

**Step 4: run the generators.** Run this once after `pub get`, and again after changing any `@riverpod`, `@freezed`, `@RoutePage`, `@AutoRouterConfig` or Drift table:

```bash
dart run build_runner build --delete-conflicting-outputs
# or keep it running while you work:
dart run build_runner watch --delete-conflicting-outputs
```

`--delete-conflicting-outputs` lets it replace stale generated files instead of stopping. If a build fails with "Could not generate", the message names the source file; most often the cause is a missing `part` line or a typo in the `_$Name` mixin.

**Step 5: the `.gitignore` additions.** Generated files are rebuilt in CI, so they stay out of git:

```gitignore
*.g.dart
*.gr.dart
*.freezed.dart
android/key.properties
*.jks
```

> [!success] Checkpoint
> `flutter analyze` reports no issues and `flutter run` shows the counter app. There is nothing Noctua-specific to screenshot yet.

The features this guide builds, and where each one lives:

| Feature | Owns | Milestone |
| --- | --- | --- |
| `app_update` | Releases repository, installer, update service and controller, update and changelog screens | 3 |
| `settings` | Settings hub, search and app-wide settings screens | 10 |
| `work` | Work, Chapter, Series models; works repository; covers; work details, series, author, content warning, cover settings | 6–7 |
| `library` | Library repository and categories, filter rules, library screen and controllers, selection, deep search, library settings | 6 |
| `reader` | Chapters and highlights repositories, reader, settings sheet, chapters, read aloud, author’s notes, save prompt | 8 |
| `tabs` | Tabs repository (open works, saved in Drift), switcher, tab-count button | 8 |
| `updates`, `history` | Their repositories; updates and expected updates; history and stats | 9 |
| `browse`, `downloads` | Extensions repository, sources, import, source sign-in, muted tags; download queue | 9 |
| `custom_theme`, `ai`, `archive` | Theme editor, AI options, community archive | 10 |
| `auth` | Auth and session repositories, auth service, sign-in and account controllers and screens | 11 |
| `onboarding` | First-run setup, tour, coach marks | 12 |
| `errors`, `more` | Crash and report screens; More tab | 13 |

---
← [[02 Architecture]] · [[00 Index|Index]] · [[Milestone 02 - Release pipeline for beta and stable]] →
