---
title: "Milestone 4: Preferences and the local database"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 4
aliases:
  - Milestone 4
updated: 2026-11-06
---
# Milestone 4: Preferences and the local database

Every setting in Noctua is a typed preference stored in Drift and read before the first frame, so the app never flashes the wrong theme or layout. This milestone builds that store before anything that needs it: the theme in [[Milestone 05 - Theming and the app shell|milestone 5]] and every screen after read their settings from here. It also finishes the updater, whose launch check needs two preferences.

1. **`lib/src/database/app_database.dart`** (shared): two Drift tables. `preferences` is a key/value table (adding a setting never needs a migration); `open_tabs` holds the open works with chapter, progress and position, used from [[Milestone 08 - The reader and open works|milestone 8]]. Defining both now keeps the schema at version 1. `AppDatabase` takes an optional `QueryExecutor` so tests can pass `NativeDatabase.memory()`, and `appDatabaseProvider` throws until `main()` overrides it.

   ```dart
   class Preferences extends Table {
     TextColumn get key => text()();
     TextColumn get value => text()();
     @override
     Set<Column> get primaryKey => {key};
   }
   
   @DriftDatabase(tables: [Preferences, OpenTabs])
   class AppDatabase extends _$AppDatabase {
     AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'noctua'));
     @override
     int get schemaVersion => 1;
   }
   ```
2. **`lib/src/preferences/pref.dart`** (shared): a `Pref<T>(key, defaultValue)` class that encodes and decodes `bool`, `int`, `double` and `String`, and the `Prefs` registry of every key. It is plain Dart, so any layer can name a preference. Preferences sit with the database in shared code rather than in a feature, because the theme (shared) and nearly every feature read them.
3. **`lib/src/preferences/preferences_repository.dart`** (shared, data): `PreferencesRepository`, a repository with a cache. Its state is every setting as stored text; `set` updates the state and writes through to Drift. Extensions let widgets write `ref.pref(Prefs.gridColumns)` to watch one value and `ref.setPref(...)` to change it; `ref.readPref` reads once inside callbacks.

   ```dart
   @Riverpod(keepAlive: true)
   class PreferencesRepository extends _$PreferencesRepository {
     @override
     Map<String, String> build() => Map.of(ref.read(initialPrefsProvider));
   
     T get<T>(Pref<T> p) => p.decode(state[p.key]);
     Future<void> set<T>(Pref<T> p, T value) async { /* update state, write to Drift */ }
   }
   
   extension PrefWidgetRef on WidgetRef {
     T pref<T>(Pref<T> p) => watch(preferencesRepositoryProvider.select((m) => p.decode(m[p.key])));
     void setPref<T>(Pref<T> p, T value) => read(preferencesRepositoryProvider.notifier).set(p, value);
     T readPref<T>(Pref<T> p) => p.decode(read(preferencesRepositoryProvider)[p.key]);
   }
   ```
4. Keep every key in the one `Prefs` registry. It is the one deliberate exception to feature ownership: “Reset all settings”, settings search and sync need to see every key, and stable key strings are what get migrated. Later milestones add their keys to it.
5. **`main.dart`**: open the database, `await db.loadPreferences()`, and start the app with `appDatabaseProvider` and `initialPrefsProvider` overridden. The same overrides are how tests swap in an in-memory database.
6. **Finish the updater** (`app_update/application/app_update_service.dart`): add `Prefs.autoCheckAppUpdates` (default on) and `Prefs.lastUpdateCheck` (epoch milliseconds) to the registry; `check()` records the time, and `isCheckDue()` is false when automatic checks are off or the last check was under 20 hours ago. GitHub allows 60 unauthenticated API requests an hour per IP, so a daily check leaves plenty of room. The service now spans three repositories, which is the case the application layer exists for.
7. Run build\_runner to generate `app_database.g.dart` and the providers.

## Code walkthrough: milestone 4

