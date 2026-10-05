import 'package:flutter_test/flutter_test.dart';
import 'package:whah_ai/main.dart';

void main() {
  testWidgets('Waha AI app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const WahaAI());

    expect(find.byType(WahaAI), findsOneWidget);
  });
}
