import 'package:flutter_test/flutter_test.dart';
import 'package:agro_alerta/main.dart';

void main() {
  testWidgets('AgroAlerta Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AgroAlertaApp());

    // Verify that the login screen renders successfully
    expect(find.text('Bem-vindo de volta!'), findsOneWidget);
    expect(find.text('E-MAIL'), findsOneWidget);
    expect(find.text('ACESSAR CONTA'), findsOneWidget);
  });
}
