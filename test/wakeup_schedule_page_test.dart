import 'package:callrool_app/services/wakeup_schedule_service.dart';
import 'package:callrool_app/widgets/wakeup_schedule_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _shareData = '''
{"courseLen":60,"id":2,"name":"测试时间表"}
[{"endTime":"09:00","node":1,"startTime":"08:00","timeTable":2},{"endTime":"11:00","node":2,"startTime":"10:00","timeTable":2},{"endTime":"15:00","node":3,"startTime":"14:00","timeTable":2}]
{"maxWeek":20,"startDate":"2026-8-31","tableName":"预览课表"}
[{"courseName":"第一节","id":1,"tableId":2},{"courseName":"第二节","id":2,"tableId":2},{"courseName":"第三节","id":3,"tableId":2}]
[{"day":3,"endTime":"","endWeek":20,"id":1,"ownTime":false,"room":"A101","startNode":1,"startTime":"","startWeek":1,"step":1,"tableId":2,"teacher":"甲","type":0},{"day":3,"endTime":"","endWeek":20,"id":2,"ownTime":false,"room":"B202","startNode":2,"startTime":"","startWeek":1,"step":1,"tableId":2,"teacher":"乙","type":0},{"day":3,"endTime":"","endWeek":20,"id":3,"ownTime":false,"room":"C303","startNode":3,"startTime":"","startWeek":1,"step":1,"tableId":2,"teacher":"丙","type":0}]
''';

class _FakeWakeUpScheduleService extends WakeUpScheduleService {
  const _FakeWakeUpScheduleService();

  @override
  Future<String> fetchShareData({
    required String authToken,
    required String shareCode,
  }) async => _shareData;
}

class _FakeLocalQuickImportBackend extends WakeUpScheduleService {
  const _FakeLocalQuickImportBackend();

  @override
  bool get requiresAuthToken => false;
}

Future<void> _pumpPage(WidgetTester tester, DateTime now) async {
  await tester.binding.setSurfaceSize(const Size(800, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: WakeUpSchedulePage(
        initialAuthToken: 'token',
        backend: const _FakeWakeUpScheduleService(),
        onAuthTokenSaved: (_) async {},
        now: () => now,
      ),
    ),
  );
  await tester.enterText(find.byType(TextField), 'share-code');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, '预览课程'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('当前有课时预览当前课程与下一节课', (tester) async {
    await _pumpPage(tester, DateTime(2026, 9, 2, 10, 30));

    expect(find.text('当前课程'), findsOneWidget);
    expect(find.text('第二节'), findsOneWidget);
    expect(find.text('B202'), findsOneWidget);
    expect(find.text('下一节课'), findsOneWidget);
    expect(find.text('第三节'), findsOneWidget);
    expect(find.text('C303'), findsOneWidget);
  });

  testWidgets('当前无课时预览接下来两节课', (tester) async {
    await _pumpPage(tester, DateTime(2026, 9, 2, 9, 30));

    expect(find.text('当前课程'), findsNothing);
    expect(find.text('接下来第 1 节'), findsOneWidget);
    expect(find.text('第二节'), findsOneWidget);
    expect(find.text('B202'), findsOneWidget);
    expect(find.text('接下来第 2 节'), findsOneWidget);
    expect(find.text('第三节'), findsOneWidget);
    expect(find.text('C303'), findsOneWidget);
  });

  testWidgets('本地 backend 不要求 authToken', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: WakeUpSchedulePage(
          initialAuthToken: '',
          backend: const _FakeLocalQuickImportBackend(),
          onAuthTokenSaved: (_) async {},
          now: () => DateTime(2026, 9, 2, 9, 30),
        ),
      ),
    );

    expect(find.byTooltip('设置 authToken'), findsNothing);
    await tester.enterText(find.byType(TextField), 'share-code');
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '预览课程'),
    );
    expect(button.onPressed, isNotNull);
  });
}
