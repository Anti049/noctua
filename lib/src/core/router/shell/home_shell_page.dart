import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/router/app_router.gr.dart';
import 'package:noctua/src/core/utils/responsive_layout.dart';
import 'package:noctua/src/core/utils/shell_page.dart';
import 'package:noctua/src/core/utils/theming.dart';
import 'package:noctua/src/core/widgets/themed_logo.dart';

@RoutePage()
class HomeShellPage extends ConsumerWidget {
  const HomeShellPage({super.key});

  static const _destinations = [
    ShellPage(label: 'Library', route: LibraryRoute(), icon: Symbols.collections_bookmark),
    ShellPage(label: 'Updates', route: UpdatesRoute(), icon: Symbols.release_alert),
    ShellPage(label: 'Browse', route: BrowseRoute(), icon: Symbols.explore),
    ShellPage(label: 'History', route: HistoryRoute(), icon: Symbols.history),
    ShellPage(label: 'More', route: MoreRoute(), icon: Symbols.more_horiz),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AutoTabsRouter(
      // Routes
      routes: _destinations.map((d) => d.route!).toList(),
      // Transition
      transitionBuilder: (context, child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      // Main navigation component
      builder: (context, child) {
        // Get sub-router
        final subRouter = context.tabsRouter;
        // Build navigation controls
        final navBar = NavigationBar(
          backgroundColor: context.colors.surfaceContainer,
          selectedIndex: subRouter.activeIndex,
          onDestinationSelected: subRouter.setActiveIndex,
          destinations: _destinations.map((item) => item.barDestination).toList(),
        );
        final navRail = NavigationRail(
          leading: const Column(mainAxisSize: MainAxisSize.min, children: [ThemedLogo(size: 56.0), SizedBox(height: 16.0)]),
          backgroundColor: context.colors.surfaceContainer,
          selectedIndex: subRouter.activeIndex,
          onDestinationSelected: subRouter.setActiveIndex,
          destinations: _destinations.map((item) => item.railDestination).toList(),
          labelType: context.atLeastExtraLarge ? NavigationRailLabelType.none : NavigationRailLabelType.all,
          extended: context.atLeastExtraLarge,
        );

        return Scaffold(
          body: Row(
            children: [
              if (context.atLeastMedium) navRail,
              Expanded(child: child),
            ],
          ),
          bottomNavigationBar: context.atLeastMedium ? null : navBar,
        );
      },
    );
  }
}
