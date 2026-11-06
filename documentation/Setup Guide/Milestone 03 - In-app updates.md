---
title: "Milestone 3: In-app updates"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 3
aliases:
  - Milestone 3
updated: 2026-11-06
---
# Milestone 3: In-app updates

After this milestone, a push to `develop` is all it takes to reach testers: the app checks GitHub Releases on launch, picks the APK for its channel and CPU, verifies its SHA-256 and opens Android’s installer. This build is the one to send testers first, because it is the first that can update itself.

It is also the first feature, and it uses all four layers, so it doubles as a worked example of [[02 Architecture|the Architecture section]]. It depends on nothing but the packages from [[Milestone 01 - Project setup and the folder structure|milestone 1]]: no theme, router or preferences yet. The places those arrive later are named as they come up.

**1. Packages and Android setup.** Add `ota_update` (download, checksum, install), `package_info_plus` (installed version), `device_info_plus` (CPU types) and `dio` (every network call the app makes). Then give the installer what it needs in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
<!-- ota_update also asks for these; Noctua doesn't need them -->
<uses-permission android:name="android.permission.INSTALL_PACKAGES" tools:node="remove" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove" />

<application ...>
  <provider
      android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
      android:authorities="${applicationId}.ota_update_provider"
      android:exported="false"
      android:grantUriPermissions="true">
    <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/filepaths" />
  </provider>
  <receiver android:name="sk.fourq.otaupdate.InstallResultReceiver" android:exported="false">
    <intent-filter><action android:name="${applicationId}.ACTION_INSTALL_COMPLETE" /></intent-filter>
  </receiver>
</application>
```

Add `xmlns:tools` to the `<manifest>` tag, and create `res/xml/filepaths.xml` with `<files-path name="internal_apk_storage" path="ota_update/" />`.

**2. Shared config** in `lib/src/constants/app_config.dart`: `githubOwner` and `githubRepoName` (the error reports in [[Milestone 13 - Errors, tablets and e-ink|milestone 13]] reuse them), and `isPlayStoreBuild = bool.fromEnvironment('PLAY_STORE')`. Google Play doesn’t allow apps to update themselves, so a Play build passes `--dart-define=PLAY_STORE=true` and the updater switches off.

**One HTTP client** in `lib/src/networking/dio_provider.dart`. Every repository that talks to a server takes this `Dio`, so timeouts, the user agent and debug logging live in one place, and tests can override `dioProvider` (or the repository above it) without touching real endpoints. The sync client in [[Milestone 11 - Accounts and sync|milestone 11]] and the source extensions later reuse it.

```dart
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'User-Agent': 'Noctua-app'},
  ));
  if (kDebugMode) dio.interceptors.add(LogInterceptor(requestHeader: false, responseHeader: false));
  ref.onDispose(dio.close);
  return dio;
}
```

**3. The `app_update` feature,** layer by layer:

| File | Layer | Holds |
| --- | --- | --- |
| `domain/app_release.dart` | domain | Freezed models: `AppVersion` (parses tags, same version code as the workflow), `AppRelease`, `ReleaseAsset`, `InstalledApp`, `AvailableUpdate`; plus `UpdateChannel`, `pickUpdate` and `checksumFor` |
| `domain/install_progress.dart`, `domain/update_check_result.dart` | domain | `InstallProgress` (stage and percent) and `UpdateCheckResult` (every release, the update for this device, when it was checked) |
| `data/releases_repository.dart` | data | `ReleasesRepository(Dio)`: `fetchReleases()` (`GET /repos/{owner}/{repo}/releases`, no token; 403 or 429 becomes the rate-limit message) and `fetchChecksum()`; `releasesRepositoryProvider` |
| `data/apk_installer.dart` | data | `ApkInstaller`, the only file that imports ota\_update; `apkInstallerProvider` |
| `data/installed_app_reader.dart` | data | `readInstalledApp()` (version and supported ABIs, read once in `main()`; the channel comes from the flavor) and `installedAppProvider` |
| `data/fake_releases_repository.dart`, `data/fake_apk_installer.dart` | data | Fakes that `implements` the concrete classes, for tests and screenshots |
| `application/app_update_service.dart` | application | `AppUpdateService`: `check()` joins releases and the installed app through `pickUpdate`; `install()` fetches the checksum and starts the installer |
| `presentation/app_update_controller.dart` | presentation | `AppUpdateController` (the last check, shared by every screen that shows it) and `InstallController` (download progress on the update page) |
| `presentation/app_update_page.dart`, `presentation/widgets/` | presentation | The update page and changelog; `AppUpdateListener` (launch check and offer), `UpdateAvailableTile`, `ReleaseNotes` |

**4. The rule that decides what each install gets.** It is a pure function in `domain/`, so it is unit-tested without a device or network:

```dart
AvailableUpdate? pickUpdate(Iterable<AppRelease> releases, InstalledApp app) {
  AvailableUpdate? best;
  for (final r in releases) {
    if (app.channel == UpdateChannel.stable && r.prerelease) continue; // stable never sees betas
    if (r.version.code <= app.versionCode) continue;                    // only newer builds
    final apk = app.abis.map((abi) => r.apkFor(app.channel, abi)).nonNulls.firstOrNull;
    if (apk == null) continue;                                          // nothing for this CPU
    if (best == null || r.version > best.release.version) best = AvailableUpdate(r, apk);
  }
  return best;
}
```

| Installed app | Considers | Downloads |
| --- | --- | --- |
| Noctua (stable) | Stable releases only | `noctua-stable-<version>-<abi>.apk` |
| Noctua Beta | Every release, beta and stable | `noctua-beta-<version>-<abi>.apk`; stable tags publish one too |

**5. Download and install.** The service fetches the expected hash from the release’s `SHA256SUMS.txt` and hands it to the installer, which refuses a file that doesn’t match. The page never sees either repository; it calls the controller, which listens to the service’s progress stream:

```dart
Stream<InstallProgress> install(AvailableUpdate update) async* {
  yield const InstallProgress(InstallStage.downloading);
  final sha = await ref.read(releasesRepositoryProvider).fetchChecksum(update.release, update.apk).catchError((_) => null);
  yield* ref.read(apkInstallerProvider).install(url: update.apk.url, fileName: update.apk.name, sha256: sha);
}
```

The first time, Android asks the user to allow Noctua to install apps; the page explains that if permission is missing. Updates must be signed with the same upload key as the installed app, which is why [[Milestone 02 - Release pipeline for beta and stable|milestone 2]]’s key must never change.

**6. Wire it in for now.** There is no router or shell yet, so replace the counter app’s home with a plain page: the app name, the installed version and a Check for updates button that pushes the update page with `Navigator.push`. Wrap it in `AppUpdateListener`, which runs the launch check and shows a snackbar with a View action when an update exists. Later milestones move these into place:

- [[Milestone 04 - Preferences and the local database|Milestone 4]] adds preferences: “Check automatically” and the last-check time, so the launch check runs at most once every 20 hours. Until then it runs on every launch.
- [[Milestone 05 - Theming and the app shell|Milestone 5]] adds the theme shortcuts and the router: the update page and changelog become `@RoutePage`s, and the home shell is wrapped in `AppUpdateListener`.
- [[Milestone 10 - Settings|Milestone 10]] adds the About rows: channel, Check for updates, Check automatically, Changelog.

**7. Tests, one file per layer.** Delete the counter test and add, under `test/src/features/app_update/`: `domain/app_release_test.dart` (version codes match the workflow, a stable release sorts after its betas, stable installs ignore pre-releases, beta installs roll onto stable releases, CPU fallback, checksum parsing) and `data/releases_repository_test.dart` (GitHub JSON parsing, and the repository against a canned HTTP adapter). [[Milestone 04 - Preferences and the local database|Milestone 4]] adds the service test, once preferences exist. From here CI runs real tests on every pull request.

**Ship cadence from here.** Merge each milestone into `develop` and the push publishes a beta. Bump the version in `pubspec.yaml` when a milestone starts, so its betas group under one number; tag a stable release on `main` whenever a beta has held up:

| Milestone | `pubspec.yaml` version on `develop` | Betas published |
| --- | --- | --- |
| 3 In-app updates | 0.1.0 | `v0.1.0-beta.N` (first tester invite) |
| 4 Preferences and database | 0.2.0 | `v0.2.0-beta.N` |
| 5 to 13 | 0.3.0 to 0.11.0, one minor version per milestone | `v0.3.0-beta.N` to `v0.11.0-beta.N` |
| 14 Tests | 1.0.0 | `v1.0.0-beta.N`, then tag `v1.0.0` on `main` |

## Code walkthrough: milestone 3

The feature is built bottom-up, the same order every later feature follows: shared config and the HTTP client, then the domain (which you can unit-test straight away), the data layer, the service that joins them, the controllers, and finally the screens.

**Step 1: shared config.** `lib/src/constants/app_config.dart` holds the repository name and the Play Store switch. `bool.fromEnvironment` is evaluated at compile time from `--dart-define`, so a Play build has the updater compiled out of its decisions rather than hidden behind a setting.

```dart
/// The GitHub repository that hosts releases (in-app updates) and issues
/// (error reports and feedback). Change both to your repository.
const githubOwner = 'your-github-name';
const githubRepoName = 'noctua';
const githubRepo = '$githubOwner/$githubRepoName';

