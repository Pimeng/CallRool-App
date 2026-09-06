import 'package:callrool_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('首次启动使用内置名单', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RollCallApp());
    await tester.pumpAndSettle();

    expect(find.text('快捷考勤'), findsOneWidget);
    expect(find.text('刘一'), findsOneWidget);
    expect(find.text('名单还是空的'), findsNothing);

    final saved = SharedPreferences.getInstance().then(
      (prefs) => prefs.getString('roll_call_people_v1'),
    );
    expect(await saved, contains('郑十'));
  });
}
