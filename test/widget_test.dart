import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctua/flavors.dart';
import 'package:noctua/src/app.dart';
import 'package:noctua/src/core/router/app_router.dart';

void main() {
  setUpAll(() {
    // F.appFlavor is late final, so it can only be set once per test run.
    F.appFlavor = Flavor.stable;
  });

  test('stable flavor uses the release app title', () {
    expect(F.title, 'Noctua');
  });

  testWidgets('NoctuaApp opens on the Library tab', (tester) async {
    await tester.pumpWidget(ProviderScope(child: NoctuaApp(router: AppRouter())));
    await tester.pumpAndSettle();

    expect(find.text('Library Not Implemented'), findsOneWidget);
  });
}
