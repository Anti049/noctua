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