/// Builds published to Google Play must not update themselves, so the Play
/// workflow passes `--dart-define=PLAY_STORE=true` and the updater turns off.
const isPlayStoreBuild = bool.fromEnvironment('PLAY_STORE');
```

**Step 2: the HTTP client.** One `Dio` for the whole app, created by a provider so tests can replace it. `ref.onDispose(dio.close)` releases its connection pool if the provider is ever thrown away (in practice only in tests, since it is `keepAlive`).

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_provider.g.dart';

/// The one HTTP client the app uses. Features build their repositories on it,
/// so timeouts, the user agent and logging are set in one place.
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': 'Noctua-app'},
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(requestHeader: false, responseHeader: false, logPrint: (o) => debugPrint('$o')));
  }
  ref.onDispose(dio.close);
  return dio;
}
```

**Step 3: the domain models.** Everything that decides what a device downloads lives in `domain/app_release.dart`, with no Flutter, network or Riverpod imports. Read it in order:

```dart
/// Which release line this install follows. It comes from the build flavor,
/// not a setting: Noctua (stable) and Noctua Beta are separate apps.
enum UpdateChannel {
  stable,
  beta;

  String get label => this == beta ? 'Beta' : 'Stable';
}

/// A release version as tagged: `1.4.2` or `1.5.0-beta.3`.
@freezed
abstract class AppVersion with _$AppVersion implements Comparable<AppVersion> {
  const factory AppVersion(
    int major,
    int minor,
    int patch, [

    /// Beta number, or null for a stable release.
    int? beta,
  ]) = _AppVersion;
  const AppVersion._();

  static final _pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$');

  /// Parses a tag or version name; null when it isn't one of ours.
  static AppVersion? tryParse(String input) {
    final m = _pattern.firstMatch(input.trim());
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), m[4] == null ? null : int.parse(m[4]!));
  }

  bool get isBeta => beta != null;

  /// The Android version code the release workflow gives this version:
  /// `major·10⁷ + minor·10⁵ + patch·10³ + n`, where betas use n = 1–998 and the
  /// stable release 999, so stable always upgrades its own betas.
  int get code => major * 10000000 + minor * 100000 + patch * 1000 + (beta ?? 999);

  @override
  int compareTo(AppVersion other) => code.compareTo(other.code);

  @override
  String toString() => '$major.$minor.$patch${beta == null ? '' : '-beta.$beta'}';
}
```

- `UpdateChannel` is an enhanced enum: the `label` getter lives on the enum itself.
- `AppVersion` uses positional Freezed fields (`AppVersion(1, 4, 2)`); the optional `[int? beta]` makes stable versions the 3-argument form.
- `tryParse` returns null for anything that isn't `vX.Y.Z` or `vX.Y.Z-beta.N`, so stray tags like `nightly` are skipped instead of crashing the check.
- `code` mirrors the bash arithmetic in `build-android.yml` exactly. If you ever change one, change both, and the version-code test fails until you do.
- `compareTo` orders by code, so sorting and "is newer" both agree with what Android itself compares.
- `toString` is overridden after Freezed, so string interpolation gives `1.5.0-beta.3` rather than Freezed's `AppVersion(major: 1, …)`. The APK names depend on that.

