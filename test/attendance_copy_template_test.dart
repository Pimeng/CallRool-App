import 'package:callrool_app/models/attendance_copy_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('替换所有支持的复制格式变量', () {
    final result = AttendanceCopyTemplate.render(
      '{{课程}}|{{老师}}|{{应出勤人数}}|{{实际出勤人数}}|{{请假}}|{{教室}}',
      {
        '课程': '软件测试',
        '老师': '李老师',
        '应出勤人数': '42',
        '实际出勤人数': '40',
        '请假': '张三（事假）、李四（病假）',
        '教室': '实训室 305',
      },
    );

    expect(result, '软件测试|李老师|42|40|张三（事假）、李四（病假）|实训室 305');
  });

  test('保留不支持的变量以便发现模板拼写问题', () {
    final result = AttendanceCopyTemplate.render('{{课程}} {{未知变量}}', {
      '课程': '软件测试',
    });

    expect(result, '软件测试 {{未知变量}}');
  });

  test('支持的变量没有值时显示无', () {
    final result = AttendanceCopyTemplate.render(
      '课程：{{课程}}\n请假：{{请假}}\n人数：{{实际出勤人数}}',
      {'课程': '', '请假': '   ', '实际出勤人数': '0'},
    );

    expect(result, '课程：无\n请假：无\n人数：0');
  });
}
