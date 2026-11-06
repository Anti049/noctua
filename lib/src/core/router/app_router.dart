import 'package:auto_route/auto_route.dart';

import 'package:noctua/src/core/router/app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen|Page|Tab,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    // TODO: Add routes
    AutoRoute(
      page: HomeShellRoute.page,
      initial: true,
      path: '/',
      children: [
        // Library
        AutoRoute(path: 'library', page: LibraryRoute.page),
        // Updates
        AutoRoute(path: 'updates', page: UpdatesRoute.page),
        // Browse
        AutoRoute(
          path: 'browse',
          page: BrowseRoute.page,
          children: [
            // Browse -> Subroutes
            AutoRoute(path: 'sources', page: SourcesRoute.page),
            AutoRoute(path: 'extensions', page: ExtensionsRoute.page),
            AutoRoute(path: 'migrate', page: MigrateRoute.page),
          ],
        ),
        // History
        AutoRoute(path: 'history', page: HistoryRoute.page),
        // More
        AutoRoute(path: 'more', page: MoreRoute.page),
      ],
    ),
  ];
}
