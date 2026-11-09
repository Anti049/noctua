import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/constants/app_config.dart';
import 'package:noctua/src/core/router/app_router.gr.dart';
import 'package:noctua/src/core/utils/theming.dart';
import 'package:noctua/src/features/app_update/data/installed_app_reader.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';
import 'package:noctua/src/features/app_update/domain/install_progress.dart';
import 'package:noctua/src/features/app_update/presentation/app_update_controller.dart';
import 'package:noctua/src/features/app_update/presentation/widgets/release_notes.dart';
import 'package:url_launcher/url_launcher.dart';

String _date(DateTime d) =>
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.day}, ${d.year}';

/// Check for updates, read what changed, then download and install.
@RoutePage()
class AppUpdatePage extends ConsumerStatefulWidget {
  const AppUpdatePage({super.key});

  @override
  ConsumerState<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends ConsumerState<AppUpdatePage> {
  @override
  void initState() {
    super.initState();
    // Opening the page always shows fresh results.
    Future.microtask(() => ref.read(appUpdateControllerProvider.notifier).check());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final app = ref.watch(installedAppProvider);
    final check = ref.watch(appUpdateControllerProvider);

    Widget header(String title, String subtitle, IconData icon) => Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: c.primaryContainer,
          child: Icon(icon, color: c.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleLarge),
              Text(subtitle, style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );

    final installed = 'You have ${app.versionName} · ${app.channel.label} channel';
    final List<Widget> body;
    if (kIsPlayStoreBuild) {
      body = [header('Updates come from Google Play', installed, Symbols.shop_rounded)];
    } else {
      body = switch (check) {
        AsyncError(:final error) => [
          header('Couldn’t check for updates', installed, Symbols.cloud_off_rounded),
          const SizedBox(height: 16),
          Text('$error', style: context.text.bodyMedium),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => ref.read(appUpdateControllerProvider.notifier).check(), child: const Text('Try again')),
        ],
        AsyncData(value: final result?) when result.update != null => _available(context, result.update!, installed),
        AsyncData(value: final result?) => [
          header('You’re up to date', installed, Symbols.check_circle_rounded),
          const SizedBox(height: 8),
          Text(
            'Checked ${TimeOfDay.fromDateTime(result.checkedAt).format(context)} against GitHub Releases.',
            style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => ref.read(appUpdateControllerProvider.notifier).check(), child: const Text('Check again')),
        ],
        _ => [
          header('Checking for updates…', installed, Symbols.sync_rounded),
          const SizedBox(height: 24),
          const LinearProgressIndicator(),
        ],
      };
    }

    return Scaffold(
      appBar: AppBar(title: const Text('App updates')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ...body,
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.router.push(const ChangelogRoute()), child: const Text('All releases')),
        ],
      ),
    );
  }

  List<Widget> _available(BuildContext context, AvailableUpdate u, String installed) {
    final c = context.colors;
    final p = ref.watch(installControllerProvider);
    final busy = p != null && (p.stage == InstallStage.downloading || p.stage == InstallStage.installing);
    return [
      Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: c.primaryContainer,
            child: Icon(Symbols.system_update_rounded, color: c.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.release.title, style: context.text.titleLarge),
                Text(
                  '$installed\n${_date(u.release.publishedAt)} · ${u.apk.sizeLabel}${u.release.prerelease ? ' · pre-release' : ''}',
                  style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ReleaseNotes(u.release.notes),
      const SizedBox(height: 24),
      if (busy) ...[
        LinearProgressIndicator(value: p.stage == InstallStage.installing ? null : p.percent / 100),
        const SizedBox(height: 8),
        Text(p.stage == InstallStage.installing ? 'Opening the installer…' : 'Downloading · ${p.percent}%', style: context.text.bodySmall),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: ref.read(installControllerProvider.notifier).cancel, child: const Text('Cancel')),
      ] else ...[
        if (p?.stage == InstallStage.failed) ...[
          Text(p!.error ?? 'The update couldn’t be installed.', style: context.text.bodyMedium?.copyWith(color: c.error)),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: () => ref.read(installControllerProvider.notifier).install(u),
          child: Text('Download and install · ${u.apk.sizeLabel}'),
        ),
      ],
      TextButton(
        onPressed: () => launchUrl(Uri.parse(u.release.pageUrl), mode: LaunchMode.externalApplication),
        child: const Text('View on GitHub'),
      ),
    ];
  }
}

/// Every published release, newest first, from the same check.
@RoutePage()
class ChangelogPage extends ConsumerStatefulWidget {
  const ChangelogPage({super.key});

  @override
  ConsumerState<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends ConsumerState<ChangelogPage> {
  final _open = <String>{};

  @override
  void initState() {
    super.initState();
    if (ref.read(appUpdateControllerProvider).value == null) {
      Future.microtask(() => ref.read(appUpdateControllerProvider.notifier).check());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final app = ref.watch(installedAppProvider);
    final check = ref.watch(appUpdateControllerProvider);
    final releases = [
      for (final r in check.value?.releases ?? const <AppRelease>[])
        if (app.channel == UpdateChannel.beta || !r.prerelease) r,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Changelog')),
      body: switch (check) {
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$error', textAlign: TextAlign.center),
          ),
        ),
        AsyncData(value: _?) when releases.isEmpty => const Center(child: Text('No releases yet.')),
        AsyncData(value: _?) => ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: releases.length,
          itemBuilder: (context, i) {
            final r = releases[i];
            final key = '${r.version}';
            final open = _open.contains(key) || i == 0;
            final installed = r.version.code == app.versionCode;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(r.title),
                  subtitle: Text('${_date(r.publishedAt)}${r.prerelease ? ' · beta' : ''}${installed ? ' · installed' : ''}'),
                  trailing: Icon(open ? Symbols.expand_less_rounded : Symbols.expand_more_rounded),
                  onTap: () => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key)),
                ),
                if (open) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: ReleaseNotes(r.notes)),
                Divider(color: c.outlineVariant, height: 1),
              ],
            );
          },
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
