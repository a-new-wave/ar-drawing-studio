import 'package:flutter_test/flutter_test.dart';
import 'package:ar_drawing_studio/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ARDrawingStudio(isFirstLaunch: true));

    // Verify that onboarding is shown (Welcome to AR Studio)
    expect(find.text('Welcome to AR Studio'), findsOneWidget);
  });
}
