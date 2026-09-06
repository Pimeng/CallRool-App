import 'package:callrool_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('首次启动使用内置名单', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RollCallApp());
    await tester.pumpAndSettle();

    expect(find.text('点名册'), findsOneWidget);
    for (final name in [
      '刘一',
      '陈二',
      '张三',
      '李四',
      '王五',
      '赵六',
      '孙七',
      '周八',
      '吴九',
      '郑十',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('名单还是空的'), findsNothing);
  });
}
