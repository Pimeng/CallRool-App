/// 应用本地存储（`shared_preferences`）用到的所有键。
///
/// 集中定义便于「备份 / 还原」按白名单收集数据，也避免各处硬编码字符串。
/// 修改已有键的字符串值会丢失用户数据，请保持向后兼容。
abstract final class StorageKeys {
  /// 名单及每人的考勤状态、扩展字段。
  static const people = 'roll_call_people_v1';

  /// 是否导入过自己的名单（用于首屏引导）。
  static const hasImportedRoster = 'roll_call_has_imported_v1';

  /// 名单最后一次修改时间。
  static const lastModified = 'roll_call_last_modified_v1';

  /// WakeUp 课程表登录凭据。属于敏感信息，**不写入备份文件**。
  static const wakeUpAuthToken = 'wakeup_auth_token_v1';

  /// 已同步的 WakeUp 课程表原始数据。
  static const wakeUpScheduleData = 'wakeup_schedule_data_v1';

  /// WakeUp 课程表同步时间。
  static const wakeUpScheduleSyncedAt = 'wakeup_schedule_synced_at_v1';

  /// 自定义复制格式模板。
  static const attendanceCopyTemplate = 'attendance_copy_template_v2';

  /// 自定义扩展字段的名称列表。
  static const personFields = 'person_fields_v1';

  /// 保存的考勤历史记录。
  static const attendanceHistory = 'attendance_history_v1';

  /// 参与备份 / 还原的键。
  ///
  /// `wakeUpAuthToken` 是账号凭据，刻意排除，避免备份文件被转发后泄露；
  /// 还原课程表后重新同步一次即可补回。
  static const backupKeys = <String>[
    people,
    hasImportedRoster,
    lastModified,
    wakeUpScheduleData,
    wakeUpScheduleSyncedAt,
    attendanceCopyTemplate,
    personFields,
    attendanceHistory,
  ];
}
