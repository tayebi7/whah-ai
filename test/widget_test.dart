import 'package:flutter_test/flutter_test.dart';
import 'package:whah_ai/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const WahaAI());
    expect(find.textContaining('WHAH'), findsWidgets);
  });
}
