import 'package:callrool_app/models/course_schedule.dart';
import 'package:callrool_app/services/wakeup_schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _shareData = '''
{"courseLen":45,"id":2,"name":"测试时间表"}
[{"endTime":"08:40","node":1,"startTime":"08:00","timeTable":2},{"endTime":"09:20","node":2,"startTime":"08:40","timeTable":2}]
{"maxWeek":20,"school":"测试学院","startDate":"2026-8-31","tableName":"测试课表"}
[{"courseName":"数据标注工程","id":7,"tableId":2},{"courseName":"网络爬虫","id":8,"tableId":2}]
[{"day":3,"endTime":"","endWeek":16,"id":7,"ownTime":false,"room":"实训室305","startNode":1,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"李老师","type":0},{"day":1,"endTime":"","endWeek":16,"id":8,"ownTime":false,"room":"教学楼101","startNode":1,"startTime":"","startWeek":1,"step":1,"tableId":2,"teacher":"王老师","type":2}]
''';

void main() {
  test('从 WakeUp 完整分享口令中提取 shareCode', () {
    const message =
        '这是来自「WakeUp课程表」的课表分享，30分钟内有效哦，如果失效请朋友再分享一遍叭。'
        '为了保护隐私我们选择不监听你的剪贴板，请复制这条消息后，打开App的主界面，'
        '右上角第二个按钮 -> 从分享口令导入，按操作提示即可完成导入~'
        '分享口令为「ffffbf0619574371bd27364855407d8f」';

    expect(extractWakeUpShareCode(message), 'ffffbf0619574371bd27364855407d8f');
  });

  test('直接填写 shareCode 时保持原值并去除首尾空白', () {
    expect(
      extractWakeUpShareCode('  ffffbf0619574371bd27364855407d8f  '),
      'ffffbf0619574371bd27364855407d8f',
    );
  });

  test('解析 WakeUp 分享数据并匹配当前课程', () {
    final schedule = WakeUpSchedule.parse(_shareData);

    expect(schedule.name, '测试课表');
    final courses = schedule.currentCoursesAt(DateTime(2026, 9, 2, 8, 50));
    expect(courses, hasLength(1));
    expect(courses.single.name, '数据标注工程');
    expect(courses.single.teacher, '李老师');
    expect(courses.single.room, '实训室305');
    expect(courses.single.startTime, '08:00');
    expect(courses.single.endTime, '09:20');
  });

  test('支持单双周并在非上课时段返回空结果', () {
    final schedule = WakeUpSchedule.parse(_shareData);

    expect(
      schedule.currentCoursesAt(DateTime(2026, 9, 7, 8, 10)).single.name,
      '网络爬虫',
    );
    expect(schedule.currentCoursesAt(DateTime(2026, 9, 14, 8, 10)), isEmpty);
    expect(schedule.currentCoursesAt(DateTime(2026, 9, 2, 10)), isEmpty);
  });

  test('拒绝空的分享数据', () {
    expect(() => WakeUpSchedule.parse(''), throwsFormatException);
  });

  test('识别已经过期的分享码', () {
    expect(
      () => decodeWakeUpShareResponse(
        '{"success":true,"code":200,"message":"获取成功","data":{"shareData":""}}',
      ),
      throwsA(
        isA<WakeUpScheduleException>().having(
          (error) => error.message,
          'message',
          '分享码已过期或课程表为空',
        ),
      ),
    );
  });
}
