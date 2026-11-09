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
