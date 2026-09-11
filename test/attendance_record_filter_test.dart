import 'package:callrool_app/models/attendance.dart';
import 'package:callrool_app/models/attendance_record.dart';
import 'package:callrool_app/models/attendance_record_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 12, 15, 30);

AttendanceRecord _record({
  required String id,
  required DateTime savedAt,
  String? courseName,
  String? teacher,
  String? room,
  String? note,
}) => AttendanceRecord(
  id: id,
  savedAt: savedAt,
  note: note ?? (courseName ?? '未关联课程'),
  courseName: courseName,
  teacher: teacher,
  room: room,
  entries: const [
    AttendanceRecordEntry(
      personId: 1,
      name: '张三',
      status: AttendanceStatus.present,
    ),
  ],
);

/// 三条记录：今天 / 4 天前 / 12 天前，其中最后一条没有课程信息。
final _today = _record(
  id: 'today',
  savedAt: DateTime(2026, 9, 12, 9),
  courseName: '高等数学',
  teacher: '王老师',
  room: 'A101',
);
final _fewDaysAgo = _record(
  id: 'few',
  savedAt: DateTime(2026, 9, 8, 9),
  courseName: '大学英语',
  teacher: '李老师',
  room: 'B202',
);
final _longAgo = _record(id: 'long', savedAt: DateTime(2026, 8, 31, 9));
final _all = [_today, _fewDaysAgo, _longAgo];

List<String> _ids(List<AttendanceRecord> records) =>
    records.map((record) => record.id).toList();

