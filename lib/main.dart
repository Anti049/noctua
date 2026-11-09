import 'package:flutter/services.dart' show appFlavor, SystemChrome, SystemUiMode, SystemUiOverlay;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/flavors.dart';
import 'package:noctua/src/app.dart';
import 'package:noctua/src/core/router/app_router.dart';
import 'package:noctua/src/core/router/crash_guard.dart';
import 'package:noctua/src/features/app_update/data/installed_app_reader.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Enable edge-to-edge mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);

  // Preserve the splash screen until the app is ready
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Set the app flavor based on the build configuration
  F.appFlavor = Flavor.values.asNameMap()[appFlavor] ?? Flavor.stable;

  // TODO: Read preferences before the first frame

  // TODO: Load the dynamic theme before the first frame

  // Get installed application information
  final installed = await readInstalledApp();

  final router = AppRouter();
  CrashGuard.install(router);

  // Run the app with a ProviderScope to manage state
  runApp(
    ProviderScope(
      overrides: [
        // Override the installed app provider with the actual installed app information
        installedAppProvider.overrideWithValue(installed),
      ],
      child: NoctuaApp(router: router),
    ),
  );

  // Remove the splash screen after the app has been initialized
  FlutterNativeSplash.remove();
}
