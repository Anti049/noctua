import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/router/app_router.gr.dart';
import 'package:noctua/src/core/utils/shell_page.dart';
import 'package:noctua/src/core/widgets/padded_app_bar.dart';

@RoutePage()
class BrowseTab extends ConsumerStatefulWidget {
  const BrowseTab({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BrowseTabState();
}

class _BrowseTabState extends ConsumerState<BrowseTab> {
  static const _destinations = [
    ShellPage(label: 'Sources', route: SourcesRoute()),
    ShellPage(label: 'Extensions', route: ExtensionsRoute()),
    ShellPage(label: 'Migrate', route: MigrateRoute()),
  ];

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter.tabBar(
      routes: _destinations.map((item) => item.route!).toList(),
      builder: (context, child, controller) {
        final router = AutoTabsRouter.of(context);

        return BannerScaffold(
          appBar: PaddedAppBar(
            title: const Text('Browse'),
            actions: _destinations[router.activeIndex].actions,
            bottom: TabBar(controller: controller, tabs: _destinations.map((item) => item.tabDestination).toList()),
          ),
          body: child,
        );
      },
    );
  }
}
