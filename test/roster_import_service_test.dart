import 'dart:io';
import 'dart:typed_data';

import 'package:callrool_app/services/roster_import_service.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('文本名单在预览前去除空行和重复姓名', () {
    final draft = parseRosterText('张三\n\n李四\n张三\n');

    expect(draft.names, ['张三', '李四']);
    expect(draft.duplicateCount, 1);
    expect(draft.ignoredRowCount, 2);
  });

  test('电子表格自动识别姓名表头并跳过示例行', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([TextCellValue('2026级新生花名册')]);
    sheet.appendRow([
      TextCellValue('序号'),
      TextCellValue('姓名'),
      TextCellValue('性别'),
      TextCellValue('宿舍号\n（x栋xxx）'),
      TextCellValue('学生电话'),
    ]);
    sheet.appendRow([
      TextCellValue('例'),
      TextCellValue('示例同学'),
      TextCellValue('男'),
      TextCellValue('示例宿舍'),
      TextCellValue('10000'),
    ]);
    sheet.appendRow([
      IntCellValue(1),
      TextCellValue('张三'),
      TextCellValue('男'),
      TextCellValue('13栋214'),
      IntCellValue(13800138000),
    ]);
    sheet.appendRow([
      null,
      TextCellValue('李四'),
      TextCellValue('女'),
      null,
      IntCellValue(13900139000),
    ]);
    sheet.appendRow([
      IntCellValue(3),
      TextCellValue('张三'),
      TextCellValue('男'),
      TextCellValue('重复宿舍'),
      IntCellValue(13700137000),
    ]);

    final bytes = Uint8List.fromList(workbook.save()!);
    final draft = parseRosterFile('名单.xlsx', bytes);

    expect(draft.names, ['张三', '李四']);
    expect(draft.fieldNames, ['性别', '宿舍', '学生电话']);
    expect(draft.people.first.fields, {
      '性别': '男',
      '宿舍': '13栋214',
      '学生电话': '13800138000',
    });
    expect(draft.people.last.fields, {'性别': '女', '学生电话': '13900139000'});
    expect(draft.sourceDescription, 'Sheet1，第 2 行为表头');
    expect(draft.duplicateCount, 1);
    expect(draft.ignoredRowCount, 1);
  });

  test('电子表格没有姓名表头时给出明确错误', () {
    final workbook = Excel.createExcel();
    workbook['Sheet1'].appendRow([TextCellValue('序号'), TextCellValue('家长姓名')]);
    final bytes = Uint8List.fromList(workbook.save()!);

    expect(
      () => parseRosterFile('名单.xlsx', bytes),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('没有找到“姓名”列'),
        ),
      ),
    );
  });

  test('旧版 XLS 二进制文件使用同一套名单识别规则', () {
    final bytes = Uint8List.fromList(
      File('test/fixtures/roster_preview.xls').readAsBytesSync(),
    );

    final draft = parseRosterFile('名单.xls', bytes);

    expect(draft.names, ['张三', '李四']);
    expect(draft.fieldNames, ['性别']);
    expect(draft.people.first.fields, {'性别': '男'});
    expect(draft.sourceDescription, '花名册，第 2 行为表头');
    expect(draft.duplicateCount, 1);
    expect(draft.ignoredRowCount, 1);
  });
}
