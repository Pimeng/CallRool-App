import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

class RosterImportPerson {
  const RosterImportPerson({required this.name, this.fields = const {}});

  final String name;
  final Map<String, String> fields;
}

class RosterImportDraft {
  const RosterImportDraft({
    required this.people,
    required this.fieldNames,
    required this.sourceDescription,
    this.duplicateCount = 0,
    this.ignoredRowCount = 0,
  });

  final List<RosterImportPerson> people;
  final List<String> fieldNames;
  final String sourceDescription;
  final int duplicateCount;
  final int ignoredRowCount;

  List<String> get names => [for (final person in people) person.name];
}

RosterImportDraft parseRosterText(String text) {
  final seen = <String>{};
  final people = <RosterImportPerson>[];
  var duplicateCount = 0;
  var ignoredRowCount = 0;
  for (final line in text.replaceAll('\r', '').split('\n')) {
    final name = line.trim();
    if (name.isEmpty) {
      ignoredRowCount++;
      continue;
    }
    if (!seen.add(name.toLowerCase())) {
      duplicateCount++;
      continue;
    }
    people.add(RosterImportPerson(name: name));
  }
  return RosterImportDraft(
    people: List.unmodifiable(people),
    fieldNames: const [],
    sourceDescription: '文本名单',
    duplicateCount: duplicateCount,
    ignoredRowCount: ignoredRowCount,
  );
}

RosterImportDraft parseRosterFile(String fileName, Uint8List bytes) {
  final extension = fileName.split('.').last.toLowerCase();
  if (extension == 'txt') {
    return parseRosterText(utf8.decode(bytes, allowMalformed: true));
  }
  if (extension != 'xls' && extension != 'xlsx') {
    throw const FormatException('仅支持 TXT、XLS 或 XLSX 名单文件');
  }
  return _parseSpreadsheet(bytes);
}

RosterImportDraft parseRosterFileRequest((String, Uint8List) request) =>
    parseRosterFile(request.$1, request.$2);

RosterImportDraft _parseSpreadsheet(Uint8List bytes) {
  final workbook = Excel.decodeBytes(bytes);
  _HeaderCandidate? best;
  for (final entry in workbook.tables.entries) {
    final sheet = entry.value;
    final rowsToScan = sheet.rows.length < 20 ? sheet.rows.length : 20;
    for (var rowIndex = 0; rowIndex < rowsToScan; rowIndex++) {
      final row = sheet.rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
        if (!_isNameHeader(_cellText(row[columnIndex]))) continue;
        final score =
            10 +
            row.where((cell) {
              final header = _normalizeHeader(_cellText(cell));
              return const {
                '序号',
                '性别',
                '学号',
                '学生电话',
                '宿舍',
                '宿舍号',
              }.contains(header);
            }).length;
        final candidate = _HeaderCandidate(
          sheetName: entry.key,
          sheet: sheet,
          rowIndex: rowIndex,
          nameColumnIndex: columnIndex,
          score: score,
        );
        if (best == null || candidate.score > best.score) best = candidate;
      }
    }
  }
  if (best == null) {
    throw const FormatException('没有找到“姓名”列，请确认文件包含姓名表头');
  }

  final headerRow = best.sheet.rows[best.rowIndex];
  final fieldColumns = <_FieldColumn>[];
  final seenFieldNames = <String>{};
  for (var columnIndex = 0; columnIndex < headerRow.length; columnIndex++) {
    if (columnIndex == best.nameColumnIndex) continue;
    final fieldName = _fieldName(_cellText(headerRow[columnIndex]));
    if (fieldName.isEmpty || !seenFieldNames.add(fieldName)) continue;
    fieldColumns.add(_FieldColumn(index: columnIndex, name: fieldName));
  }

  final people = <RosterImportPerson>[];
  final seen = <String>{};
  var duplicateCount = 0;
  var ignoredRowCount = 0;
  var lastNamedRow = best.rowIndex;
  for (
    var rowIndex = best.rowIndex + 1;
    rowIndex < best.sheet.rows.length;
    rowIndex++
  ) {
    final row = best.sheet.rows[rowIndex];
    if (best.nameColumnIndex < row.length &&
        _cellText(row[best.nameColumnIndex]).trim().isNotEmpty) {
      lastNamedRow = rowIndex;
    }
  }
  for (var rowIndex = best.rowIndex + 1; rowIndex <= lastNamedRow; rowIndex++) {
    final row = best.sheet.rows[rowIndex];
    final firstCell = row.isEmpty ? '' : _normalizeHeader(_cellText(row.first));
    if (const {'例', '示例', '样例'}.contains(firstCell)) {
      ignoredRowCount++;
      continue;
    }
    final name = best.nameColumnIndex < row.length
        ? _cellText(row[best.nameColumnIndex]).trim()
        : '';
    if (name.isEmpty) {
      ignoredRowCount++;
      continue;
    }
    if (!seen.add(name.toLowerCase())) {
      duplicateCount++;
      continue;
    }
    final fields = <String, String>{};
    for (final fieldColumn in fieldColumns) {
      if (fieldColumn.index >= row.length) continue;
      final value = _cellText(row[fieldColumn.index]).trim();
      if (value.isNotEmpty) fields[fieldColumn.name] = value;
    }
    people.add(
      RosterImportPerson(name: name, fields: Map.unmodifiable(fields)),
    );
  }
  if (people.isEmpty) {
    throw const FormatException('找到了“姓名”列，但没有可导入的姓名');
  }
  final populatedFieldNames = [
    for (final column in fieldColumns)
      if (people.any((person) => person.fields.containsKey(column.name)))
        column.name,
  ];
  return RosterImportDraft(
    people: List.unmodifiable(people),
    fieldNames: List.unmodifiable(populatedFieldNames),
    sourceDescription: '${best.sheetName}，第 ${best.rowIndex + 1} 行为表头',
    duplicateCount: duplicateCount,
    ignoredRowCount: ignoredRowCount,
  );
}

String _cellText(Data? cell) {
  final value = cell?.value;
  return switch (value) {
    null => '',
    TextCellValue(value: final text) => text.toString(),
    IntCellValue(value: final number) => number.toString(),
    DoubleCellValue(value: final number) =>
      number == number.truncateToDouble()
          ? number.toInt().toString()
          : number.toString(),
    BoolCellValue(value: final boolean) => boolean.toString(),
    _ => value.toString(),
  };
}

String _normalizeHeader(String value) => value
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'[（）():：]'), '')
    .trim();

bool _isNameHeader(String value) =>
    const {'姓名', '名字', '学生姓名', '成员姓名'}.contains(_normalizeHeader(value));

String _fieldName(String rawHeader) {
  final firstLine = rawHeader.split(RegExp(r'[\r\n]')).first.trim();
  final withoutInstructions = firstLine.split(RegExp(r'[（(]')).first.trim();
  final normalized = withoutInstructions.replaceAll(RegExp(r'\s+'), '');
  return switch (normalized) {
    '' || '序号' || '编号' || '姓名' || '名字' || '学生姓名' || '成员姓名' => '',
    '身份证证号' => '身份证号',
    '宿舍号' || '寝室号' => '宿舍',
    _ => normalized,
  };
}

class _FieldColumn {
  const _FieldColumn({required this.index, required this.name});

  final int index;
  final String name;
}

class _HeaderCandidate {
  const _HeaderCandidate({
    required this.sheetName,
    required this.sheet,
    required this.rowIndex,
    required this.nameColumnIndex,
    required this.score,
  });

  final String sheetName;
  final Sheet sheet;
  final int rowIndex;
  final int nameColumnIndex;
  final int score;
}
