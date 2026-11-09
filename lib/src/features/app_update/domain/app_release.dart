// Update channel enum
import 'package:dartx/dartx.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_release.freezed.dart';

enum UpdateChannel {
  stable,
  beta;

  String get label => name.capitalize();
}

@freezed
abstract class AppVersion with _$AppVersion implements Comparable<AppVersion> {
  const factory AppVersion(int major, int minor, int patch, [int? beta]) = _AppVersion;
  const AppVersion._();

  static final _pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$');

  static AppVersion? tryParse(String input) {
    final match = _pattern.firstMatch(input.trim());
    if (match == null) return null;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);
    final beta = match.group(4) != null ? int.parse(match.group(4)!) : null;
    return AppVersion(major, minor, patch, beta);
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

extension on AppVersion {
  bool operator >(AppVersion other) => compareTo(other) > 0;
}

/// Reads the hash for [fileName] from a `sha256sum` listing.
String? checksumFor(String sha256sums, String fileName) {
  for (final line in sha256sums.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+\*?'));
    if (parts.length == 2 && parts[1] == fileName) return parts[0].toLowerCase();
  }
  return null;
}
