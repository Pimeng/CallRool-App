import 'package:callrool_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('空名单显示导入入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RollCallApp());
    await tester.pumpAndSettle();

    expect(find.text('点名册'), findsOneWidget);
    expect(find.text('名单还是空的'), findsOneWidget);
    expect(find.text('导入名单'), findsWidgets);
  });
}
