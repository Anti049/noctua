import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/widgets/empty_placeholder.dart';

@RoutePage()
class UpdatesTab extends ConsumerStatefulWidget {
  const UpdatesTab({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends ConsumerState<UpdatesTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: const Center(child: EmptyPlaceholder(message: 'Updates Not Implemented')),
    );
  }
}
