import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:noctua/src/core/router/app_router.gr.dart';
import 'package:noctua/src/features/app_update/presentation/app_update_controller.dart';

/// Runs the launch-time update check and offers a found update once.
/// Wraps the home shell, so it starts with the first screen users see.
class AppUpdateListener extends ConsumerStatefulWidget {
  const AppUpdateListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppUpdateListener> createState() => _AppUpdateListenerState();
}

class _AppUpdateListenerState extends ConsumerState<AppUpdateListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launchCheck());
  }

  /// Only the automatic launch check offers the update; checks started from
  /// the update page or About show their result there instead.
  Future<void> _launchCheck() async {
    final checker = ref.read(appUpdateControllerProvider.notifier);
    if (!await checker.checkIfDue() || !mounted) return;
    final update = ref.read(appUpdateControllerProvider).value?.update;
    if (update == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Text('${update.release.title} is available'),
        action: SnackBarAction(label: 'View', onPressed: () => context.router.push(const AppUpdateRoute())),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Update available" row for About and More; empty when there's nothing to install.
class UpdateAvailableTile extends ConsumerWidget {
  const UpdateAvailableTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateControllerProvider).value?.update;
    if (update == null) return const SizedBox.shrink();
    return ListTile(
      leading: Icon(Symbols.system_update_rounded, color: Theme.of(context).colorScheme.primary),
      title: Text('Update available: ${update.release.version}'),
      subtitle: Text('${update.apk.sizeLabel}${update.release.prerelease ? ' · beta' : ''}'),
      trailing: FilledButton(onPressed: () => context.router.push(const AppUpdateRoute()), child: const Text('View')),
      onTap: () => context.router.push(const AppUpdateRoute()),
    );
  }
}
