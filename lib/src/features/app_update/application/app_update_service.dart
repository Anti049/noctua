import 'package:noctua/src/core/constants/app_config.dart';
import 'package:noctua/src/features/app_update/data/apk_installer.dart';
import 'package:noctua/src/features/app_update/data/installed_app_reader.dart';
import 'package:noctua/src/features/app_update/data/releases_repository.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
import 'package:noctua/src/features/app_update/domain/install_progress.dart';
import 'package:noctua/src/features/app_update/domain/update_check_result.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_update_service.g.dart';

class AppUpdateService {
  AppUpdateService(this.ref);
  final Ref ref;

  /// Play Store builds update through the store, so the updater is off.
  bool get enabled => !kIsPlayStoreBuild;

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

/// Kept alive: callers only `ref.read` it, so an auto-dispose provider would be
/// disposed mid-`await` and the service's [Ref] would throw on its next use.
@Riverpod(keepAlive: true)
AppUpdateService appUpdateService(Ref ref) => AppUpdateService(ref);
