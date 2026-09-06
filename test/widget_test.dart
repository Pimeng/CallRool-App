import 'package:callrool_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(WidgetTester tester, {Size? size}) async {
  if (size != null) {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const RollCallApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首次启动使用内置名单', (tester) async {
    await _pumpApp(tester);

    expect(find.text('快捷考勤'), findsOneWidget);
    expect(find.text('刘一'), findsOneWidget);
    expect(find.text('名单还是空的'), findsNothing);

    final saved = SharedPreferences.getInstance().then(
      (prefs) => prefs.getString('roll_call_people_v1'),
    );
    expect(await saved, contains('郑十'));
  });

  testWidgets('缺勤与请假使用独立筛选', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('选择缺勤类型').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('公假'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, '缺勤'));
    await tester.pumpAndSettle();
    expect(find.text('在“缺勤”筛选下没有匹配人员'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '请假'));
    await tester.pumpAndSettle();
    expect(find.text('刘一'), findsOneWidget);
  });

  testWidgets('筛选变化会取消筛选外人员的批量选择', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('批量选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刘一'));
    await tester.pumpAndSettle();
    expect(find.text('1人'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '正常'));
    await tester.pumpAndSettle();
    expect(find.text('0人'), findsOneWidget);
    expect(find.text('已取消 1 名筛选外人员的选择'), findsOneWidget);
  });

  testWidgets('复制未完成考勤前显示提醒', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('复制考勤情况'));
    await tester.pumpAndSettle();
    expect(find.text('还有 10 人未点名'), findsOneWidget);
    expect(find.text('继续复制'), findsOneWidget);
  });

  testWidgets('替换名单需要二次确认且追加是主操作', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('名单操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入名单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '新同学');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '追加'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '替换现有'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '替换现有'));
    await tester.pumpAndSettle();
    expect(find.text('确认替换现有名单？'), findsOneWidget);
  });

  testWidgets('320 宽度顶部栏不溢出', (tester) async {
    await _pumpApp(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
  });
}