void main() {
  group('默认与激活状态', () {
    test('没有条件时不改动列表', () {
      const filter = AttendanceRecordFilter.empty;
      expect(filter.isActive, isFalse);
      expect(filter.activeCount, 0);
      expect(_ids(filter.apply(_all, now: _now)), ['today', 'few', 'long']);
    });

    test('activeCount 统计生效的维度数量', () {
      final filter = AttendanceRecordFilter.empty
          .withKeyword('王')
          .withCourses({'高等数学'})
          .withDate(RecordDatePreset.today);
      expect(filter.isActive, isTrue);
      expect(filter.activeCount, 3);
    });
  });

  group('课程筛选', () {
    test('多选课程时命中任意一个即可', () {
      final filter = AttendanceRecordFilter.empty.withCourses({
        '高等数学',
        '大学英语',
      });
      expect(_ids(filter.apply(_all, now: _now)), ['today', 'few']);
    });

    test('单选课程只保留匹配记录', () {
      final filter = AttendanceRecordFilter.empty.withCourses({'大学英语'});
      expect(_ids(filter.apply(_all, now: _now)), ['few']);
    });

    test('没有课程信息的记录归入「未关联课程」', () {
      final filter = AttendanceRecordFilter.empty.withCourses({noCourseLabel});
      expect(_ids(filter.apply(_all, now: _now)), ['long']);
      expect(AttendanceRecordFilter.courseKeyOf(_longAgo), noCourseLabel);
    });

    test('courseOptions 去重、升序，且「未关联课程」排在最后', () {
      expect(AttendanceRecordFilter.courseOptions(_all), [
        '大学英语',
        '高等数学',
        noCourseLabel,
      ]);
    });

    test('课程名只有空白时视为未关联课程', () {
      final record = _record(
        id: 'blank',
        savedAt: DateTime(2026, 9, 12),
        courseName: '   ',
      );
      expect(AttendanceRecordFilter.courseKeyOf(record), noCourseLabel);
    });
  });

  group('日期筛选', () {
    test('今天只保留当天记录', () {
      final filter = AttendanceRecordFilter.empty.withDate(
        RecordDatePreset.today,
      );
      expect(_ids(filter.apply(_all, now: _now)), ['today']);
    });

    test('近 7 天包含今天在内共 7 天', () {
      final filter = AttendanceRecordFilter.empty.withDate(
        RecordDatePreset.last7,
      );
      expect(_ids(filter.apply(_all, now: _now)), ['today', 'few']);
      final range = filter.resolveRange(_now)!;
      expect(range.start, DateTime(2026, 9, 6));
      expect(range.end, DateTime(2026, 9, 12));
    });

    test('近 30 天包含更早的记录', () {
      final filter = AttendanceRecordFilter.empty.withDate(
        RecordDatePreset.last30,
      );
      expect(_ids(filter.apply(_all, now: _now)), ['today', 'few', 'long']);
    });

    test('自定义范围按天包含首尾', () {
      final filter = AttendanceRecordFilter.empty.withDate(
        RecordDatePreset.custom,
        custom: DateTimeRange(
          start: DateTime(2026, 9, 8),
          end: DateTime(2026, 9, 8),
        ),
      );
      expect(_ids(filter.apply(_all, now: _now)), ['few']);
    });

    test('自定义范围会忽略时间部分，只按日期比较', () {
      final filter = AttendanceRecordFilter.empty.withDate(
        RecordDatePreset.custom,
        custom: DateTimeRange(
          start: DateTime(2026, 9, 12, 23, 59),
          end: DateTime(2026, 9, 12, 23, 59),
        ),
      );
      expect(_ids(filter.apply(_all, now: _now)), ['today']);
    });

    test('选了自定义但还没挑范围时不生效', () {
      final filter = AttendanceRecordFilter.empty.withDate(
        RecordDatePreset.custom,
      );
      expect(filter.hasDateFilter, isTrue);
      expect(filter.resolveRange(_now), isNull);
      expect(_ids(filter.apply(_all, now: _now)), ['today', 'few', 'long']);
    });

    test('全部日期不限制', () {
      final filter = AttendanceRecordFilter.empty.withDate(
        RecordDatePreset.all,
        custom: DateTimeRange(
          start: DateTime(2026, 9, 12),
          end: DateTime(2026, 9, 12),
        ),
      );
      expect(filter.resolveRange(_now), isNull);
      expect(_ids(filter.apply(_all, now: _now)), ['today', 'few', 'long']);
    });
  });

  group('关键词筛选', () {
    test('匹配备注、课程、教师与教室', () {
      for (final keyword in ['高等数学', '王老师', 'A101']) {
        final filter = AttendanceRecordFilter.empty.withKeyword(keyword);
        expect(_ids(filter.apply(_all, now: _now)), ['today'], reason: keyword);
      }
    });

    test('大小写不敏感且忽略首尾空白', () {
      final filter = AttendanceRecordFilter.empty.withKeyword('  b202  ');
      expect(_ids(filter.apply(_all, now: _now)), ['few']);
    });

    test('纯空白关键词视为未设置', () {
      final filter = AttendanceRecordFilter.empty.withKeyword('   ');
      expect(filter.hasKeyword, isFalse);
      expect(_ids(filter.apply(_all, now: _now)), ['today', 'few', 'long']);
    });

    test('没有匹配时返回空列表', () {
      final filter = AttendanceRecordFilter.empty.withKeyword('不存在的课程');
      expect(filter.apply(_all, now: _now), isEmpty);
    });
  });

  group('多条件组合', () {
    test('课程与日期按「与」组合', () {
      final filter = AttendanceRecordFilter.empty
          .withCourses({'高等数学', '大学英语'})
          .withDate(RecordDatePreset.today);
      expect(_ids(filter.apply(_all, now: _now)), ['today']);
    });

    test('课程、日期与关键词三者同时生效', () {
      final filter = AttendanceRecordFilter.empty
          .withCourses({'高等数学'})
          .withDate(RecordDatePreset.last7)
          .withKeyword('A101');
      expect(_ids(filter.apply(_all, now: _now)), ['today']);

      final noMatch = filter.withKeyword('李老师');
      expect(noMatch.apply(_all, now: _now), isEmpty);
    });
  });

  group('按钮文案', () {
    test('课程文案随选择变化', () {
      expect(AttendanceRecordFilter.empty.courseLabel, '全部课程');
      expect(
        AttendanceRecordFilter.empty.withCourses({'高等数学'}).courseLabel,
        '高等数学',
      );
      expect(
        AttendanceRecordFilter.empty.withCourses({'高等数学', '大学英语'}).courseLabel,
        '已选 2 个课程',
      );
    });

    test('日期文案随预设变化', () {
      expect(AttendanceRecordFilter.empty.dateLabel, '全部日期');
      expect(
        AttendanceRecordFilter.empty.withDate(RecordDatePreset.last7).dateLabel,
        '近 7 天',
      );
      expect(
        AttendanceRecordFilter.empty
            .withDate(
              RecordDatePreset.custom,
              custom: DateTimeRange(
                start: DateTime(2026, 9, 1),
                end: DateTime(2026, 9, 12),
              ),
            )
            .dateLabel,
        '2026/9/1 - 2026/9/12',
      );
      expect(
        AttendanceRecordFilter.empty
            .withDate(RecordDatePreset.custom)
            .dateLabel,
        '选择日期范围',
      );
    });
  });
}
