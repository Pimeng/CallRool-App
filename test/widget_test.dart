import 'dart:convert';

import 'package:callrool_app/main.dart';
import 'package:callrool_app/models/attendance.dart';
import 'package:callrool_app/widgets/attendance_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(
  WidgetTester tester, {
  Size? size,
  Map<String, Object> initialValues = const {},
}) async {
  if (size != null) {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  SharedPreferences.setMockInitialValues(initialValues);
  await tester.pumpWidget(const RollCallApp());
  await tester.pumpAndSettle();
}

Future<void> _openCopyFormatEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('设置'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('自定义复制格式'));
  await tester.pumpAndSettle();
}

Future<void> _pumpDarkApp(WidgetTester tester) async {
  tester.binding.platformDispatcher.platformBrightnessTestValue =
      Brightness.dark;
  addTearDown(
    tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
  );
  await _pumpApp(tester);
}

String _scheduleForToday() {
  final now = DateTime.now();
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  final startDate = '${monday.year}-${monday.month}-${monday.day}';
  return [
    jsonEncode({'courseLen': 1440, 'id': 2, 'name': '全天'}),
    jsonEncode([
      {'endTime': '23:59', 'node': 1, 'startTime': '00:00', 'timeTable': 2},
    ]),
    jsonEncode({'maxWeek': 20, 'startDate': startDate, 'tableName': '测试课表'}),
    jsonEncode([
      {'courseName': '当前测试课程', 'id': 1, 'tableId': 2},
    ]),
    jsonEncode([
      {
        'day': now.weekday,
        'endTime': '',
        'endWeek': 20,
        'id': 1,
        'ownTime': false,
        'room': '测试教室',
        'startNode': 1,
        'startTime': '',
        'startWeek': 1,
        'step': 1,
        'tableId': 2,
        'teacher': '测试教师',
        'type': 0,
      },
    ]),
  ].join('\n');
}

