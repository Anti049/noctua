import 'package:auto_route/auto_route.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:material_ui/material_ui.dart';

part 'shell_page.freezed.dart';

@freezed
abstract class ShellPage with _$ShellPage {
  const ShellPage._();
  const factory ShellPage({required String label, PageRouteInfo? route, Widget? content, IconData? icon, List<Widget>? actions}) =
      _ShellPage;

  Icon get unselectedIcon => Icon(icon, fill: 0.0);
  Icon get selectedIcon => Icon(icon, fill: 1.0);

  NavigationDestination get barDestination => NavigationDestination(label: label, icon: unselectedIcon, selectedIcon: selectedIcon);

  NavigationRailDestination get railDestination =>
      NavigationRailDestination(icon: unselectedIcon, selectedIcon: selectedIcon, label: Text(label));

  NavigationDrawerDestination get drawerDestination =>
      NavigationDrawerDestination(icon: unselectedIcon, selectedIcon: selectedIcon, label: Text(label));

  Tab get tabDestination => Tab(text: label);
}
