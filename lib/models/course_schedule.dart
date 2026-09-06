import 'dart:convert';

class CurrentCourse {
  const CurrentCourse({
    required this.name,
    required this.teacher,
    required this.room,
    required this.startTime,
    required this.endTime,
  });

  final String name;
  final String teacher;
  final String room;
  final String startTime;
  final String endTime;

  String get summary {
    final details = [
      if (teacher.isNotEmpty) teacher,
      if (room.isNotEmpty) room,
      '$startTime-$endTime',
    ];
    return '$name｜${details.join('｜')}';
  }
}

class WakeUpSchedule {
  const WakeUpSchedule._({
    required this.name,
    required this.startDate,
    required this.maxWeek,
    required this._timeSlots,
    required this._courses,
    required this._arrangements,
  });

  final String name;
  final DateTime startDate;
  final int maxWeek;
  final Map<String, _TimeSlot> _timeSlots;
  final Map<String, _Course> _courses;
  final List<_Arrangement> _arrangements;

  factory WakeUpSchedule.parse(String shareData) {
    final parts = const LineSplitter()
        .convert(shareData.trim())
        .where((line) => line.trim().isNotEmpty)
        .map(jsonDecode)
        .toList();
    if (parts.isEmpty) {
      throw const FormatException('分享数据为空');
    }

    Map<String, dynamic>? tableConfig;
    final timeSlots = <String, _TimeSlot>{};
    final courses = <String, _Course>{};
    final arrangements = <_Arrangement>[];

    for (final part in parts) {
      if (part is Map<String, dynamic> && part.containsKey('startDate')) {
        tableConfig = part;
        continue;
      }
      if (part is! List || part.isEmpty || part.first is! Map) continue;
      final first = Map<String, dynamic>.from(part.first as Map);
      if (first.containsKey('node') && first.containsKey('startTime')) {
        for (final raw in part) {
          final item = Map<String, dynamic>.from(raw as Map);
          final slot = _TimeSlot.fromJson(item);
          timeSlots[_key(slot.timeTable, slot.node)] = slot;
        }
      } else if (first.containsKey('courseName')) {
        for (final raw in part) {
          final item = Map<String, dynamic>.from(raw as Map);
          final course = _Course.fromJson(item);
          courses[_key(course.tableId, course.id)] = course;
        }
      } else if (first.containsKey('startNode') && first.containsKey('day')) {
        arrangements.addAll(
          part.map(
            (raw) =>
                _Arrangement.fromJson(Map<String, dynamic>.from(raw as Map)),
          ),
        );
      }
    }

    if (tableConfig == null || courses.isEmpty || arrangements.isEmpty) {
      throw const FormatException('课程表数据不完整');
    }
    final startDate = _parseDate(tableConfig['startDate'] as String? ?? '');
    return WakeUpSchedule._(
      name:
          tableConfig['tableName'] as String? ??
          tableConfig['school'] as String? ??
          'WakeUp 课程表',
      startDate: startDate,
      maxWeek: _asInt(tableConfig['maxWeek']),
      timeSlots: timeSlots,
      courses: courses,
      arrangements: arrangements,
    );
  }

  List<CurrentCourse> currentCoursesAt(DateTime dateTime) {
    final date = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final semesterStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final daysSinceStart = date.difference(semesterStart).inDays;
    if (daysSinceStart < 0) return const [];
    final week = daysSinceStart ~/ 7 + 1;
    if (maxWeek > 0 && week > maxWeek) return const [];
    final minute = dateTime.hour * 60 + dateTime.minute;
    final matches = <CurrentCourse>[];

    for (final arrangement in _arrangements) {
      if (arrangement.day != dateTime.weekday ||
          week < arrangement.startWeek ||
          week > arrangement.endWeek ||
          !_matchesWeekType(arrangement.type, week)) {
        continue;
      }

      final course = _courses[_key(arrangement.tableId, arrangement.id)];
      if (course == null) continue;

      final startTime = arrangement.ownTime
          ? arrangement.startTime
          : _timeSlots[_key(arrangement.tableId, arrangement.startNode)]
                    ?.startTime ??
                '';
      final endNode = arrangement.startNode + arrangement.step - 1;
      final endTime = arrangement.ownTime
          ? arrangement.endTime
          : _timeSlots[_key(arrangement.tableId, endNode)]?.endTime ?? '';
      final startMinute = _parseTime(startTime);
      final endMinute = _parseTime(endTime);
      if (startMinute == null || endMinute == null) continue;
      final isInside = endMinute >= startMinute
          ? minute >= startMinute && minute <= endMinute
          : minute >= startMinute || minute <= endMinute;
      if (!isInside) continue;

      matches.add(
        CurrentCourse(
          name: course.name,
          teacher: arrangement.teacher,
          room: arrangement.room,
          startTime: startTime,
          endTime: endTime,
        ),
      );
    }
    return matches;
  }
}

class _TimeSlot {
  const _TimeSlot({
    required this.timeTable,
    required this.node,
    required this.startTime,
    required this.endTime,
  });

  factory _TimeSlot.fromJson(Map<String, dynamic> json) => _TimeSlot(
    timeTable: _asInt(json['timeTable']),
    node: _asInt(json['node']),
    startTime: json['startTime'] as String? ?? '',
    endTime: json['endTime'] as String? ?? '',
  );

  final int timeTable;
  final int node;
  final String startTime;
  final String endTime;
}

class _Course {
  const _Course({required this.tableId, required this.id, required this.name});

  factory _Course.fromJson(Map<String, dynamic> json) => _Course(
    tableId: _asInt(json['tableId']),
    id: _asInt(json['id']),
    name: json['courseName'] as String? ?? '未命名课程',
  );

  final int tableId;
  final int id;
  final String name;
}

class _Arrangement {
  const _Arrangement({
    required this.tableId,
    required this.id,
    required this.day,
    required this.startNode,
    required this.step,
    required this.startWeek,
    required this.endWeek,
    required this.type,
    required this.teacher,
    required this.room,
    required this.ownTime,
    required this.startTime,
    required this.endTime,
  });

  factory _Arrangement.fromJson(Map<String, dynamic> json) => _Arrangement(
    tableId: _asInt(json['tableId']),
    id: _asInt(json['id']),
    day: _asInt(json['day']),
    startNode: _asInt(json['startNode']),
    step: _asInt(json['step']),
    startWeek: _asInt(json['startWeek']),
    endWeek: _asInt(json['endWeek']),
    type: _asInt(json['type']),
    teacher: json['teacher'] as String? ?? '',
    room: json['room'] as String? ?? '',
    ownTime: json['ownTime'] as bool? ?? false,
    startTime: json['startTime'] as String? ?? '',
    endTime: json['endTime'] as String? ?? '',
  );

  final int tableId;
  final int id;
  final int day;
  final int startNode;
  final int step;
  final int startWeek;
  final int endWeek;
  final int type;
  final String teacher;
  final String room;
  final bool ownTime;
  final String startTime;
  final String endTime;
}

String _key(int tableId, int id) => '$tableId:$id';

int _asInt(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

DateTime _parseDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) throw const FormatException('开学日期格式无效');
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    throw const FormatException('开学日期格式无效');
  }
  return DateTime(year, month, day);
}

int? _parseTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

bool _matchesWeekType(int type, int week) => switch (type) {
  1 => week.isOdd,
  2 => week.isEven,
  _ => true,
};