**Step 1: the Drift tables.** A Drift table is a class extending `Table` whose getters describe columns; the trailing `()()` is Drift's builder syntax (the first call configures, the second builds). The database class lists its tables in `@DriftDatabase` and extends the generated `_$AppDatabase`:

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_database.g.dart';

/// Every app and reader preference, stored as text and decoded by [Pref].
/// A key/value table keeps schema migrations away from day-to-day setting changes.
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Works open as Firefox-style tabs, so they survive a restart or a crash.
class OpenTabs extends Table {
  TextColumn get workId => text()();
  IntColumn get chapter => integer().withDefault(const Constant(1))();
  RealColumn get progress => real().withDefault(const Constant(0))();
  IntColumn get position => integer()();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {workId};
}

@DriftDatabase(tables: [Preferences, OpenTabs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'noctua'));

  @override
  int get schemaVersion => 1;

  // Preferences

  Future<Map<String, String>> loadPreferences() async {
    final rows = await select(preferences).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> putPreference(String key, String value) =>
      into(preferences).insertOnConflictUpdate(PreferencesCompanion.insert(key: key, value: value));

  Future<void> deletePreferences(Iterable<String> keys) => (delete(preferences)..where((p) => p.key.isIn(keys.toList()))).go();

  Future<void> clearPreferences() => delete(preferences).go();

  // Open tabs

  Future<List<OpenTab>> loadTabs() => (select(openTabs)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();

  /// Replaces the whole tab list in one transaction (the list is small).
  Future<void> saveTabs(List<OpenTabsCompanion> tabs) => transaction(() async {
    await delete(openTabs).go();
    await batch((b) => b.insertAll(openTabs, tabs));
  });
}

/// The open database. Throws until main() overrides it, so a missing override
/// fails loudly at the first read; tests override it with an in-memory database.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => throw UnimplementedError('appDatabaseProvider is overridden in main()');
```

- `Preferences` has the key as its primary key, so `insertOnConflictUpdate` is an upsert: one row per setting, overwritten in place.
- `OpenTabs.position` stores tab order explicitly; SQL tables have no inherent order. [[Milestone 08 - The reader and open works|Milestone 8]]'s tabs repository is the first to use the table.
- `openedAt` uses `withDefault(currentDateAndTime)`, so inserts don't need to pass it. `build.yaml` from [[Milestone 01 - Project setup and the folder structure|milestone 1]] stores it as ISO-8601 text.
- `driftDatabase(name: 'noctua')` (from drift_flutter) opens `noctua.sqlite` in the app's documents folder on a background isolate, so queries never block the UI thread.
- The optional `QueryExecutor` parameter is the test seam: tests pass `NativeDatabase.memory()` and get a fresh database per test.
- `saveTabs` replaces all rows inside one `transaction`: either the whole new list is saved or nothing changes, so a crash mid-save can't leave half a tab list.
- `appDatabaseProvider` throws until `main()` overrides it, so forgetting the override fails loudly at the first read instead of silently writing nowhere.

Drift generates, among others, the `OpenTab` row class and `OpenTabsCompanion` (a row where every column is optional, for inserts and partial updates). Bump `schemaVersion` and add a `MigrationStrategy` the first time a table changes. Because settings live as rows, adding a setting never touches the schema.

**Step 2: the preference type.** `Pref<T>` pairs a stable key with a typed default. Everything is stored as text, and `decode` turns it back:

```dart
/// A typed setting: a stable key, a default, and how the value is stored as
/// text. Plain Dart, so every layer can use the registry below.
class Pref<T> {
  const Pref(this.key, this.defaultValue);

  final String key;
  final T defaultValue;

  T decode(String? raw) {
    if (raw == null) return defaultValue;
    final Object? d = defaultValue;
    Object? value;
    if (d is bool) {
      value = raw == 'true';
    } else if (d is int) {
      value = int.tryParse(raw);
    } else if (d is double) {
      value = double.tryParse(raw);
    } else {
      value = raw;
    }
    return value is T ? value : defaultValue;
  }

  String encode(T value) => value.toString();
}
```

- `decode` branches on the type of the default value, because generic type checks like `T == bool` are unreliable for nullable and subtyped types.
- A value that fails to parse (an `int` setting holding `"abc"` after a bad sync, say) falls back to the default instead of throwing.

**Step 3: the registry.** Every key in one place, in the same file. Group by screen, comment the allowed values of string settings, and never rename a key without a migration, since the key is what's stored. Start it with the two keys the updater needs; each later milestone adds its own group, and the full list ends up around 120 settings:

```dart
/// Every preference the app knows about. Keys are stable; never rename one
/// without a migration.
abstract final class Prefs {
  // About
  static const autoCheckAppUpdates = Pref<bool>('app.autoCheckUpdates', true);
  static const lastUpdateCheck = Pref<int>('app.lastUpdateCheck', 0); // epoch ms
}
```

**Step 4: the repository and the extensions.** One notifier holds every setting as a `Map<String, String>`. Screens never read the map directly; they go through `ref.pref`, which watches a single key:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noctua/src/database/app_database.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'preferences_repository.g.dart';

/// Overridden in main() with the preferences read at startup.
@Riverpod(keepAlive: true)
Map<String, String> initialPrefs(Ref ref) => const {};

/// The app's settings: the Drift `preferences` table plus an in-memory copy.
///
/// A repository with a cache: its state is every setting as stored text, read
/// synchronously by widgets through `ref.pref`, and its methods write through
/// to Drift. Settings are read before the first frame, so nothing flashes.
@Riverpod(keepAlive: true)
class PreferencesRepository extends _$PreferencesRepository {
  @override
  Map<String, String> build() => Map.of(ref.read(initialPrefsProvider));

  T get<T>(Pref<T> pref) => pref.decode(state[pref.key]);

  Future<void> set<T>(Pref<T> pref, T value) async {
    final raw = pref.encode(value);
    if (state[pref.key] == raw) return;
    state = {...state, pref.key: raw};
    await ref.read(appDatabaseProvider).putPreference(pref.key, raw);
  }

  Future<void> reset(Iterable<Pref<Object?>> prefs) async {
    final keys = prefs.map((p) => p.key).toSet();
    state = {...state}..removeWhere((k, _) => keys.contains(k));
    await ref.read(appDatabaseProvider).deletePreferences(keys);
  }

  /// "Reset all settings": library, progress and downloads are untouched.
  Future<void> resetAll() async {
    final userKeys = state.keys.where((k) => !k.startsWith('internal.') && !k.startsWith('auth.')).toList();
    state = {...state}..removeWhere((k, _) => userKeys.contains(k));
    await ref.read(appDatabaseProvider).deletePreferences(userKeys);
  }
}

extension PrefWidgetRef on WidgetRef {
  /// Watches one preference; rebuilds only when that value changes.
  T pref<T>(Pref<T> pref) => watch(preferencesRepositoryProvider.select((m) => pref.decode(m[pref.key])));

  void setPref<T>(Pref<T> pref, T value) => read(preferencesRepositoryProvider.notifier).set(pref, value);

  /// Reads one preference once, without watching (for callbacks).
  T readPref<T>(Pref<T> pref) => pref.decode(read(preferencesRepositoryProvider)[pref.key]);
}

extension PrefRef on Ref {
  T pref<T>(Pref<T> pref) => watch(preferencesRepositoryProvider.select((m) => pref.decode(m[pref.key])));
}
```

- This is the "repository with a cache" pattern from [[02 Architecture|the Architecture section]]: the state is the cache, and every method writes through to Drift. `set` updates `state` first and writes second, so the UI changes instantly and the write happens in the background. The early `return` skips both when nothing changed.
- `state = {...state, key: raw}` builds a new map. Riverpod notifies listeners when `state` is replaced, not when a map is mutated in place, so `state[key] = raw` would silently do nothing.
- `watch(preferencesRepositoryProvider.select(...))` is what makes this cheap: `select` compares the decoded value before and after each change, and only rebuilds widgets whose value actually changed. A screen watching `gridColumns` doesn't rebuild when the theme changes.
- `resetAll` keeps `internal.*` and `auth.*` keys, so "Reset all settings" doesn't sign you out or reseed the sample tabs.
- `PrefRef` gives providers the same `ref.pref` that widgets have; the theme provider in [[Milestone 05 - Theming and the app shell|milestone 5]] is the first to use it.

**Step 5: the update service, finished.** With preferences in place, the service records when it checked and decides whether the launch check is due. This is its final version; compare it with [[Milestone 03 - In-app updates|milestone 3]]'s:

```dart
import 'package:noctua/src/constants/app_config.dart';
import 'package:noctua/src/features/app_update/data/apk_installer.dart';
import 'package:noctua/src/features/app_update/data/installed_app_reader.dart';
import 'package:noctua/src/features/app_update/data/releases_repository.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
import 'package:noctua/src/features/app_update/domain/install_progress.dart';
import 'package:noctua/src/features/app_update/domain/update_check_result.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_update_service.g.dart';

/// Checking for and installing app updates.
///
/// Joins the releases repository, the installed app, the preferences (the
/// automatic-check switch and when the last check ran) and the installer.
/// The rules for which release fits this device live in the domain
/// ([pickUpdate]); this class only gathers the inputs and records the result.
class AppUpdateService {
  AppUpdateService(this.ref);
  final Ref ref;

  static const autoCheckInterval = Duration(hours: 20);

  /// Play Store builds update through the store, so the updater is off.
  bool get enabled => !isPlayStoreBuild;

  /// Fetches the releases, records the time and picks the update for this device.
  Future<UpdateCheckResult> check() async {
    final releases = await ref.read(releasesRepositoryProvider).fetchReleases();
    final now = DateTime.now();
    await ref.read(preferencesRepositoryProvider.notifier).set(Prefs.lastUpdateCheck, now.millisecondsSinceEpoch);
    return UpdateCheckResult(releases: releases, update: pickUpdate(releases, ref.read(installedAppProvider)), checkedAt: now);
  }

  /// Whether the launch-time check should run: automatic checks are on and
  /// the last check was long enough ago.
  bool isCheckDue() {
    final prefs = ref.read(preferencesRepositoryProvider.notifier);
    if (!enabled || !prefs.get(Prefs.autoCheckAppUpdates)) return false;
    final last = DateTime.fromMillisecondsSinceEpoch(prefs.get(Prefs.lastUpdateCheck));
    return DateTime.now().difference(last) >= autoCheckInterval;
  }

  /// Downloads and installs [update]. The checksum is verified when the
  /// release has one; a missing or unreadable `SHA256SUMS.txt` installs
  /// without verification instead of blocking the update.
  Stream<InstallProgress> install(AvailableUpdate update) async* {
    yield const InstallProgress(InstallStage.downloading);
    final sha = await ref.read(releasesRepositoryProvider).fetchChecksum(update.release, update.apk).catchError((_) => null);
    yield* ref.read(apkInstallerProvider).install(url: update.apk.url, fileName: update.apk.name, sha256: sha);
  }

  Future<void> cancelInstall() => ref.read(apkInstallerProvider).cancel();
}

@riverpod
AppUpdateService appUpdateService(Ref ref) => AppUpdateService(ref);
```

- `ref.read(preferencesRepositoryProvider.notifier)` gets the repository itself (to call `get` and `set`) rather than its state.
- 20 hours rather than 24 means a user who opens the app at roughly the same time every day still gets a daily check.
- `AppUpdateController` doesn't change: it already asked the service, and the service now gives a different answer.

**Step 6: `main()`.** Everything that must be known before the first frame is read here, then injected with `overrideWithValue`. For this milestone:

```dart
Future<void> main() async {
  // Keep the native splash up until preferences are loaded, so the first
  // frame already has the saved settings.
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  F.appFlavor = Flavor.values.asNameMap()[appFlavor] ?? Flavor.stable;

  final db = AppDatabase();
  final prefs = await db.loadPreferences();
  final installed = await readInstalledApp();

  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      initialPrefsProvider.overrideWithValue(prefs),
      installedAppProvider.overrideWithValue(installed),
    ],
    child: const MaterialApp(home: AppUpdateListener(child: _TempHome())),
  ));
  FlutterNativeSplash.remove();
}
```

- Order matters: the database opens first, and the preferences come from it. Later milestones add their startup reads here in the same way: the dynamic colours (5), the open tabs (8), the session (11) and the crash guard (13).
- `FlutterNativeSplash.remove()` runs after `runApp`, so the native splash covers all of this loading.

**Step 7: testing the service with an in-memory database.** An application-layer test needs no widgets: a `ProviderContainer` with the same overrides `main()` uses, the fake releases repository, and a fresh in-memory database:

```dart
// Application: the service joins releases, the installed app and preferences.
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctua/src/database/app_database.dart';
import 'package:noctua/src/features/app_update/application/app_update_service.dart';
import 'package:noctua/src/features/app_update/data/fake_releases_repository.dart';
import 'package:noctua/src/features/app_update/data/installed_app_reader.dart';
import 'package:noctua/src/features/app_update/data/releases_repository.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';

ProviderContainer _container({required UpdateChannel channel, required String version, Map<String, String> prefs = const {}}) {
  final db = AppDatabase(NativeDatabase.memory());
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      initialPrefsProvider.overrideWithValue({...prefs}),
      releasesRepositoryProvider.overrideWithValue(const FakeReleasesRepository()),
      installedAppProvider.overrideWithValue(
        InstalledApp(channel: channel, versionName: version, versionCode: AppVersion.tryParse(version)!.code, abis: const ['arm64-v8a']),
      ),
    ],
  );
  addTearDown(() async {
    c.dispose();
    await db.close();
  });
  return c;
}

void main() {
  test('check picks the update for this channel and records the time', () async {
    final c = _container(channel: UpdateChannel.stable, version: '0.6.0');
    final result = await c.read(appUpdateServiceProvider).check();
    expect(result.update?.release.version.toString(), '0.6.1'); // the beta is skipped on stable
    expect(result.releases, hasLength(2));
    expect(c.read(preferencesRepositoryProvider.notifier).get(Prefs.lastUpdateCheck), greaterThan(0));
  });

  test('beta installs get the newest pre-release', () async {
    final c = _container(channel: UpdateChannel.beta, version: '0.6.1');
    final result = await c.read(appUpdateServiceProvider).check();
    expect(result.update?.release.version.toString(), '0.7.0-beta.2');
  });

  test('the launch check is due only when automatic checks are on and none ran recently', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool due(Map<String, String> prefs) =>
        _container(channel: UpdateChannel.stable, version: '0.6.0', prefs: prefs).read(appUpdateServiceProvider).isCheckDue();

    expect(due({}), isTrue);
    expect(due({Prefs.lastUpdateCheck.key: '$now'}), isFalse);
    expect(due({Prefs.autoCheckAppUpdates.key: 'false'}), isFalse);
  });
}
```

- `addTearDown` disposes the container and closes the database after each test, so tests never share state.
- The prefs map passed to `initialPrefsProvider` is how a test starts from "checked a minute ago" or "automatic checks off" without touching the UI.

`NativeDatabase` needs the SQLite library on the machine running the tests (`libsqlite3` on Linux, preinstalled on macOS and GitHub's runners).

> [!success] Checkpoint
> `flutter test` passes the new service tests. On a phone, open the app, close it and open it again: the second launch shows no update snackbar, because the last check was under 20 hours ago. There is still nothing new to screenshot; the next milestone uses these preferences for the theme.

---
← [[Milestone 03 - In-app updates]] · [[00 Index|Index]] · [[Milestone 05 - Theming and the app shell]] →
