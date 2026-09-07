import 'package:callrool_app/models/attendance_copy_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('替换所有支持的复制格式变量', () {
    final result = AttendanceCopyTemplate.render(
      '{{课程}}|{{老师}}|{{应出勤人数}}|{{实际出勤人数}}|'
      '{{请假名单}}|{{请假人数}}|{{旷课名单}}|{{旷课人数}}|'
      '{{迟到名单}}|{{迟到人数}}|{{早退名单}}|{{早退人数}}|{{教室}}',
      {
        '课程': '软件测试',
        '老师': '李老师',
        '应出勤人数': '42',
        '实际出勤人数': '40',
        '请假名单': '张三、李四',
        '请假人数': '2',
        '旷课名单': '王五',
        '旷课人数': '1',
        '迟到名单': '赵六',
        '迟到人数': '1',
        '早退名单': '孙七',
        '早退人数': '1',
        '教室': '实训室 305',
      },
    );

    expect(result, '软件测试|李老师|42|40|张三、李四|2|王五|1|赵六|1|孙七|1|实训室 305');
  });

  test('保留不支持的变量以便发现模板拼写问题', () {
    final result = AttendanceCopyTemplate.render('{{课程}} {{未知变量}}', {
      '课程': '软件测试',
    });

    expect(result, '软件测试 {{未知变量}}');
  });

  test('支持的变量没有值时显示无', () {
    final result = AttendanceCopyTemplate.render(
      '课程：{{课程}}\n请假：{{请假名单}}\n人数：{{请假人数}}',
      {'课程': '', '请假名单': '   ', '请假人数': '0'},
    );

    expect(result, '课程：无\n请假：无\n人数：0');
  });
}
