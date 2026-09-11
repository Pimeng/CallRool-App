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

/// 切换到主页底部导航栏的某个 Tab。
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// 展开右下角悬浮按钮菜单并点击其中一项操作。
Future<void> _tapAction(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('fab-menu-toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

const _fabToggleKey = ValueKey('fab-menu-toggle');

/// 读取悬浮菜单里某一项当前的弹出进度：0 = 完全收起，1 = 完全展开。
double _menuEntryProgress(WidgetTester tester, String label) {
  final fade = tester.widget<FadeTransition>(
    find
        .ancestor(of: find.text(label), matching: find.byType(FadeTransition))
        .first,
  );
  return fade.opacity.value;
}

Future<void> _openCopyFormatEditor(WidgetTester tester) async {
  await _openTab(tester, '设置');
  await tester.tap(find.text('自定义复制格式'));
  await tester.pumpAndSettle();
}

Future<void> _openRandomPicker(WidgetTester tester) async {
  await _openTab(tester, '工具箱');
  await tester.tap(find.widgetWithText(ListTile, '随机点人'));
  await tester.pumpAndSettle();
}

/// 等待抽签滚动动画结束。
///
/// 抽签过程中有无限循环的进度条，不能直接 pumpAndSettle，需先推进到动画结束。
Future<void> _finishSpin(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 3000));
  await tester.pumpAndSettle();
}

