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