```dart
@freezed
abstract class ReleaseAsset with _$ReleaseAsset {
  const factory ReleaseAsset({
    required String name,
    required String url,

    /// Bytes.
    required int size,
  }) = _ReleaseAsset;
  const ReleaseAsset._();

  String get sizeLabel => '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}

@freezed
abstract class AppRelease with _$AppRelease {
  const factory AppRelease({
    required AppVersion version,
    required String title,

    /// Markdown release notes, as GitHub generated or the author wrote them.
    required String notes,
    required bool prerelease,
    required DateTime publishedAt,
    required String pageUrl,
    required List<ReleaseAsset> assets,
  }) = _AppRelease;
  const AppRelease._();

  /// The APK for [channel] built for [abi], named by the release workflow
  /// `noctua-<channel>-<version>-<abi>.apk`.
  ReleaseAsset? apkFor(UpdateChannel channel, String abi) =>
      assets.where((a) => a.name == 'noctua-${channel.name}-$version-$abi.apk').firstOrNull;

  ReleaseAsset? get checksums => assets.where((a) => a.name == 'SHA256SUMS.txt').firstOrNull;
}

/// What is installed on this device.
@freezed
abstract class InstalledApp with _$InstalledApp {
  const factory InstalledApp({
    required UpdateChannel channel,
    required String versionName,
    required int versionCode,

    /// Supported ABIs, most preferred first (from the device).
    required List<String> abis,
  }) = _InstalledApp;

  /// Used in tests and on platforms where nothing can be read.
  static const unknown = InstalledApp(channel: UpdateChannel.stable, versionName: '0.0.0', versionCode: 0, abis: ['arm64-v8a']);
}

/// A newer release this device can install.
@freezed
abstract class AvailableUpdate with _$AvailableUpdate {
  const factory AvailableUpdate(AppRelease release, ReleaseAsset apk) = _AvailableUpdate;
}
```

- `ReleaseAsset.sizeLabel` and `AppRelease.apkFor` are getters/methods, so these two declare `const X._();`.
- `apkFor` rebuilds the file name the workflow wrote and looks it up. Nothing parses asset names; if the name doesn't match exactly, the asset doesn't exist as far as the app is concerned.
- `InstalledApp.unknown` is a `static const`, so it can be the default value of a provider and of test fixtures.

```dart
/// Picks the newest release this install can update to, or null.
///
/// Stable installs only consider stable releases. Beta installs consider every
/// release, because stable tags also publish a beta-flavor APK, so testers move
/// onto each stable release and then onto the next beta.
AvailableUpdate? pickUpdate(Iterable<AppRelease> releases, InstalledApp app) {
  AvailableUpdate? best;
  for (final r in releases) {
    if (app.channel == UpdateChannel.stable && r.prerelease) continue;
    if (r.version.code <= app.versionCode) continue;
    final apk = app.abis.map((abi) => r.apkFor(app.channel, abi)).nonNulls.firstOrNull;
    if (apk == null) continue;
    if (best == null || r.version > best.release.version) best = AvailableUpdate(r, apk);
  }
  return best;
}

/// Reads the hash for [fileName] from a `sha256sum` listing.
String? checksumFor(String sha256sums, String fileName) {
  for (final line in sha256sums.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+\*?'));
    if (parts.length == 2 && parts[1] == fileName) return parts[0].toLowerCase();
  }
  return null;
}
```

`pickUpdate` walks every release once:

1. Stable installs skip pre-releases.
2. Releases not newer than the installed version code are skipped.
3. For the rest, it tries the device's ABIs in order of preference (`arm64-v8a` first on most phones, then `armeabi-v7a`) and takes the first APK that exists.
4. It keeps the newest candidate. The `>` operator comes from a private extension at the bottom of the file, so the comparison reads naturally.

`checksumFor` parses `sha256sum` output (`<hash>  <file>`, or `<hash> *<file>` in binary mode, hence the `\*?` in the split pattern).

Two small models complete the domain. `InstallProgress` is what the installer reports, and `UpdateCheckResult` is what a check produces:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'install_progress.freezed.dart';

enum InstallStage { downloading, installing, done, failed, canceled }

@freezed
abstract class InstallProgress with _$InstallProgress {
  const factory InstallProgress(
    InstallStage stage, {

    /// 0–100 while downloading.
    @Default(0) int percent,
    String? error,
  }) = _InstallProgress;
}
```

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';

part 'update_check_result.freezed.dart';

/// The result of a check: every release (for the changelog) and the update
/// this device can install, if any.
@freezed
abstract class UpdateCheckResult with _$UpdateCheckResult {
  const factory UpdateCheckResult({required List<AppRelease> releases, required AvailableUpdate? update, required DateTime checkedAt}) =
      _UpdateCheckResult;
}
```

**Step 4: the releases repository.** A concrete class over Dio, with no interface in front of it. Its job is to turn GitHub's JSON and HTTP errors into domain models and one exception type:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:noctua/src/constants/app_config.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
import 'package:noctua/src/networking/dio_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'releases_repository.g.dart';

class ReleaseCheckException implements Exception {
  const ReleaseCheckException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The app's releases, from GitHub Releases through the public REST API with
/// the app's [Dio]. No token is needed: the unauthenticated limit is 60
/// requests an hour per IP, and the app checks at most once a day plus when
/// asked. Tests and screenshots use FakeReleasesRepository instead.
class ReleasesRepository {
  ReleasesRepository(this._dio);
  final Dio _dio;

