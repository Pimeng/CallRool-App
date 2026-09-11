import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_record.dart';
import 'storage_keys.dart';

/// 考勤历史记录的本地读写。
abstract final class AttendanceHistoryStore {
  /// 从本地读取全部记录（读取失败或数据损坏时返回空列表）。
  static List<AttendanceRecord> load(SharedPreferences prefs) =>
      decode(prefs.getString(StorageKeys.attendanceHistory));

  /// 覆盖写入全部记录。
  static Future<void> save(
    SharedPreferences prefs,
    List<AttendanceRecord> records,
  ) => prefs.setString(StorageKeys.attendanceHistory, encode(records));

  static List<AttendanceRecord> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map<String, dynamic>) AttendanceRecord.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<AttendanceRecord> records) =>
      jsonEncode([for (final record in records) record.toJson()]);
}
