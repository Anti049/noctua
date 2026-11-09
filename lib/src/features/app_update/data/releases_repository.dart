import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:noctua/src/core/constants/app_config.dart';
import 'package:noctua/src/core/network/dio_provider.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
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
        'https://api.github.com/repos/$kGitHubRepo/releases',
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
        pageUrl: raw['html_url'] as String? ?? 'https://github.com/$kGitHubRepo/releases',
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
