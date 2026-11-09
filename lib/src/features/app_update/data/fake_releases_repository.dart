import 'package:noctua/src/core/constants/app_config.dart';
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
      notes: '## What’s Changed\n* Reader: chapters sheet without leaving the page\n* Save prompt for works you keep reading\n* Fix covers stretching on tablets\n',
      prerelease: true,
      publishedAt: DateTime.utc(2026, 11, 4),
      pageUrl: 'https://github.com/$kGitHubRepo/releases/tag/v0.7.0-beta.2',
      assets: [..._assets('beta', '0.7.0-beta.2')],
    ),
    AppRelease(
      version: const AppVersion(0, 6, 1),
      title: 'Noctua 0.6.1',
      notes: '## What’s Changed\n* Mihon themes and pure black dark mode\n* Feature tour and coach marks\n* Fix the library opening with demo filters on\n',
      prerelease: false,
      publishedAt: DateTime.utc(2026, 10, 28),
      pageUrl: 'https://github.com/$kGitHubRepo/releases/tag/v0.6.1',
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
