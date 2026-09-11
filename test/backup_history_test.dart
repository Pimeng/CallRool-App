import 'dart:convert';

import 'package:callrool_app/models/attendance.dart';
import 'package:callrool_app/models/attendance_record.dart';
import 'package:callrool_app/models/person.dart';
import 'package:callrool_app/services/attendance_history_store.dart';
import 'package:callrool_app/services/backup_service.dart';
import 'package:callrool_app/services/storage_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _roundTrip(Object? value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

AttendanceRecord _record({List<AttendanceRecordEntry>? entries}) =>
    AttendanceRecord(
      id: 'r1',
      savedAt: DateTime(2026, 9, 12, 10, 30),
      note: '高等数学',
      courseName: '高等数学',
      teacher: '王老师',
      room: 'A101',
      timeRange: '08:00-09:40',
      entries:
          entries ??
          const [
            AttendanceRecordEntry(
              personId: 1,
              name: '张三',
              status: AttendanceStatus.present,
              fields: {'宿舍': '101'},
            ),
            AttendanceRecordEntry(
              personId: 2,
              name: '李四',
              status: AttendanceStatus.truancy,
            ),
            AttendanceRecordEntry(
              personId: 3,
              name: '王五',
              status: AttendanceStatus.unmarked,
            ),
          ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('人员扩展字段', () {
    test('序列化保留扩展字段，并加入搜索索引', () {
      final person = Person(
        id: 1,
        name: '张三',
        fields: const {'宿舍': '101', '学号': '20230001'},
      );
      final restored = Person.fromJson(_roundTrip(person.toJson()));

      expect(restored.fields, {'宿舍': '101', '学号': '20230001'});
      expect(restored.searchText, contains('20230001'));
      expect(restored.searchText, contains('101'));
      expect(restored.fieldSummary, '宿舍 101 · 学号 20230001');
    });

    test('没有扩展字段时不写入 fields 键', () {
      expect(Person(id: 1, name: '张三').toJson().containsKey('fields'), isFalse);
    });

    test('字段名规范化：去空白、丢空名、去重', () {
      expect(normalizePersonFields([' 宿舍 ', '学号', '宿舍', '', '  ']), [
        '宿舍',
        '学号',
      ]);
    });

    test('字段摘要忽略空值', () {
      final person = Person(id: 1, name: '张三', fields: const {'宿舍': '  '});
      expect(person.fieldSummary, isEmpty);
      expect(person.searchText, isNot(contains('宿舍')));
    });

    test('解码容错：非 Map 输入返回空字段', () {
      expect(decodePersonFields(null), isEmpty);
      expect(decodePersonFields(['宿舍']), isEmpty);
    });
  });

  group('考勤记录模型', () {
    test('JSON 往返保持一致', () {
      final restored = AttendanceRecord.fromJson(_roundTrip(_record().toJson()));

      expect(restored.note, '高等数学');
      expect(restored.savedAt, DateTime(2026, 9, 12, 10, 30));
      expect(restored.entries.length, 3);
      expect(restored.entries.first.fields, {'宿舍': '101'});
      expect(restored.courseSummary, '高等数学｜王老师｜A101｜08:00-09:40');
    });

    test('统计应到、实到、请假、异常与未点名', () {
      final record = _record(
        entries: const [
          AttendanceRecordEntry(
            personId: 1,
            name: '张三',
            status: AttendanceStatus.present,
          ),
          AttendanceRecordEntry(
            personId: 2,
            name: '李四',
            status: AttendanceStatus.late,
          ),
          AttendanceRecordEntry(
            personId: 3,
            name: '王五',
            status: AttendanceStatus.sickLeave,
          ),
          AttendanceRecordEntry(
            personId: 4,
            name: '赵六',
            status: AttendanceStatus.truancy,
          ),
          AttendanceRecordEntry(
            personId: 5,
            name: '孙七',
            status: AttendanceStatus.unmarked,
          ),
        ],
      );

      expect(record.total, 5);
      expect(record.presentCount, 2); // 正常 + 迟到
      expect(record.leaveCount, 1);
      expect(record.issueCount, 2); // 迟到 + 旷课
      expect(record.unmarkedCount, 1);
    });

    test('没有任何课程信息时 courseSummary 为 null', () {
      final record = AttendanceRecord(
        id: 'r',
        savedAt: DateTime(2026, 9, 12),
        note: 'x',
        entries: const [],
      );
      expect(record.courseSummary, isNull);
    });
  });

  group('考勤历史存储', () {
    test('编解码往返', () {
      final encoded = AttendanceHistoryStore.encode([_record()]);
      final decoded = AttendanceHistoryStore.decode(encoded);
      expect(decoded.length, 1);
      expect(decoded.first.note, '高等数学');
    });

    test('损坏或空数据返回空列表', () {
      expect(AttendanceHistoryStore.decode(null), isEmpty);
      expect(AttendanceHistoryStore.decode('not json'), isEmpty);
      expect(AttendanceHistoryStore.decode('{"a":1}'), isEmpty);
    });
  });

  group('备份与还原', () {
    test('导出内容包含白名单数据，但不含登录凭据', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.people: jsonEncode([
          Person(id: 1, name: '张三', fields: const {'学号': '1'}).toJson(),
        ]),
        StorageKeys.personFields: jsonEncode(['学号']),
        StorageKeys.attendanceHistory: AttendanceHistoryStore.encode([_record()]),
        StorageKeys.wakeUpAuthToken: 'super-secret',
      });

      final raw = await BackupService.export();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>;

      expect(decoded['format'], 'callrool_app_backup');
      expect(data.containsKey(StorageKeys.people), isTrue);
      expect(data.containsKey(StorageKeys.attendanceHistory), isTrue);
      expect(data.containsKey(StorageKeys.wakeUpAuthToken), isFalse);

      final summary = BackupService.inspect(raw);
      expect(summary.peopleCount, 1);
      expect(summary.historyCount, 1);
    });

    test('还原可以恢复数据', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.people: jsonEncode([Person(id: 1, name: '张三').toJson()]),
        StorageKeys.personFields: jsonEncode(['学号']),
      });
      final raw = await BackupService.export();

      SharedPreferences.setMockInitialValues({});
      final summary = await BackupService.restore(raw);

      expect(summary.peopleCount, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.people), contains('张三'));
      expect(prefs.getString(StorageKeys.personFields), jsonEncode(['学号']));
    });

    test('覆盖还原会清掉备份中没有的键', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.people: jsonEncode([Person(id: 1, name: '张三').toJson()]),
      });
      final raw = await BackupService.export();

      SharedPreferences.setMockInitialValues({
        StorageKeys.attendanceHistory: AttendanceHistoryStore.encode([
          _record(),
        ]),
      });
      await BackupService.restore(raw);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.attendanceHistory), isNull);
    });

    test('拒绝非本应用的备份文件', () {
      expect(
        () => BackupService.inspect(jsonEncode({'format': 'other'})),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => BackupService.inspect('不是 JSON'),
        throwsA(isA<BackupException>()),
      );
    });

    test('currentSummary 反映本机数据规模', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.people: jsonEncode([
          Person(id: 1, name: '张三').toJson(),
          Person(id: 2, name: '李四').toJson(),
        ]),
        StorageKeys.attendanceHistory: AttendanceHistoryStore.encode([_record()]),
      });

      final summary = await BackupService.currentSummary();
      expect(summary.peopleCount, 2);
      expect(summary.historyCount, 1);
      expect(summary.hasSchedule, isFalse);
    });
  });
}
