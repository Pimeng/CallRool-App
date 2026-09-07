import 'package:callrool_app/models/attendance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('迟到和早退计入实际出勤与异常，旷课只计入异常', () {
    expect(isActuallyPresentStatus(AttendanceStatus.late), isTrue);
    expect(isActuallyPresentStatus(AttendanceStatus.earlyLeave), isTrue);
    expect(isActuallyPresentStatus(AttendanceStatus.truancy), isFalse);

    for (final status in [
      AttendanceStatus.late,
      AttendanceStatus.earlyLeave,
      AttendanceStatus.truancy,
    ]) {
      expect(isAttendanceIssueStatus(status), isTrue);
      expect(isAttendanceExceptionStatus(status), isTrue);
    }
  });
}
