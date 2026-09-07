class AttendanceCopyVariable {
  const AttendanceCopyVariable({required this.name, required this.description});

  final String name;
  final String description;

  String get token => '{{$name}}';
}

class AttendanceCopyTemplate {
  const AttendanceCopyTemplate._();

  static const variables = [
    AttendanceCopyVariable(name: '课程', description: '当前课程名称'),
    AttendanceCopyVariable(name: '老师', description: '当前课程老师'),
    AttendanceCopyVariable(name: '应出勤人数', description: '名单总人数'),
    AttendanceCopyVariable(name: '实际出勤人数', description: '正常出勤人数'),
    AttendanceCopyVariable(name: '请假', description: '请假人员及类型'),
    AttendanceCopyVariable(name: '教室', description: '当前课程教室'),
  ];

  static const suggested = '''{{课程}}考勤情况
老师：{{老师}}
教室：{{教室}}
应出勤：{{应出勤人数}}人
实际出勤：{{实际出勤人数}}人
请假：{{请假}}''';

  static String render(String template, Map<String, String> values) {
    var result = template;
    for (final variable in variables) {
      final value = values[variable.name];
      result = result.replaceAll(
        variable.token,
        value == null || value.trim().isEmpty ? '无' : value,
      );
    }
    return result;
  }
}
