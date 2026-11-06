import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/flavors.dart';
import 'package:noctua/src/core/router/app_router.dart';
import 'package:noctua/src/core/router/app_router.gr.dart';
import 'package:noctua/src/core/utils/responsive_layout.dart';
import 'package:responsive_framework/responsive_framework.dart';

class NoctuaApp extends ConsumerStatefulWidget {
  const NoctuaApp({super.key, required this.router});

  final AppRouter router;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _NoctuaAppState();
}

class _NoctuaAppState extends ConsumerState<NoctuaApp> {
  late final _routerConfig = widget.router.config(deepLinkBuilder: (_) => DeepLink.single(const HomeShellRoute()));

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: F.title,
      debugShowCheckedModeBanner: false,
      routerConfig: _routerConfig,
      builder: (context, child) => ResponsiveBreakpoints.builder(child: child!, breakpoints: WindowSize.breakpoints),
    );
  }
}
