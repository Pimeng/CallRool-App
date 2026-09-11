import 'attendance.dart';
import 'person.dart';

/// 一条考勤记录里某个人的快照。
///
/// 保存的是保存那一刻的姓名、状态与扩展字段，之后名单改动不会影响历史。
class AttendanceRecordEntry {
  const AttendanceRecordEntry({
    required this.personId,
    required this.name,
    required this.status,
    this.fields = const {},
  });

  final int personId;
  final String name;
  final AttendanceStatus status;
  final Map<String, String> fields;

  Map<String, Object> toJson() => {
    'personId': personId,
    'name': name,
    'status': status.name,
    if (fields.isNotEmpty) 'fields': fields,
  };

  factory AttendanceRecordEntry.fromJson(Map<String, dynamic> json) =>
      AttendanceRecordEntry(
        personId: (json['personId'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        status: AttendanceStatus.values.firstWhere(
          (status) => status.name == json['status'],
          orElse: () => AttendanceStatus.unmarked,
        ),
        fields: decodePersonFields(json['fields']),
      );
}

/// 一次「保存当前考勤记录」产生的历史快照。
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.savedAt,
    required this.note,
    this.courseName,
    this.teacher,
    this.room,
    this.timeRange,
    required this.entries,
  });

  final String id;
  final DateTime savedAt;

  /// 用户填写的备注（默认取当前课程名或时间）。
  final String note;
  final String? courseName;
  final String? teacher;
  final String? room;
  final String? timeRange;
  final List<AttendanceRecordEntry> entries;

  int get total => entries.length;

  int countWhere(bool Function(AttendanceStatus status) matches) =>
      entries.where((entry) => matches(entry.status)).length;

  int get presentCount =>
      entries.where((entry) => isActuallyPresentStatus(entry.status)).length;
  int get unmarkedCount =>
      countWhere((status) => status == AttendanceStatus.unmarked);
  int get leaveCount => countWhere(isLeaveStatus);
  int get issueCount => countWhere(isAttendanceIssueStatus);

  /// 形如 `高等数学｜王老师｜A101｜08:00-09:40`；没有任何信息时返回 null。
  String? get courseSummary {
    final parts = [
      if (courseName != null && courseName!.trim().isNotEmpty) courseName!.trim(),
      if (teacher != null && teacher!.trim().isNotEmpty) teacher!.trim(),
      if (room != null && room!.trim().isNotEmpty) room!.trim(),
      if (timeRange != null && timeRange!.trim().isNotEmpty) timeRange!.trim(),
    ];
    return parts.isEmpty ? null : parts.join('｜');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'savedAt': savedAt.toIso8601String(),
    'note': note,
    'courseName': courseName,
    'teacher': teacher,
    'room': room,
    'timeRange': timeRange,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        id: json['id'] as String? ?? '',
        savedAt:
            DateTime.tryParse(json['savedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        note: json['note'] as String? ?? '',
        courseName: json['courseName'] as String?,
        teacher: json['teacher'] as String?,
        room: json['room'] as String?,
        timeRange: json['timeRange'] as String?,
        entries: [
          for (final item in (json['entries'] as List<dynamic>? ?? const []))
            if (item is Map<String, dynamic>) AttendanceRecordEntry.fromJson(item),
        ],
      );
}
