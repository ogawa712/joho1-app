import 'package:flutter_test/flutter_test.dart';
import 'package:joho1_app/main.dart';

void main() {
  testWidgets('Joho1App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const Joho1App());
    expect(find.byType(Joho1App), findsOneWidget);
  });
}
