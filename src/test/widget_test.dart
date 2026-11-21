import 'package:cerebrum/common/themes/theme_provider.dart';
import 'package:cerebrum/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CerebrumApp builds', (WidgetTester tester) async {
    final themeProvider = ThemeProvider();
    await themeProvider.load();
    await tester.pumpWidget(CerebrumApp(themeProvider: themeProvider));
    await tester.pump();
    expect(find.byType(CerebrumApp), findsOneWidget);
  });
}