void main() {
  testWidgets('移动端长按进入拖拽时提供触觉反馈', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    String? hapticType;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        hapticType = call.arguments as String?;
      }
      return null;
    });
    try {
      await _pumpApp(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('刘一')),
      );
      await tester.pump(const Duration(milliseconds: 801));

      expect(hapticType, 'HapticFeedbackType.selectionClick');
      await gesture.up();
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    }
  });

  testWidgets('跟随系统启用深色主题', (tester) async {
    await _pumpDarkApp(tester);

    final context = tester.element(find.byType(Scaffold));
    final theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0F1511));

    final personRow = find.ancestor(
      of: find.text('刘一'),
      matching: find.byType(PersonRow),
    );
    final rowMaterial = tester.widget<Material>(
      find.descendant(of: personRow, matching: find.byType(Material)).first,
    );
    expect(rowMaterial.color, isNot(Colors.white));
  });

  testWidgets('首次启动使用内置名单', (tester) async {
    await _pumpApp(tester);

    expect(find.text('快捷考勤喵'), findsOneWidget);
    expect(find.text('刘一'), findsOneWidget);
    expect(find.text('名单还是空的'), findsNothing);

    final saved = SharedPreferences.getInstance().then(
      (prefs) => prefs.getString('roll_call_people_v1'),
    );
    expect(await saved, contains('郑十'));
  });

  testWidgets('异常与请假使用独立筛选', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('选择异常考勤状态').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('公假'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, '异常'));
    await tester.pumpAndSettle();
    expect(find.text('在“异常”筛选下没有匹配人员'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '请假'));
    await tester.pumpAndSettle();
    expect(find.text('刘一'), findsOneWidget);
  });

  testWidgets('筛选中点名后显示姓名并可撤销', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.widgetWithText(FilterChip, '未点名'));
    await tester.pumpAndSettle();

    final liuYiRow = find.ancestor(
      of: find.text('刘一'),
      matching: find.byType(PersonRow),
    );
    await tester.tap(
      find.descendant(of: liuYiRow, matching: find.byTooltip('正常')),
    );
    await tester.pumpAndSettle();

    expect(find.text('刘一'), findsNothing);
    expect(find.text('已将 刘一 标记为正常'), findsOneWidget);

    await tester.tap(find.text('撤销'));
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

  testWidgets('从设置页打开自定义格式编辑器', (tester) async {
    await _pumpApp(tester);

    await _openCopyFormatEditor(tester);

    expect(find.widgetWithText(AppBar, '自定义复制格式'), findsOneWidget);
    for (final variable in [
      '课程',
      '老师',
      '应出勤人数',
      '实际出勤人数',
      '请假名单',
      '请假人数',
      '旷课名单',
      '旷课人数',
      '迟到名单',
      '迟到人数',
      '早退名单',
      '早退人数',
      '教室',
    ]) {
      expect(find.widgetWithText(ActionChip, variable), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('copy-format-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('copy-format-preview')), findsOneWidget);
  });

  testWidgets('复制格式变量可以拖入编辑框', (tester) async {
    await _pumpApp(tester);
    await _openCopyFormatEditor(tester);

    final editorFinder = find.byKey(const ValueKey('copy-format-editor'));
    final editor = tester.widget<TextField>(editorFinder);
    editor.controller!.clear();
    await tester.pump();

    final variable = find.widgetWithText(ActionChip, '课程');
    await tester.dragFrom(
      tester.getCenter(variable),
      tester.getCenter(editorFinder) - tester.getCenter(variable),
    );
    await tester.pumpAndSettle();

    expect(editor.controller!.text, '{{课程}}');
  });

  testWidgets('复制格式变量插入到实际拖拽落点', (tester) async {
    await _pumpApp(tester);
    await _openCopyFormatEditor(tester);

    final editorFinder = find.byKey(const ValueKey('copy-format-editor'));
    final editor = tester.widget<TextField>(editorFinder);
    editor.controller!.value = const TextEditingValue(
      text: '尾部',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.pump();

    final variable = find.widgetWithText(ActionChip, '课程');
    final dropPoint = tester.getTopLeft(editorFinder) + const Offset(18, 42);
    await tester.dragFrom(
      tester.getCenter(variable),
      dropPoint - tester.getCenter(variable),
    );
    await tester.pumpAndSettle();

    expect(editor.controller!.text, '{{课程}}尾部');
  });

  testWidgets('自定义格式在复制时替换课程和考勤变量', (tester) async {
    String? copiedText;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    SharedPreferences.setMockInitialValues({
      'wakeup_schedule_data_v1': _scheduleForToday(),
      'attendance_copy_template_v2':
          '{{课程}}|{{老师}}|{{应出勤人数}}|{{实际出勤人数}}|{{请假名单}}|{{教室}}',
    });
    await tester.pumpWidget(const RollCallApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('复制考勤情况'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续复制'));
    await tester.pumpAndSettle();

    expect(copiedText, startsWith('当前测试课程|测试教师|10|0|无|测试教室'));
    expect(copiedText, contains('未点名（10人）'));
  });

  testWidgets('名单与人数变量分别输出状态人员和数量', (tester) async {
    String? copiedText;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    SharedPreferences.setMockInitialValues({
      'roll_call_people_v1': jsonEncode([
        {'id': 1, 'name': '刘一', 'status': 'leave'},
        {'id': 2, 'name': '陈二', 'status': 'personalLeave'},
        {'id': 3, 'name': '张三', 'status': 'truancy'},
        {'id': 4, 'name': '李四', 'status': 'late'},
        {'id': 5, 'name': '王五', 'status': 'earlyLeave'},
      ]),
      'attendance_copy_template_v2':
          '{{请假名单}}|{{请假人数}}|{{旷课名单}}|{{旷课人数}}|'
          '{{迟到名单}}|{{迟到人数}}|{{早退名单}}|{{早退人数}}',
    });
    await tester.pumpWidget(const RollCallApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('复制考勤情况'));
    await tester.pumpAndSettle();

    expect(copiedText, '刘一、陈二|2|张三|1|李四|1|王五|1');
  });

  testWidgets('设置入口打开独立二级页面', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
    expect(find.text('名单'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('课程表'), findsOneWidget);
    expect(find.text('导入名单'), findsOneWidget);
    expect(find.text('导出名单'), findsOneWidget);
    expect(find.text('自定义复制格式'), findsOneWidget);
    expect(find.text('同步 WakeUp 课程表'), findsOneWidget);
    expect(find.text('复制考勤情况'), findsNothing);
    expect(find.text('未点名全部标记为旷课'), findsNothing);
    expect(find.text('重置考勤'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('快捷考勤喵'), findsOneWidget);
  });

  testWidgets('复制考勤时写入当前课程', (tester) async {
    String? copiedText;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    SharedPreferences.setMockInitialValues({
      'wakeup_schedule_data_v1': _scheduleForToday(),
    });
    await tester.pumpWidget(const RollCallApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('复制考勤情况'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续复制'));
    await tester.pumpAndSettle();

    expect(copiedText, contains('当前课程：当前测试课程｜测试教师｜测试教室｜00:00-23:59'));
  });

  testWidgets('课程表同步支持粘贴 WakeUp 完整分享口令', (tester) async {
    await _pumpApp(
      tester,
      initialValues: const {'wakeup_auth_token_v1': 'saved-token'},
    );

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步 WakeUp 课程表'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '同步 WakeUp 课程表'), findsOneWidget);
    expect(find.text('可直接粘贴完整分享口令，不会保存'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '预览课程'), findsOneWidget);

    final authTokenButton = find.byTooltip('设置 authToken');
    if (authTokenButton.evaluate().isNotEmpty) {
      await tester.tap(authTokenButton);
      await tester.pumpAndSettle();
      expect(find.text('authToken'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }

    final shareCodeField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'shareCode 或 WakeUp 分享口令',
    );
    const message =
        '这是来自「WakeUp课程表」的课表分享，分享口令为「ffffbf0619574371bd27364855407d8f」';
    await tester.enterText(shareCodeField, message);
    await tester.pump();

    final field = tester.widget<TextField>(shareCodeField);
    expect(field.obscureText, isFalse);
    expect(field.controller!.text, 'ffffbf0619574371bd27364855407d8f');
  });

  testWidgets('首次导入以替换为主操作且不二次确认', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入名单'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '导入名单'), findsOneWidget);
    expect(find.byTooltip('选择 TXT 文件'), findsOneWidget);
    expect(find.text('选择 TXT 文件'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '新同学');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '替换现有'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '追加'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '替换现有'));
    await tester.pumpAndSettle();
    expect(find.text('确认替换现有名单？'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('新同学'), findsOneWidget);
    expect(find.text('刘一'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('roll_call_has_imported_v1'), isTrue);
  });

  testWidgets('已有自定义名单时追加仍为主操作且替换需要确认', (tester) async {
    await _pumpApp(
      tester,
      initialValues: {
        'roll_call_people_v1': jsonEncode([
          {'id': 1, 'name': '已有同学', 'status': 'unmarked'},
        ]),
      },
    );

    await tester.tap(find.byTooltip('设置'));
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
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '导入名单'), findsOneWidget);
    final importField = tester.widget<TextField>(find.byType(TextField).last);
    expect(importField.controller!.text, '新同学');
  });

  testWidgets('追加名单时输入控制器保持到页面退出完成', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入名单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '新同学');
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '追加'));

    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    final saved = await SharedPreferences.getInstance().then(
      (prefs) => prefs.getString('roll_call_people_v1'),
    );
    expect(saved, contains('新同学'));
  });

  testWidgets('删除确认展示当前选中的完整名单', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('批量选择'));
    await tester.pumpAndSettle();
    for (final name in ['刘一', '陈二', '张三']) {
      await tester.tap(find.text(name));
      await tester.pump();
    }
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();

    expect(find.text('将要删除3人'), findsOneWidget);
    expect(find.text('刘一、陈二、张三 将会被删除，且连同他们目前的考勤状态一并删除，是否继续？'), findsOneWidget);
  });

  testWidgets('添加人员时可以选择初始考勤状态', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('添加人员'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '王小明');
    await tester.tap(find.byType(DropdownButtonFormField<AttendanceStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旷课').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    final saved = await SharedPreferences.getInstance().then(
      (prefs) => prefs.getString('roll_call_people_v1'),
    );
    expect(saved, contains('"name":"王小明","status":"truancy"'));
  });

  testWidgets('人员状态使用整行底色且异常菜单没有投影', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('选择异常考勤状态').first);
    await tester.pumpAndSettle();
    final menu = tester.widget<Material>(
      find.byKey(const ValueKey('attendance-exception-status-menu')),
    );
    expect(menu.elevation, 0);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('attendance-exception-status-menu')),
        matching: find.text('旷课'),
      ),
    );
    await tester.pumpAndSettle();

    final personRow = find.ancestor(
      of: find.text('刘一'),
      matching: find.byType(PersonRow),
    );
    final rowMaterial = tester.widget<Material>(
      find.descendant(of: personRow, matching: find.byType(Material)).first,
    );
    expect(rowMaterial.color, AttendanceStatus.truancy.softColor);
  });

  testWidgets('异常展开选单支持迟到早退和旷课', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('选择异常考勤状态').first);
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('attendance-exception-status-menu'));
    for (final status in ['迟到', '早退', '旷课']) {
      expect(
        find.descendant(of: menu, matching: find.text(status)),
        findsOneWidget,
      );
    }
    expect(find.descendant(of: menu, matching: find.text('缺勤')), findsNothing);

    await tester.tap(find.descendant(of: menu, matching: find.text('迟到')));
    await tester.pumpAndSettle();
    expect(find.text('迟到'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '异常'));
    await tester.pumpAndSettle();
    expect(find.text('刘一'), findsOneWidget);

    final saved = await SharedPreferences.getInstance().then(
      (prefs) => prefs.getString('roll_call_people_v1'),
    );
    expect(saved, contains('"name":"刘一","status":"late"'));
  });

  testWidgets('320 宽度顶部栏不溢出', (tester) async {
    await _pumpApp(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
  });
}
