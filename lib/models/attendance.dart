import 'package:flutter/material.dart';

enum AttendanceStatus {
  unmarked,
  present,
  absent,
  leave,
  personalLeave,
  sickLeave,
}

extension AttendanceStatusUi on AttendanceStatus {
  String get label => switch (this) {
    AttendanceStatus.unmarked => '未点名',
    AttendanceStatus.present => '正常',
    AttendanceStatus.absent => '缺勤',
    AttendanceStatus.leave => '公假',
    AttendanceStatus.personalLeave => '事假',
    AttendanceStatus.sickLeave => '病假',
  };
  Color get color => switch (this) {
    AttendanceStatus.unmarked => const Color(0xFF77817B),
    AttendanceStatus.present => const Color(0xFF198754),
    AttendanceStatus.absent => const Color(0xFFD14C3E),
    AttendanceStatus.leave => const Color(0xFFDA8610),
    AttendanceStatus.personalLeave => const Color(0xFF8B5FBF),
    AttendanceStatus.sickLeave => const Color(0xFF3D7DB8),
  };
  Color get softColor => switch (this) {
    AttendanceStatus.unmarked => const Color(0xFFF0F2F0),
    AttendanceStatus.present => const Color(0xFFE6F5EC),
    AttendanceStatus.absent => const Color(0xFFFCEAE7),
    AttendanceStatus.leave => const Color(0xFFFFF3DD),
    AttendanceStatus.personalLeave => const Color(0xFFF2E9FA),
    AttendanceStatus.sickLeave => const Color(0xFFE6F1FB),
  };
  Color adaptiveColor(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.light) return color;
    return switch (this) {
      AttendanceStatus.unmarked => const Color(0xFFAEB8B1),
      AttendanceStatus.present => const Color(0xFF72D69A),
      AttendanceStatus.absent => const Color(0xFFFFB4AB),
      AttendanceStatus.leave => const Color(0xFFFFC46B),
      AttendanceStatus.personalLeave => const Color(0xFFD8B4FE),
      AttendanceStatus.sickLeave => const Color(0xFF9CCAFF),
    };
  }

  Color adaptiveSoftColor(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.light) return softColor;
    return adaptiveColor(context).withValues(alpha: .14);
  }

  IconData get icon => switch (this) {
    AttendanceStatus.unmarked => Icons.remove_rounded,
    AttendanceStatus.present => Icons.check_rounded,
    AttendanceStatus.absent => Icons.close_rounded,
    AttendanceStatus.leave => Icons.beach_access_rounded,
    AttendanceStatus.personalLeave => Icons.person_outline_rounded,
    AttendanceStatus.sickLeave => Icons.local_hospital_outlined,
  };
}

bool isAbsenceStatus(AttendanceStatus status) =>
    status == AttendanceStatus.absent ||
    status == AttendanceStatus.leave ||
    status == AttendanceStatus.personalLeave ||
    status == AttendanceStatus.sickLeave;
bool isLeaveStatus(AttendanceStatus status) =>
    status == AttendanceStatus.leave ||
    status == AttendanceStatus.personalLeave ||
    status == AttendanceStatus.sickLeave;

enum RosterFilter { all, unmarked, present, absent, leave }
