import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/widgets/empty_placeholder.dart';

@RoutePage()
class SourcesTab extends ConsumerStatefulWidget {
  const SourcesTab({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SourcesTabState();
}

class _SourcesTabState extends ConsumerState<SourcesTab> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: EmptyPlaceholder(message: 'Sources Not Implemented')),
    );
  }
}
