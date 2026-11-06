import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/constants/user_interface.dart';
import 'package:noctua/src/core/utils/theming.dart';

class BannerScaffold extends ConsumerWidget {
  const BannerScaffold({super.key, this.appBar, this.body, this.floatingActionButton});

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(primary: true, appBar: appBar, body: body, floatingActionButton: floatingActionButton);
  }
}

class PaddedAppBar extends ConsumerWidget implements PreferredSizeWidget {
  PaddedAppBar({
    super.key,
    this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.bottom,
    this.primary = true,
    this.backgroundColor,
    this.foregroundColor,
    this.visible,
    this.elevated = false,
    this.scrollable = true,
    this.surface = false,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
  });

  final Widget? title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool primary;
  final MenuController _menuController = MenuController();
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool? visible;
  final bool elevated;
  final bool scrollable;
  final bool surface;
  final bool automaticallyImplyLeading;
  final bool centerTitle;

  bool get needsPadding {
    if (actions == null) return false;
    if (actions!.isEmpty) return false;
    if (actions![actions!.length - 1] is SizedBox) return false;
    return true;
  }

  List<Widget> get _actions {
    if (actions == null) return [];
    if (actions!.length <= kAppbarActions) return actions ?? [];
    return [
      ...actions!.sublist(0, kAppbarActions),
      MenuAnchor(
        controller: _menuController,
        menuChildren: actions!.sublist(kAppbarActions).map((e) {
          if (e is! IconButton) return e;
          return MenuItemButton(
            onPressed: e.onPressed,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text(e.tooltip ?? 'TOOLTIP')),
          );
        }).toList(),
        child: IconButton(
          icon: const Icon(Symbols.more_vert),
          onPressed: () {
            _menuController.toggle();
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      primary: true,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: centerTitle,
      title: subtitle != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title ?? const SizedBox(),
                Text(subtitle ?? '', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.normal)),
              ],
            )
          : title,
      actions: [..._actions, if (needsPadding) const SizedBox(width: 8.0)],
      leading: leading,
      bottom: bottom,
      backgroundColor: surface ? context.theme.scaffoldBackgroundColor : backgroundColor,
      foregroundColor: foregroundColor,
      elevation: elevated ? 4.0 : 0.0,
      scrolledUnderElevation: scrollable ? 4.0 : 0.0,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}

extension on MenuController {
  void toggle() {
    if (isOpen) {
      close();
    } else {
      open();
    }
  }
}
