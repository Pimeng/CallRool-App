import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'storage_keys.dart';

/// 备份文件的格式标识，用于识别「这是不是本应用的备份」。
const _backupFormat = 'callrool_app_backup';
const _backupVersion = 1;

/// 备份 / 还原过程中的可预期错误，`message` 可直接展示给用户。
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次备份文件包含的数据规模，用于导入前的确认提示。
class BackupSummary {
  const BackupSummary({
    required this.peopleCount,
    required this.historyCount,
    required this.hasSchedule,
    this.exportedAt,
  });

  final int peopleCount;
  final int historyCount;
  final bool hasSchedule;
  final DateTime? exportedAt;
}

abstract final class BackupService {
  /// 导出为 JSON 字符串。只包含 [StorageKeys.backupKeys] 白名单内的数据。
  static Future<String> export() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, Object>{};
    for (final key in StorageKeys.backupKeys) {
      final value = prefs.get(key);
      if (value != null) data[key] = value;
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': _backupFormat,
      'version': _backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': data,
    });
  }

  /// 解析备份字符串并返回数据规模，不写入本地存储。
  static BackupSummary inspect(String raw) {
    final payload = _decodePayload(raw);
    return _summarize(payload.data, payload.exportedAt);
  }

  /// 当前本地数据的规模，用于在备份页展示「现有 X 人 / Y 条记录」。
  static Future<BackupSummary> currentSummary() async {
    final prefs = await SharedPreferences.getInstance();
    return BackupSummary(
      peopleCount: _countJsonList(prefs.getString(StorageKeys.people)),
      historyCount: _countJsonList(
        prefs.getString(StorageKeys.attendanceHistory),
      ),
      hasSchedule:
          (prefs.getString(StorageKeys.wakeUpScheduleData) ?? '')
              .trim()
              .isNotEmpty,
      exportedAt: DateTime.now(),
    );
  }

  /// 用备份内容覆盖本地数据，返回写入后的数据规模。
  ///
  /// 采用「覆盖」语义：先清空白名单内的所有键，再写入备份中存在的内容，
  /// 避免旧的历史记录 / 字段残留造成数据错乱。
  static Future<BackupSummary> restore(String raw) async {
    final payload = _decodePayload(raw);
    final prefs = await SharedPreferences.getInstance();
    for (final key in StorageKeys.backupKeys) {
      await prefs.remove(key);
    }
    for (final entry in payload.data.entries) {
      if (!StorageKeys.backupKeys.contains(entry.key)) continue;
      await _write(prefs, entry.key, entry.value);
    }
    return _summarize(payload.data, payload.exportedAt);
  }

  static Future<void> _write(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is List) {
      await prefs.setStringList(key, [
        for (final item in value)
          if (item != null) item.toString(),
      ]);
    }
  }

  static BackupSummary _summarize(
    Map<String, Object?> data,
    DateTime? exportedAt,
  ) {
    final people = data[StorageKeys.people];
    final history = data[StorageKeys.attendanceHistory];
    final schedule = data[StorageKeys.wakeUpScheduleData];
    return BackupSummary(
      peopleCount: _countJsonList(people),
      historyCount: _countJsonList(history),
      hasSchedule: schedule is String && schedule.trim().isNotEmpty,
      exportedAt: exportedAt,
    );
  }

  /// data 里存的是 JSON 字符串，这里数一下条目数量，仅用于展示。
  static int _countJsonList(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  static ({Map<String, Object?> data, DateTime? exportedAt}) _decodePayload(
    String raw,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const BackupException('文件内容不是有效的 JSON，可能已损坏');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BackupException('备份内容格式不正确');
    }
    if (decoded['format'] != _backupFormat) {
      throw const BackupException('这不是「快捷考勤喵」的备份文件');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const BackupException('备份文件缺少数据内容');
    }
    return (
      data: data.cast<String, Object?>(),
      exportedAt: DateTime.tryParse(decoded['exportedAt'] as String? ?? ''),
    );
  }
}