  static final _api = Options(headers: {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'});

  /// Published releases, newest first. Drafts and tags that aren't versions are left out.
  Future<List<AppRelease>> fetchReleases() async {
    try {
      final res = await _dio.get<List<dynamic>>(
        'https://api.github.com/repos/$githubRepo/releases',
        queryParameters: {'per_page': 30},
        options: _api,
      );
      return parseReleaseList(res.data ?? const []);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 429) {
        throw const ReleaseCheckException('GitHub is limiting requests right now. Try again in an hour.');
      }
      if (code != null) throw ReleaseCheckException('GitHub answered $code.');
      throw const ReleaseCheckException('Couldn’t reach GitHub. Check your connection and try again.');
    }
  }

  /// The expected SHA-256 of [apk], from the release's `SHA256SUMS.txt`, if it has one.
  Future<String?> fetchChecksum(AppRelease release, ReleaseAsset apk) async {
    final sums = release.checksums;
    if (sums == null) return null;
    try {
      final res = await _dio.get<String>(sums.url, options: Options(responseType: ResponseType.plain));
      return checksumFor(res.data ?? '', apk.name);
    } on DioException {
      return null;
    }
  }
}

/// Parses the JSON from `GET /repos/{owner}/{repo}/releases`.
List<AppRelease> parseReleases(String body) => parseReleaseList(jsonDecode(body) as List<dynamic>);

/// Same, for JSON dio already decoded.
List<AppRelease> parseReleaseList(List<dynamic> list) {
  final out = <AppRelease>[];
  for (final raw in list.cast<Map<String, dynamic>>()) {
    if (raw['draft'] == true) continue;
    final version = AppVersion.tryParse(raw['tag_name'] as String? ?? '');
    if (version == null) continue;
    out.add(
      AppRelease(
        version: version,
        title: (raw['name'] as String?)?.trim().isNotEmpty == true ? raw['name'] as String : 'Noctua $version',
        notes: raw['body'] as String? ?? '',
        prerelease: raw['prerelease'] == true,
        publishedAt: DateTime.tryParse(raw['published_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        pageUrl: raw['html_url'] as String? ?? 'https://github.com/$githubRepo/releases',
        assets: [
          for (final a in (raw['assets'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
            ReleaseAsset(name: a['name'] as String, url: a['browser_download_url'] as String, size: (a['size'] as num?)?.toInt() ?? 0),
        ],
      ),
    );
  }
  out.sort((a, b) => b.version.compareTo(a.version));
  return out;
}

@Riverpod(keepAlive: true)
ReleasesRepository releasesRepository(Ref ref) => ReleasesRepository(ref.watch(dioProvider));
```

- `_dio.get<List<dynamic>>` tells Dio to decode the JSON body and cast it; GitHub returns an array of releases.
- The `Accept` and `X-GitHub-Api-Version` headers pin the response format, so a future API change can't silently break parsing.
- Errors become a `ReleaseCheckException` with a sentence a user can act on. A 403 or 429 from GitHub means the hourly limit for this IP address was reached.
- `fetchChecksum` requests the text file with `ResponseType.plain`; without it Dio would try to decode it as JSON.
- `parseReleaseList` is a top-level function, separate from the class, so tests can feed it a JSON fixture directly. It drops drafts and non-version tags, falls back to a title when the release has no name, and sorts newest first.
- `releasesRepositoryProvider` builds the repository on `dioProvider`. Methods are named `fetchX`, the convention every repository in the guide follows.

The fake lives in its own file and `implements` the concrete class. Dart lets any class be used as an interface, so there is no abstract class to keep in sync:

```dart
import 'package:noctua/src/constants/app_config.dart';
import 'package:noctua/src/features/app_update/data/releases_repository.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';

/// Sample releases for tests, screenshots and builds without a real repository.
class FakeReleasesRepository implements ReleasesRepository {
  const FakeReleasesRepository({this.fail = false});
  final bool fail;

  static List<ReleaseAsset> _assets(String channel, String v) => [
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
      ReleaseAsset(name: 'noctua-$channel-$v-$abi.apk', url: 'https://example.invalid/noctua-$channel-$v-$abi.apk', size: 24100000),
    const ReleaseAsset(name: 'SHA256SUMS.txt', url: 'https://example.invalid/SHA256SUMS.txt', size: 400),
  ];

  static final samples = [
    AppRelease(
      version: const AppVersion(0, 7, 0, 2),
      title: 'Noctua 0.7.0-beta.2',
      notes:
          '## What’s Changed\n* Reader: chapters sheet without leaving the page\n* Save prompt for works you keep reading\n* Fix covers stretching on tablets\n',
      prerelease: true,
      publishedAt: DateTime.utc(2026, 11, 4),
      pageUrl: 'https://github.com/$githubRepo/releases/tag/v0.7.0-beta.2',
      assets: [..._assets('beta', '0.7.0-beta.2')],
    ),
    AppRelease(
      version: const AppVersion(0, 6, 1),
      title: 'Noctua 0.6.1',
      notes:
          '## What’s Changed\n* Mihon themes and pure black dark mode\n* Feature tour and coach marks\n* Fix the library opening with demo filters on\n',
      prerelease: false,
      publishedAt: DateTime.utc(2026, 10, 28),
      pageUrl: 'https://github.com/$githubRepo/releases/tag/v0.6.1',
      assets: [..._assets('stable', '0.6.1'), ..._assets('beta', '0.6.1')],
    ),
  ];

  @override
  Future<List<AppRelease>> fetchReleases() async {
    if (fail) throw const ReleaseCheckException('Couldn’t reach GitHub. Check your connection and try again.');
    return samples;
  }

  @override
  Future<String?> fetchChecksum(AppRelease release, ReleaseAsset apk) async => null;
}
```

**Step 5: the installer.** `ota_update` does the downloading, checksum verification and the hand-off to Android's package installer. This class translates its events into the domain's `InstallProgress`, so nothing outside this file imports the plugin:

```dart
import 'package:noctua/src/features/app_update/domain/install_progress.dart';
import 'package:ota_update/ota_update.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'apk_installer.g.dart';

/// Downloads an APK and hands it to Android's package installer, through the
/// ota_update plugin. Nothing outside this file imports the plugin.
class ApkInstaller {
  Stream<InstallProgress> install({required String url, required String fileName, String? sha256}) =>
      OtaUpdate().execute(url, destinationFilename: fileName, sha256checksum: sha256).map(_map);

  Future<void> cancel() => OtaUpdate().cancel();

  static InstallProgress _map(OtaEvent e) => switch (e.status) {
    OtaStatus.DOWNLOADING => InstallProgress(InstallStage.downloading, percent: int.tryParse(e.value ?? '') ?? 0),
    OtaStatus.INSTALLING => const InstallProgress(InstallStage.installing, percent: 100),
    OtaStatus.INSTALLATION_DONE => const InstallProgress(InstallStage.done, percent: 100),
    OtaStatus.CANCELED => const InstallProgress(InstallStage.canceled),
    OtaStatus.PERMISSION_NOT_GRANTED_ERROR => const InstallProgress(
      InstallStage.failed,
      error: 'Allow Noctua to install apps (Android asks the first time), then try again.',
    ),
    OtaStatus.CHECKSUM_ERROR => const InstallProgress(
      InstallStage.failed,
      error: 'The download didn’t match its checksum, so it wasn’t installed. Try again.',
    ),
    OtaStatus.DOWNLOAD_ERROR => InstallProgress(InstallStage.failed, error: 'Download failed: ${e.value ?? 'unknown error'}'),
    _ => InstallProgress(InstallStage.failed, error: e.value ?? 'The update couldn’t be installed.'),
  };
}

@Riverpod(keepAlive: true)
ApkInstaller apkInstaller(Ref ref) => ApkInstaller();
```

- `execute` returns a `Stream<OtaEvent>`; `.map(_map)` converts each event as it arrives.
- The `switch` expression maps every status. `PERMISSION_NOT_GRANTED_ERROR` happens the first time, before the user allows "Install unknown apps" for Noctua.

```dart
import 'package:noctua/src/features/app_update/data/apk_installer.dart';
import 'package:noctua/src/features/app_update/domain/install_progress.dart';

/// Pretends to download in about a second; used by tests and screenshots.
class FakeApkInstaller implements ApkInstaller {
  @override
  Stream<InstallProgress> install({required String url, required String fileName, String? sha256}) async* {
    for (var p = 0; p <= 100; p += 25) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      yield InstallProgress(InstallStage.downloading, percent: p);
    }
    yield const InstallProgress(InstallStage.installing, percent: 100);
  }

  @override
  Future<void> cancel() async {}
}
```

`FakeApkInstaller` yields 0, 25, 50, 75, 100 percent with short delays, so the progress UI can be tested and screenshotted.

The plugin needs a file provider so the installer can read the downloaded APK. Create `android/app/src/main/res/xml/filepaths.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
  <files-path name="internal_apk_storage" path="ota_update/" />
</paths>
```

**Step 6: reading the installed app.** Runs once in `main()`. Every failure falls back to `InstalledApp.unknown` (version code 0), so a broken read means "offer the newest release" rather than a crash on startup. The provider returns the fallback until `main()` overrides it with the real value:

```dart
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:noctua/flavors.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'installed_app_reader.g.dart';

/// Reads the installed version and the device's ABIs. Runs once in main().
Future<InstalledApp> readInstalledApp() async {
  try {
    final info = await PackageInfo.fromPlatform();
    var abis = const ['arm64-v8a'];
    if (Platform.isAndroid) {
      final android = await DeviceInfoPlugin().androidInfo;
      if (android.supportedAbis.isNotEmpty) abis = android.supportedAbis;
    }
    return InstalledApp(
      channel: F.appFlavor == Flavor.beta ? UpdateChannel.beta : UpdateChannel.stable,
      versionName: info.version,
      versionCode: int.tryParse(info.buildNumber) ?? 0,
      abis: abis,
    );
  } on Object {
    return InstalledApp.unknown;
  }
}

/// Overridden in main() with the result of [readInstalledApp].
@Riverpod(keepAlive: true)
InstalledApp installedApp(Ref ref) => InstalledApp.unknown;
```

**Step 7: the service.** Checking for an update needs two repositories (releases and the installed app) plus a domain rule; installing needs two more (checksum and installer). That makes it application-layer work. The service is a plain class that takes `Ref`, exposed by a non-`keepAlive` provider because it holds no state. For this milestone, write it without preferences:

```dart
part 'app_update_service.g.dart';

class AppUpdateService {
  AppUpdateService(this.ref);
  final Ref ref;

  /// Play Store builds update through the store, so the updater is off.
  bool get enabled => !isPlayStoreBuild;

  Future<UpdateCheckResult> check() async {
    final releases = await ref.read(releasesRepositoryProvider).fetchReleases();
    return UpdateCheckResult(releases: releases, update: pickUpdate(releases, ref.read(installedAppProvider)), checkedAt: DateTime.now());
  }

  /// Milestone 4 adds the automatic-check switch and the 20-hour rule here.
  bool isCheckDue() => enabled;

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

- `ref.read` (not `watch`) inside methods: a method runs once and shouldn't subscribe to anything.
- `.catchError((_) => null)` means a missing or unreadable `SHA256SUMS.txt` installs without verification instead of blocking the update.
- `yield*` forwards every event of the installer's stream, after the service's own first "downloading" event, so the page shows progress before the checksum request returns.

**Step 8: the controllers.** Two presentation-layer notifiers, in their final form already (they only talk to the service):

```dart
import 'dart:async';

import 'package:noctua/src/features/app_update/application/app_update_service.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
import 'package:noctua/src/features/app_update/domain/install_progress.dart';
import 'package:noctua/src/features/app_update/domain/update_check_result.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_update_controller.g.dart';

/// The last update check, shared by the launch listener, the update page and
/// the "update available" rows. Null until the first check. Kept alive, so a
/// check started anywhere shows everywhere.
@Riverpod(keepAlive: true)
class AppUpdateController extends _$AppUpdateController {
  @override
  FutureOr<UpdateCheckResult?> build() => null;

  AppUpdateService get _service => ref.read(appUpdateServiceProvider);

  bool get enabled => _service.enabled;

  Future<void> check() async {
    if (!enabled) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_service.check);
  }

  /// The launch-time check: skipped when turned off or done recently.
  /// Returns whether a check ran.
  Future<bool> checkIfDue() async {
    if (!_service.isCheckDue()) return false;
    await check();
    return true;
  }
}

/// Download and install progress on the update page; null when idle.
/// Disposed with the page, which cancels listening to the download.
@riverpod
class InstallController extends _$InstallController {
  StreamSubscription<InstallProgress>? _sub;

  @override
  InstallProgress? build() {
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void install(AvailableUpdate update) {
    _sub?.cancel();
    _sub = ref
        .read(appUpdateServiceProvider)
        .install(update)
        .listen((p) => state = p, onError: (Object e) => state = InstallProgress(InstallStage.failed, error: '$e'));
  }

  Future<void> cancel() async {
    await ref.read(appUpdateServiceProvider).cancelInstall();
    await _sub?.cancel();
    state = null;
  }
}
```

- `AppUpdateController` is `keepAlive`: the launch listener, the update page and, later, the About and More rows all show the same check. Its state is `AsyncValue<UpdateCheckResult?>`: `null` until the first check, then `AsyncLoading`, `AsyncData` or `AsyncError`, which screens `switch` on.
- `AsyncValue.guard` runs the future and turns a thrown exception into `AsyncError`, so `check()` never throws at the caller.
- `InstallController` is auto-disposed with the update page. `ref.onDispose` cancels the download subscription, so a download finishing after the page closes doesn't update a dead screen.

The screens in steps 9 to 11 use only what exists at this point: colors and text styles from `Theme.of(context)`, and plain `Navigator.push` for moving between pages. [[Milestone 05 - Theming and the app shell|Milestone 5]] adds the theme shortcuts and the router and moves these widgets onto them.

**Step 9: the launch listener.** A widget that does work but draws only its child. The check starts after the first frame (`addPostFrameCallback`), so it never delays startup; `mounted` is checked after the `await` because the user may have navigated away.

```dart
/// Runs the launch-time update check and offers a found update once.
/// Wraps the home shell, so it starts with the first screen users see.
class AppUpdateListener extends ConsumerStatefulWidget {
  const AppUpdateListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppUpdateListener> createState() => _AppUpdateListenerState();
}

class _AppUpdateListenerState extends ConsumerState<AppUpdateListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launchCheck());
  }

  /// Only the automatic launch check offers the update; checks started from
  /// the update page or About show their result there instead.
  Future<void> _launchCheck() async {
    final checker = ref.read(appUpdateControllerProvider.notifier);
    if (!await checker.checkIfDue() || !mounted) return;
    final update = ref.read(appUpdateControllerProvider).value?.update;
    if (update == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Text('${update.release.title} is available'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppUpdatePage())),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

`UpdateAvailableTile` in the same file is the row [[Milestone 10 - Settings|milestone 10]] puts on About and More. It watches the same controller, so a check started anywhere updates it.

**Step 10: rendering release notes.** GitHub's generated notes use only headings, bullets and links, so a 60-line renderer is enough and avoids a Markdown package:

```dart
import 'package:flutter/material.dart';

/// Renders the small Markdown subset GitHub release notes use: headings,
/// bullets and paragraphs. Links keep their text; "by @user in https://…"
/// credits from generated notes are trimmed so lines stay readable.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(this.markdown, {super.key, this.maxItems});
  final String markdown;

  /// Show at most this many bullet points (null = all).
  final int? maxItems;

  static String clean(String s) => s
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .replaceAll(RegExp(r' by @[\w-]+ in https?://\S+'), '')
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .trim();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final children = <Widget>[];
    var bullets = 0;
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty || line.startsWith('**Full Changelog**')) continue;
      final heading = RegExp(r'^#{1,6}\s+(.*)').firstMatch(line);
      final bullet = RegExp(r'^\s*[*-]\s+(.*)').firstMatch(line);
      if (heading != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(clean(heading[1]!), style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.primary)),
          ),
        );
      } else if (bullet != null) {
        if (maxItems != null && bullets >= maxItems!) continue;
        bullets++;
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 10),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                  ),
                ),
                Expanded(child: Text(clean(bullet[1]!), style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(clean(line), style: Theme.of(context).textTheme.bodyMedium),
          ),
        );
      }
    }
    if (children.isEmpty) {
      children.add(Text('No release notes.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
```

`clean` keeps link text but drops the URL, removes "by @user in https://…" credits, and strips bold and code markers.

**Step 11: the update page.** The page holds no state of its own: the check comes from `AppUpdateController` and the download from `InstallController`.

```dart
/// Check for updates, read what changed, then download and install.
class AppUpdatePage extends ConsumerStatefulWidget {
  const AppUpdatePage({super.key});

  @override
  ConsumerState<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends ConsumerState<AppUpdatePage> {
  @override
  void initState() {
    super.initState();
    // Opening the page always shows fresh results.
    Future.microtask(() => ref.read(appUpdateControllerProvider.notifier).check());
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final app = ref.watch(installedAppProvider);
    final check = ref.watch(appUpdateControllerProvider);

    Widget header(String title, String subtitle, IconData icon) => Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: c.primaryContainer,
          child: Icon(icon, color: c.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );

    final installed = 'You have ${app.versionName} · ${app.channel.label} channel';
    final List<Widget> body;
    if (isPlayStoreBuild) {
      body = [header('Updates come from Google Play', installed, Symbols.shop_rounded)];
    } else {
      body = switch (check) {
        AsyncError(:final error) => [
          header('Couldn’t check for updates', installed, Symbols.cloud_off_rounded),
          const SizedBox(height: 16),
          Text('$error', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => ref.read(appUpdateControllerProvider.notifier).check(), child: const Text('Try again')),
        ],
        AsyncData(value: final result?) when result.update != null => _available(context, result.update!, installed),
        AsyncData(value: final result?) => [
          header('You’re up to date', installed, Symbols.check_circle_rounded),
          const SizedBox(height: 8),
          Text(
            'Checked ${TimeOfDay.fromDateTime(result.checkedAt).format(context)} against GitHub Releases.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => ref.read(appUpdateControllerProvider.notifier).check(), child: const Text('Check again')),
        ],
        _ => [
          header('Checking for updates…', installed, Symbols.sync_rounded),
          const SizedBox(height: 24),
          const LinearProgressIndicator(),
        ],
      };
    }

    return Scaffold(
      appBar: AppBar(title: const Text('App updates')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ...body,
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChangelogPage())),
            child: const Text('All releases'),
          ),
        ],
      ),
    );
  }
```

- Opening the page always re-checks (`Future.microtask` waits until `initState` has finished, because providers can't be modified during build).
- The body is a Dart 3 `switch` over the `AsyncValue`. Patterns like `AsyncData(value: final result?) when result.update != null` read as "loaded, not null, and has an update", and the cases are tried in order.

The rest of the page builds the "update available" view from the install progress, and `ChangelogPage` lists every release with the newest expanded:

```dart
  List<Widget> _available(BuildContext context, AvailableUpdate u, String installed) {
    final c = Theme.of(context).colorScheme;
    final p = ref.watch(installControllerProvider);
    final busy = p != null && (p.stage == InstallStage.downloading || p.stage == InstallStage.installing);
    return [
      Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: c.primaryContainer,
            child: Icon(Symbols.system_update_rounded, color: c.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.release.title, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '$installed\n${_date(u.release.publishedAt)} · ${u.apk.sizeLabel}${u.release.prerelease ? ' · pre-release' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ReleaseNotes(u.release.notes),
      const SizedBox(height: 24),
      if (busy) ...[
        LinearProgressIndicator(value: p.stage == InstallStage.installing ? null : p.percent / 100),
        const SizedBox(height: 8),
        Text(
          p.stage == InstallStage.installing ? 'Opening the installer…' : 'Downloading · ${p.percent}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: ref.read(installControllerProvider.notifier).cancel, child: const Text('Cancel')),
      ] else ...[
        if (p?.stage == InstallStage.failed) ...[
          Text(p!.error ?? 'The update couldn’t be installed.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.error)),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: () => ref.read(installControllerProvider.notifier).install(u),
          child: Text('Download and install · ${u.apk.sizeLabel}'),
        ),
      ],
      TextButton(
        onPressed: () => launchUrl(Uri.parse(u.release.pageUrl), mode: LaunchMode.externalApplication),
        child: const Text('View on GitHub'),
      ),
    ];
  }
}

/// Every published release, newest first, from the same check.
class ChangelogPage extends ConsumerStatefulWidget {
  const ChangelogPage({super.key});

  @override
  ConsumerState<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends ConsumerState<ChangelogPage> {
  final _open = <String>{};

  @override
  void initState() {
    super.initState();
    if (ref.read(appUpdateControllerProvider).value == null) {
      Future.microtask(() => ref.read(appUpdateControllerProvider.notifier).check());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final app = ref.watch(installedAppProvider);
    final check = ref.watch(appUpdateControllerProvider);
    final releases = [
      for (final r in check.value?.releases ?? const <AppRelease>[])
        if (app.channel == UpdateChannel.beta || !r.prerelease) r,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Changelog')),
      body: switch (check) {
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$error', textAlign: TextAlign.center),
          ),
        ),
        AsyncData(value: _?) when releases.isEmpty => const Center(child: Text('No releases yet.')),
        AsyncData(value: _?) => ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: releases.length,
          itemBuilder: (context, i) {
            final r = releases[i];
            final key = '${r.version}';
            final open = _open.contains(key) || i == 0;
            final installed = r.version.code == app.versionCode;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(r.title),
                  subtitle: Text('${_date(r.publishedAt)}${r.prerelease ? ' · beta' : ''}${installed ? ' · installed' : ''}'),
                  trailing: Icon(open ? Symbols.expand_less_rounded : Symbols.expand_more_rounded),
                  onTap: () => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key)),
                ),
                if (open) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: ReleaseNotes(r.notes)),
                Divider(color: c.outlineVariant, height: 1),
              ],
            );
          },
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
```

The changelog filters with the same channel rule as `pickUpdate`, so a stable install never sees beta notes.

**Step 12: the temporary home.** There is no router until [[Milestone 05 - Theming and the app shell|milestone 5]], so `main.dart` starts a small page wrapped in the listener, and the update screens navigate with `Navigator.push`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  F.appFlavor = Flavor.values.asNameMap()[appFlavor] ?? Flavor.stable;
  final installed = await readInstalledApp();
  runApp(ProviderScope(
    overrides: [installedAppProvider.overrideWithValue(installed)],
    child: const MaterialApp(home: AppUpdateListener(child: _TempHome())),
  ));
}

class _TempHome extends ConsumerWidget {
  const _TempHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(installedAppProvider);
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(F.title, style: Theme.of(context).textTheme.headlineMedium),
          Text('${app.versionName} · ${app.channel.label}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppUpdatePage())),
            child: const Text('Check for updates'),
          ),
        ]),
      ),
    );
  }
}
```

**Step 13: the tests.** One test file per layer, mirroring `lib/`. The domain test needs no device, no network and no Riverpod. A helper builds releases with the asset names the workflow would produce:

```dart
// Domain: the rules that decide what testers get (versions, channels, ABIs, checksums).
import 'package:flutter_test/flutter_test.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';

AppRelease release(String tag, {required bool pre, List<String> channels = const ['stable'], List<String> abis = const ['arm64-v8a']}) {
  final v = AppVersion.tryParse(tag)!;
  return AppRelease(
    version: v,
    title: 'Noctua $v',
    notes: '',
    prerelease: pre,
    publishedAt: DateTime.utc(2026),
    pageUrl: '',
    assets: [
      for (final c in channels)
        for (final abi in abis) ReleaseAsset(name: 'noctua-$c-$v-$abi.apk', url: 'https://x/$c-$v-$abi', size: 1),
    ],
  );
}

InstalledApp app(UpdateChannel channel, String version, {List<String> abis = const ['arm64-v8a']}) =>
    InstalledApp(channel: channel, versionName: version, versionCode: AppVersion.tryParse(version)!.code, abis: abis);
```

Then each rule gets a test. The first group pins the version-code formula to the same numbers as the workflow comment:

```dart
  group('AppVersion', () {
    test('parses tags and matches the workflow version codes', () {
      expect(AppVersion.tryParse('v1.4.2')!.code, 10402999);
      expect(AppVersion.tryParse('1.5.0-beta.3')!.code, 10500003);
      expect(AppVersion.tryParse('1.5.0-beta.250')!.code, 10500250);
      expect(AppVersion.tryParse('v0.7.0-beta.1')!.code, 700001);
      expect(AppVersion.tryParse('v1.2'), isNull);
      expect(AppVersion.tryParse('v1.0.0-rc.1'), isNull);
    });

    test('a stable release sorts after its betas', () {
      expect(AppVersion.tryParse('0.7.0')!.compareTo(AppVersion.tryParse('0.7.0-beta.9')!), greaterThan(0));
      expect(AppVersion.tryParse('0.7.1-beta.1')!.compareTo(AppVersion.tryParse('0.7.0')!), greaterThan(0));
    });
  });
```

The rest cover `pickUpdate` (stable ignores pre-releases, beta takes the newest of any kind, beta rolls onto stable, CPU fallback) and `checksumFor`:

```dart
  group('pickUpdate', () {
    final releases = [
      release('v0.8.0-beta.1', pre: true, channels: ['beta']),
      release('v0.7.0', pre: false, channels: ['stable', 'beta']),
      release('v0.7.0-beta.2', pre: true, channels: ['beta']),
    ];

    test('stable installs ignore pre-releases', () {
      expect(pickUpdate(releases, app(UpdateChannel.stable, '0.6.0'))!.release.version.toString(), '0.7.0');
    });

    test('beta installs take the newest release of any kind', () {
      expect(pickUpdate(releases, app(UpdateChannel.beta, '0.7.0-beta.2'))!.release.version.toString(), '0.8.0-beta.1');
    });

    test('beta testers roll onto the stable release when it is newest', () {
      final noNewBeta = releases.skip(1).toList();
      final u = pickUpdate(noNewBeta, app(UpdateChannel.beta, '0.7.0-beta.2'))!;
      expect(u.release.version.toString(), '0.7.0');
      expect(u.apk.name, 'noctua-beta-0.7.0-arm64-v8a.apk');
    });

    test('nothing newer means no update', () {
      expect(pickUpdate(releases, app(UpdateChannel.stable, '0.7.0')), isNull);
    });

    test('a release without an APK for this device is skipped', () {
      expect(pickUpdate(releases, app(UpdateChannel.stable, '0.6.0', abis: ['x86'])), isNull);
    });

    test('the first supported ABI with an APK wins', () {
      final multi = [
        release('v0.7.0', pre: false, abis: ['armeabi-v7a', 'arm64-v8a']),
      ];
      final u = pickUpdate(multi, app(UpdateChannel.stable, '0.6.0', abis: ['arm64-v8a', 'armeabi-v7a']))!;
      expect(u.apk.name, 'noctua-stable-0.7.0-arm64-v8a.apk');
    });
  });

  test('checksumFor reads sha256sum output', () {
    const sums = 'abc123  noctua-stable-0.7.0-arm64-v8a.apk\nDEF456 *noctua-stable-0.7.0-x86_64.apk\n';
    expect(checksumFor(sums, 'noctua-stable-0.7.0-arm64-v8a.apk'), 'abc123');
    expect(checksumFor(sums, 'noctua-stable-0.7.0-x86_64.apk'), 'def456');
    expect(checksumFor(sums, 'missing.apk'), isNull);
  });
}
```

The data test runs the real `ReleasesRepository` against a Dio whose HTTP adapter answers from a string, so it checks the URL, the headers and the error mapping without touching GitHub:

```dart
// Data: turning GitHub's JSON and HTTP errors into the app's types.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctua/src/features/app_update/data/releases_repository.dart';

/// Answers every request with [status] and [body], with no network.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);
  final int status;
  final String body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ReleasesRepository _repo(_CannedAdapter adapter) => ReleasesRepository(Dio()..httpClientAdapter = adapter);

void main() {
  test('parseReleases keeps versions, drops drafts and other tags, newest first', () {
    const body = '''[
      {"tag_name": "v0.6.1", "name": "", "body": "x", "prerelease": false, "draft": false, "published_at": "2026-10-28T00:00:00Z", "html_url": "u", "assets": []},
      {"tag_name": "v0.7.0-beta.1", "name": "Beta", "body": "", "prerelease": true, "draft": false, "published_at": "2026-11-01T00:00:00Z", "html_url": "u",
       "assets": [{"name": "SHA256SUMS.txt", "browser_download_url": "s", "size": 10}]},
      {"tag_name": "v0.8.0", "draft": true},
      {"tag_name": "nightly", "draft": false}
    ]''';
    final r = parseReleases(body);
    expect(r.map((e) => '${e.version}'), ['0.7.0-beta.1', '0.6.1']);
    expect(r.last.title, 'Noctua 0.6.1');
    expect(r.first.checksums?.url, 's');
  });

  test('fetchReleases calls the releases API and parses the reply', () async {
    final adapter = _CannedAdapter(
      200,
      jsonEncode([
        {'tag_name': 'v0.6.1', 'name': 'Noctua 0.6.1', 'prerelease': false, 'published_at': '2026-10-28T00:00:00Z', 'assets': <Object>[]},
      ]),
    );
    final releases = await _repo(adapter).fetchReleases();
    expect(releases.single.version.toString(), '0.6.1');
    expect(adapter.last!.uri.path, endsWith('/releases'));
    expect(adapter.last!.headers['X-GitHub-Api-Version'], '2022-11-28');
  });

  test('rate limiting becomes a ReleaseCheckException a user can act on', () async {
    final adapter = _CannedAdapter(403, '{"message": "API rate limit exceeded"}');
    expect(
      _repo(adapter).fetchReleases(),
      throwsA(isA<ReleaseCheckException>().having((e) => e.message, 'message', contains('Try again in an hour'))),
    );
  });
}
```

> [!success] Checkpoint
> install the latest `noctua-beta-0.1.0-beta.N-arm64-v8a.apk` from its release on a phone. Push any change to `develop`, wait for the beta workflow, then reopen the app: a snackbar offers the new beta, the page shows the generated release notes, and Download and install ends in Android’s installer. After installing, the app reports the new beta number.

![[noctua-m03-updates.png]]
*Milestone 3: the launch-time offer, the update page with release notes, and a download in progress*

---
← [[Milestone 02 - Release pipeline for beta and stable]] · [[00 Index|Index]] · [[Milestone 04 - Preferences and the local database]] →
