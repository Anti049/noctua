import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/router/app_router.gr.dart';
import 'package:noctua/src/core/widgets/empty_placeholder.dart';

@RoutePage()
class MoreTab extends ConsumerStatefulWidget {
  const MoreTab({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _MoreTabState();
}

class _MoreTabState extends ConsumerState<MoreTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: EmptyPlaceholder(
          message: 'More Not Implemented',
          actions: [
            ElevatedButton(
              onPressed: () {
                context.router.push(const AppUpdateRoute());
              },
              child: const Text('Check for Update'),
            ),
          ],
        ),
      ),
    );
  }
}
