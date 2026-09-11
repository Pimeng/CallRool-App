import 'package:lpinyin/lpinyin.dart';

import 'attendance.dart';

/// 「编辑名单」里默认提供的扩展字段，用户可自行增删。
const kDefaultPersonFields = <String>['宿舍', '学号'];

/// 规范化扩展字段名：去首尾空白、丢弃空名、按首次出现顺序去重。
List<String> normalizePersonFields(Iterable<String> names) {
  final seen = <String>{};
  return [
    for (final name in names)
      if (name.trim().isNotEmpty && seen.add(name.trim())) name.trim(),
  ];
}

class Person {
  Person({
    required this.id,
    required this.name,
    this.status = AttendanceStatus.unmarked,
    Map<String, String>? fields,
  }) : fields = fields ?? <String, String>{};
  final int id;
  final String name;
  AttendanceStatus status;

  /// 自定义扩展字段（如宿舍、学号），键为字段名。
  ///
  /// 修改内容时请整体替换 [Person]，不要就地改动这个 Map —— [searchText]
  /// 会缓存搜索结果，就地修改会让索引失效。
  final Map<String, String> fields;
  late final String fullPinyin = PinyinHelper.getPinyinE(
    name,
    separator: '',
  ).toLowerCase();
  late final String pinyinInitials = PinyinHelper.getShortPinyin(name)
      .toLowerCase();

  /// 搜索索引：姓名、全拼、拼音首字母以及所有非空扩展字段值。
  late final String searchText = [
    name.toLowerCase(),
    fullPinyin,
    pinyinInitials,
    for (final value in fields.values)
      if (value.trim().isNotEmpty) value.toLowerCase(),
  ].join('\u0000');

  /// 形如 `宿舍 101 · 学号 20230001` 的字段摘要，没有有效字段时返回空串。
  String get fieldSummary => [
    for (final entry in fields.entries)
      if (entry.value.trim().isNotEmpty) '${entry.key} ${entry.value.trim()}',
  ].join(' · ');

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'status': status.name,
    if (fields.isNotEmpty) 'fields': fields,
  };
  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as int,
    name: json['name'] as String,
    status: AttendanceStatus.values.firstWhere(
      (status) => status.name == json['status'],
      orElse: () => AttendanceStatus.unmarked,
    ),
    fields: decodePersonFields(json['fields']),
  );
}

/// 解析人员扩展字段，容错处理缺失或类型不符的输入。
Map<String, String> decodePersonFields(Object? raw) {
  if (raw is! Map) return <String, String>{};
  final result = <String, String>{};
  raw.forEach((key, value) {
    if (value == null) return;
    final name = key.toString().trim();
    if (name.isEmpty) return;
    result[name] = value.toString();
  });
  return result;
}