/// 读取滚动过程中当前显示的姓名；不在滚动状态时返回 null。
String? _rollingName(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('random-picker-rolling-name'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

/// 取结果面板的装饰，用于比较单人与多人抽取是否同一套样式。
BoxDecoration _resultPanelDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const ValueKey('random-picker-result-panel')),
  );
  return container.decoration! as BoxDecoration;
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

    // 首页只有搜索栏与筛选条，没有标题栏/Logo。
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '全部'), findsOneWidget);
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

    await _tapAction(tester, '复制考勤情况');
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

    await _tapAction(tester, '复制考勤情况');
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

    await _tapAction(tester, '复制考勤情况');

    expect(copiedText, '刘一、陈二|2|张三|1|李四|1|王五|1');
  });

  testWidgets('底部导航切换到工具箱与设置页', (tester) async {
    await _pumpApp(tester);

    await _openTab(tester, '工具箱');
    expect(find.widgetWithText(AppBar, '工具箱'), findsOneWidget);
    expect(find.text('抽签'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '随机点人'), findsOneWidget);

    await _openTab(tester, '设置');
    expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
    expect(find.text('名单'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('课程表'), findsOneWidget);
    expect(find.text('导入名单'), findsOneWidget);
    expect(find.text('导出名单'), findsOneWidget);
    expect(find.text('自定义复制格式'), findsOneWidget);
    expect(find.text('同步 WakeUp 课程表'), findsOneWidget);
    expect(find.textContaining('上次修改：'), findsOneWidget);
    expect(find.text('随机点人'), findsNothing);
    expect(find.text('复制考勤情况'), findsNothing);
    expect(find.text('未点名全部标记为旷课'), findsNothing);
    expect(find.text('重置考勤'), findsNothing);

    await _openTab(tester, '考勤');
    expect(find.byType(AppBar), findsNothing);
    expect(find.widgetWithText(FilterChip, '全部'), findsOneWidget);
  });

  testWidgets('搜索框随滚动逐帧上滑，筛选条钉在顶部', (tester) async {
    await _pumpApp(tester);

    // 滑出视口后 sliver 会被视口标记为 offstage，find.byType 默认会跳过它，
    // 这里要显式带上 offstage 的控件才能量到它被推到了哪儿。
    final searchField = find.byType(TextField, skipOffstage: false);
    final chips = find.widgetWithText(FilterChip, '全部');

    // 名单滚动起来后第一行可能被钉住的筛选条挡住或移出屏幕，
    // 直接 drag 它会打空，所以固定从列表中间的空白处拖。
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    Future<void> dragRoster(double dy) async {
      await tester.dragFrom(
        Offset(size.width / 2, size.height * .6),
        Offset(0, dy),
      );
      await tester.pumpAndSettle();
    }

    final searchAtRest = tester.getRect(searchField);
    final chipsAtRest = tester.getRect(chips);

    // 小幅度上滑：搜索框跟手整体上移，高度不变 ——
    // 是滚动驱动的位移，不是过阈值就整块塌成 0 高的折叠动画。
    await dragRoster(-40);
    final searchSmall = tester.getRect(searchField);
    expect(searchSmall.height, closeTo(searchAtRest.height, 1));
    expect(searchSmall.top, lessThan(searchAtRest.top));

    // 继续上滑：搜索框完全离开视口，筛选条上移后钉住。
    await dragRoster(-200);
    final chipsPinned = tester.getRect(chips);
    expect(chipsPinned.top, lessThan(chipsAtRest.top));
    expect(
      tester.getRect(searchField).bottom,
      lessThanOrEqualTo(chipsPinned.top + 1),
    );

    // 再滑一段，筛选条位置不再变化（已钉住）。
    await dragRoster(-120);
    expect(tester.getRect(chips).top, closeTo(chipsPinned.top, 1));

    // 滑回顶部：搜索框回到原位。
    await dragRoster(600);
    expect(tester.getRect(searchField).top, closeTo(searchAtRest.top, 6));
  });

  testWidgets('右下角悬浮菜单收纳原顶部栏操作', (tester) async {
    await _pumpApp(tester);

    expect(find.text('添加人员'), findsNothing);
    expect(find.text('复制考勤情况'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('fab-menu-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('添加人员'), findsOneWidget);
    expect(find.text('复制考勤情况'), findsOneWidget);
    expect(find.text('未点名全部标记为旷课'), findsOneWidget);
    expect(find.text('重置考勤'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fab-menu-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('添加人员'), findsNothing);
  });

  testWidgets('悬浮菜单项从下往上依次弹出且收起有动画', (tester) async {
    await _pumpApp(tester);

    final fabBefore = tester.getCenter(find.byKey(_fabToggleKey));

    await tester.tap(find.byKey(_fabToggleKey));
    await tester.pump();
    // 第一帧：菜单项已经挂上，但都还没开始弹。
    expect(find.text('重置考勤'), findsOneWidget);
    expect(_menuEntryProgress(tester, '重置考勤'), 0);
    expect(_menuEntryProgress(tester, '添加人员'), 0);

    await tester.pump(const Duration(milliseconds: 100));
    final nearest = _menuEntryProgress(tester, '重置考勤');
    final farthest = _menuEntryProgress(tester, '添加人员');
    expect(nearest, greaterThan(0));
    // 离悬浮按钮最近的一项先弹出来，最远的一项还在等。
    expect(nearest, greaterThan(farthest));
    // 展开过程中按钮本身不能被顶走。
    expect(
      (tester.getCenter(find.byKey(_fabToggleKey)).dy - fabBefore.dy).abs(),
      lessThan(.5),
    );

    await tester.pumpAndSettle();
    expect(_menuEntryProgress(tester, '重置考勤'), 1);
    expect(_menuEntryProgress(tester, '添加人员'), 1);

    // 展开后必须贴着右下角的按钮，不能铺满整行或跑到屏幕左边去。
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final fabRect = tester.getRect(find.byKey(_fabToggleKey));
    expect(fabRect.right, lessThanOrEqualTo(screen.width));
    for (final label in ['添加人员', '复制考勤情况', '未点名全部标记为旷课', '重置考勤']) {
      final rect = tester.getRect(find.text(label));
      // 文本起点已过屏幕中线（项的高度短、宽度也不该被撑开）。
      expect(
        rect.left,
        greaterThan(screen.width / 2),
        reason: '$label 不应该跑到左边',
      );
      // 与按钮右缘基本对齐（差值只是项内部的右侧内边距）。
      expect(fabRect.right - rect.right, inInclusiveRange(0, 40));
    }

    // 收起也要是动画：过一帧后菜单项应该还在，只是缩回去了。
    await tester.tap(find.byKey(_fabToggleKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('添加人员'), findsOneWidget);
    expect(_menuEntryProgress(tester, '重置考勤'), lessThan(1));

    await tester.pumpAndSettle();
    expect(find.text('添加人员'), findsNothing);
  });

  testWidgets('统计数量并入筛选条角标', (tester) async {
    await _pumpApp(tester);

    for (final entry in {
      '全部': '10',
      '未点名': '10',
      '正常': '0',
      '异常': '0',
      '请假': '0',
    }.entries) {
      expect(
        find.descendant(
          of: find.widgetWithText(FilterChip, entry.key),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
        reason: '${entry.key} 筛选上应显示 ${entry.value}',
      );
    }
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

    await _tapAction(tester, '复制考勤情况');
    await tester.tap(find.text('继续复制'));
    await tester.pumpAndSettle();

    expect(copiedText, contains('当前课程：当前测试课程｜测试教师｜测试教室｜00:00-23:59'));
  });

  testWidgets('课程表同步支持粘贴 WakeUp 完整分享口令', (tester) async {
    await _pumpApp(
      tester,
      initialValues: const {'wakeup_auth_token_v1': 'saved-token'},
    );

    await _openTab(tester, '设置');
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

    await _openTab(tester, '设置');
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
    await _openTab(tester, '考勤');
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

    await _openTab(tester, '设置');
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

    await _openTab(tester, '设置');
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

    await _tapAction(tester, '添加人员');
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

  testWidgets('320 宽度各 Tab 与悬浮菜单不溢出', (tester) async {
    await _pumpApp(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('fab-menu-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('fab-menu-toggle')));
    await tester.pumpAndSettle();

    await _openTab(tester, '工具箱');
    expect(tester.takeException(), isNull);

    await _openTab(tester, '设置');
    expect(tester.takeException(), isNull);
  });

  testWidgets('随机点人只抽取正常到勤人员', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"正常甲","status":"present"},'
        '{"id":2,"name":"正常乙","status":"present"},'
        '{"id":3,"name":"公假丙","status":"leave"},'
        '{"id":4,"name":"旷课丁","status":"truancy"},'
        '{"id":5,"name":"未点名戊","status":"unmarked"}]';
    await _pumpApp(tester, initialValues: {'roll_call_people_v1': peopleJson});

    await _openRandomPicker(tester);
    expect(find.widgetWithText(AppBar, '随机点人'), findsOneWidget);
    expect(find.text('正常到勤 2 人，剩余可抽 2 人'), findsOneWidget);

    await tester.tap(find.text('抽取 1 人'));
    await _finishSpin(tester);

    expect(find.text('恭喜被抽中'), findsOneWidget);
    final drawn = [
      '正常甲',
      '正常乙',
    ].where((name) => find.text(name).evaluate().isNotEmpty).toList();
    expect(drawn, hasLength(1));
    // 非正常状态的人不在候选人里，页面上不会出现。
    expect(find.text('公假丙'), findsNothing);
    expect(find.text('旷课丁'), findsNothing);
    expect(find.text('未点名戊'), findsNothing);
  });

  testWidgets('抽取过程中姓名持续变化', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"甲","status":"present"},'
        '{"id":2,"name":"乙","status":"present"},'
        '{"id":3,"name":"丙","status":"present"}]';
    await _pumpApp(tester, initialValues: {'roll_call_people_v1': peopleJson});

    await _openRandomPicker(tester);
    await tester.tap(find.text('抽取 1 人'));
    await tester.pump();

    // 滚动期间逐帧采样，应能看到多个不同姓名依次出现。
    final seen = <String>{};
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final name in ['甲', '乙', '丙']) {
        if (find.text(name).evaluate().isNotEmpty) seen.add(name);
      }
    }
    expect(seen.length, greaterThan(1));

    await _finishSpin(tester);
  });

  testWidgets('抽签动画越到后面换名越慢并停在结果上', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"甲","status":"present"},'
        '{"id":2,"name":"乙","status":"present"},'
        '{"id":3,"name":"丙","status":"present"}]';
    await _pumpApp(tester, initialValues: {'roll_call_people_v1': peopleJson});

    await _openRandomPicker(tester);
    await tester.tap(find.text('抽取 1 人'));
    await tester.pump();

    // 前 500ms：快速滚动阶段，换名次数很多。
    var early = 0;
    String? previous = _rollingName(tester);
    for (var i = 0; i < 31; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = _rollingName(tester);
      if (current != previous) early += 1;
      previous = current;
    }

    // 后 1s：减速阶段，换名次数应明显减少。
    await tester.pump(const Duration(milliseconds: 1200));
    var late = 0;
    previous = _rollingName(tester);
    for (var i = 0; i < 55; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = _rollingName(tester);
      if (current != previous) late += 1;
      previous = current;
    }

    expect(early, greaterThan(10));
    expect(late, lessThan(early));

    // 末段应停住不动，并且停的就是最终中奖者。
    final settled = _rollingName(tester);
    expect(settled, isNotNull);

    await _finishSpin(tester);
    expect(find.text(settled!), findsOneWidget);
  });

  testWidgets('抽签前后姓名排版与面板尺寸保持一致', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"甲","status":"present"},'
        '{"id":2,"name":"乙","status":"present"}]';
    await _pumpApp(tester, initialValues: {'roll_call_people_v1': peopleJson});

    await _openRandomPicker(tester);
    await tester.tap(find.text('抽取 1 人'));
    await tester.pump();

    const rollingKey = ValueKey('random-picker-rolling-name');
    const resultKey = ValueKey('random-picker-result-name');

    final rollingName = tester.widget<Text>(find.byKey(rollingKey));
    final rollingPanel = tester.getSize(
      find
          .ancestor(
            of: find.byKey(rollingKey),
            matching: find.byType(Container),
          )
          .first,
    );

    await _finishSpin(tester);

    final resultName = tester.widget<Text>(find.byKey(resultKey));
    final resultPanel = tester.getSize(
      find
          .ancestor(of: find.byKey(resultKey), matching: find.byType(Container))
          .first,
    );

    expect(resultName.style?.fontSize, rollingName.style?.fontSize);
    expect(resultName.style?.fontWeight, rollingName.style?.fontWeight);
    expect(resultPanel, rollingPanel);
  });

  testWidgets('单人抽取与多人抽取的结果面板样式一致', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"甲","status":"present"},'
        '{"id":2,"name":"乙","status":"present"},'
        '{"id":3,"name":"丙","status":"present"}]';
    await _pumpApp(
      tester,
      size: const Size(400, 900),
      initialValues: {'roll_call_people_v1': peopleJson},
    );

    await _openRandomPicker(tester);

    // 单人抽取。
    await tester.tap(find.text('抽取 1 人'));
    await _finishSpin(tester);

    expect(
      find.byKey(const ValueKey('random-picker-result-panel')),
      findsOneWidget,
    );
    expect(find.text('恭喜被抽中'), findsOneWidget);
    final single = _resultPanelDecoration(tester);

    // 关掉不重复并改成 3 人，走多人抽取分支。
    await tester.tap(find.widgetWithText(SwitchListTile, '不重复抽取'));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('增加人数'));
      await tester.pump();
    }
    expect(find.text('抽取 3 人'), findsOneWidget);

    await tester.tap(find.text('抽取 3 人'));
    await _finishSpin(tester);

    expect(find.text('抽中 3 人'), findsOneWidget);
    final batch = _resultPanelDecoration(tester);

    // 两套结果必须长得一样：同一个面板、同样的底色/边框/圆角。
    expect(batch.color, single.color);
    expect(batch.border, single.border);
    expect(batch.borderRadius, single.borderRadius);
  });

  testWidgets('关闭抽签动画后点击直接显示结果', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"甲","status":"present"},'
        '{"id":2,"name":"乙","status":"present"}]';
    await _pumpApp(
      tester,
      size: const Size(400, 900),
      initialValues: {'roll_call_people_v1': peopleJson},
    );

    await _openRandomPicker(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, '播放抽签动画'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('抽取 1 人'));
    await tester.pumpAndSettle();

    // 没有滚动过程，直接就是结果。
    expect(
      find.byKey(const ValueKey('random-picker-rolling-name')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('random-picker-result-name')),
      findsOneWidget,
    );
    expect(find.text('恭喜被抽中'), findsOneWidget);
    expect(find.text('本轮已抽中 1 人'), findsOneWidget);
  });

  testWidgets('随机点人支持批量抽取', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"甲","status":"present"},'
        '{"id":2,"name":"乙","status":"present"},'
        '{"id":3,"name":"丙","status":"present"},'
        '{"id":4,"name":"丁","status":"present"},'
        '{"id":5,"name":"戊","status":"present"}]';
    await _pumpApp(
      tester,
      size: const Size(400, 900),
      initialValues: {'roll_call_people_v1': peopleJson},
    );

    await _openRandomPicker(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('增加人数'));
      await tester.pump();
    }
    expect(find.text('抽取 5 人'), findsOneWidget);

    await tester.tap(find.text('抽取 5 人'));
    await _finishSpin(tester);

    expect(find.text('抽中 5 人'), findsOneWidget);
    for (final name in ['甲', '乙', '丙', '丁', '戊']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('本轮已抽中 5 人'), findsOneWidget);
  });

  testWidgets('不重复抽取会排除已抽中的人并支持重置', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"甲","status":"present"},'
        '{"id":2,"name":"乙","status":"present"}]';
    await _pumpApp(tester, initialValues: {'roll_call_people_v1': peopleJson});

    await _openRandomPicker(tester);
    expect(find.text('正常到勤 2 人，剩余可抽 2 人'), findsOneWidget);

    await tester.tap(find.text('抽取 1 人'));
    await _finishSpin(tester);
    final first = [
      '甲',
      '乙',
    ].firstWhere((name) => find.text(name).evaluate().isNotEmpty);
    expect(find.text('正常到勤 2 人，剩余可抽 1 人'), findsOneWidget);

    await tester.tap(find.text('抽取 1 人'));
    await _finishSpin(tester);
    final second = [
      '甲',
      '乙',
    ].firstWhere((name) => find.text(name).evaluate().isNotEmpty);
    expect(second, isNot(first));
    expect(find.text('正常到勤 2 人，剩余可抽 0 人'), findsOneWidget);
    expect(find.text('已全部抽完'), findsOneWidget);

    await tester.tap(find.text('重置本轮'));
    await tester.pumpAndSettle();
    expect(find.text('正常到勤 2 人，剩余可抽 2 人'), findsOneWidget);
    expect(find.text('本轮已抽中 2 人'), findsNothing);
  });

  testWidgets('没有正常到勤人员时随机点人显示空状态', (tester) async {
    const peopleJson =
        '[{"id":1,"name":"公假甲","status":"leave"},'
        '{"id":2,"name":"旷课乙","status":"truancy"}]';
    await _pumpApp(tester, initialValues: {'roll_call_people_v1': peopleJson});

    await _openRandomPicker(tester);
    expect(find.text('没有可抽签的人员'), findsOneWidget);
    expect(find.text('抽取 1 人'), findsNothing);
  });
}
