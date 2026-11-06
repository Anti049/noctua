import 'package:flutter/foundation.dart';
import 'package:noctua/src/core/router/app_router.dart';

abstract final class CrashGuard {
  static AppRouter? _router;
  static bool _showing = false;

  static void install(AppRouter router) {
    _router = router;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (kReleaseMode) report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true;
    };
  }

  static void report(Object error, StackTrace? stack) {
    final router = _router;
    if (router == null || _showing) return;
    _showing = true;
    // Defer: the error may have been thrown mid-build.
    // TODO: Add crash route
    // Future(() => router.replaceAll([CrashRoute(error: error.toString(), stack: stack?.toString() ?? '')]));
  }

  /// Called when the user leaves the crash screen.
  static void reset() => _showing = false;
}
