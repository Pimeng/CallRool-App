import 'package:flutter/material.dart';

import 'attendance_record.dart';

/// 没有关联课程信息的记录，在筛选时归到这个虚拟课程名。
const noCourseLabel = '未关联课程';

/// 考勤记录列表的日期快捷筛选项。
enum RecordDatePreset {
  all('全部日期'),
  today('今天'),
  last7('近 7 天'),
  last30('近 30 天'),
  custom('自定义范围');

  const RecordDatePreset(this.label);

  final String label;
}

/// 考勤记录的筛选条件。
///
/// 三个维度各自独立、彼此按「与」组合：
/// - [courses]：课程名多选，命中任意一个即可（空表示不限）；
/// - [preset] / [customRange]：日期范围，按天比较（含首尾）；
/// - [keyword]：关键词，匹配备注、课程名、教师或教室。
@immutable
class AttendanceRecordFilter {
  const AttendanceRecordFilter({
    this.courses = const <String>{},
    this.keyword = '',
    this.preset = RecordDatePreset.all,
    this.customRange,
  });

  static const empty = AttendanceRecordFilter();

  final Set<String> courses;
  final String keyword;
  final RecordDatePreset preset;
  final DateTimeRange? customRange;

  bool get hasCourseFilter => courses.isNotEmpty;
  bool get hasDateFilter => preset != RecordDatePreset.all;
  bool get hasKeyword => keyword.trim().isNotEmpty;

  bool get isActive => hasCourseFilter || hasDateFilter || hasKeyword;

  int get activeCount =>
      (hasCourseFilter ? 1 : 0) +
      (hasDateFilter ? 1 : 0) +
      (hasKeyword ? 1 : 0);

  AttendanceRecordFilter withKeyword(String value) => AttendanceRecordFilter(
    courses: courses,
    keyword: value,
    preset: preset,
    customRange: customRange,
  );

  AttendanceRecordFilter withCourses(Set<String> value) =>
      AttendanceRecordFilter(
        courses: Set.unmodifiable(value),
        keyword: keyword,
        preset: preset,
        customRange: customRange,
      );

  AttendanceRecordFilter withDate(
    RecordDatePreset value, {
    DateTimeRange? custom,
  }) => AttendanceRecordFilter(
    courses: courses,
    keyword: keyword,
    preset: value,
    customRange: custom ?? customRange,
  );

  /// 记录所属的课程分类：没有课程名时归入 [noCourseLabel]。
  static String courseKeyOf(AttendanceRecord record) {
    final name = record.courseName?.trim() ?? '';
    return name.isEmpty ? noCourseLabel : name;
  }

  /// 记录里出现过的课程分类，用于生成课程筛选列表（[noCourseLabel] 排在最后）。
  static List<String> courseOptions(Iterable<AttendanceRecord> records) {
    final options = <String>{};
    for (final record in records) {
      options.add(courseKeyOf(record));
    }
    final sorted = options.toList()..sort();
    if (sorted.remove(noCourseLabel)) sorted.add(noCourseLabel);
    return sorted;
  }

  /// 解析成具体的日期区间；不限日期或自定义范围缺失时返回 null。
  DateTimeRange? resolveRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case RecordDatePreset.all:
        return null;
      case RecordDatePreset.today:
        return DateTimeRange(start: today, end: today);
      case RecordDatePreset.last7:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case RecordDatePreset.last30:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case RecordDatePreset.custom:
        final range = customRange;
        if (range == null) return null;
        return DateTimeRange(
          start: DateTime(range.start.year, range.start.month, range.start.day),
          end: DateTime(range.end.year, range.end.month, range.end.day),
        );
    }
  }

  bool matches(AttendanceRecord record, {DateTime? now}) {
    if (hasCourseFilter && !courses.contains(courseKeyOf(record))) return false;
    if (hasDateFilter && !_matchesDate(record, now ?? DateTime.now())) {
      return false;
    }
    return _matchesKeyword(record);
  }

  List<AttendanceRecord> apply(Iterable<AttendanceRecord> records, {DateTime? now}) {
    if (!isActive) return List.of(records);
    final reference = now ?? DateTime.now();
    return [
      for (final record in records)
        if (matches(record, now: reference)) record,
    ];
  }

  bool _matchesDate(AttendanceRecord record, DateTime now) {
    final range = resolveRange(now);
    if (range == null) return true;
    final day = DateTime(
      record.savedAt.year,
      record.savedAt.month,
      record.savedAt.day,
    );
    return !day.isBefore(range.start) && !day.isAfter(range.end);
  }

  bool _matchesKeyword(AttendanceRecord record) {
    final keyword = this.keyword.trim().toLowerCase();
    if (keyword.isEmpty) return true;
    final haystack = [
      record.note,
      record.courseName ?? '',
      record.teacher ?? '',
      record.room ?? '',
    ].join('\n').toLowerCase();
    return haystack.contains(keyword);
  }

  /// 课程筛选按钮上的文案。
  String get courseLabel {
    if (courses.isEmpty) return '全部课程';
    if (courses.length == 1) return courses.first;
    return '已选 ${courses.length} 个课程';
  }

  /// 日期筛选按钮上的文案。
  String get dateLabel {
    switch (preset) {
      case RecordDatePreset.all:
        return RecordDatePreset.all.label;
      case RecordDatePreset.custom:
        final range = customRange;
        if (range == null) return '选择日期范围';
        return '${_formatDay(range.start)} - ${_formatDay(range.end)}';
      case RecordDatePreset.today:
      case RecordDatePreset.last7:
      case RecordDatePreset.last30:
        return preset.label;
    }
  }
}

String _formatDay(DateTime value) => '${value.year}/${value.month}/${value.day}';
