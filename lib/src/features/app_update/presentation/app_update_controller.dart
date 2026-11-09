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
