import 'dart:convert';

import 'person.dart';

/// 名单排序方向。
enum RosterSortDirection { ascending, descending }

/// 名单排序依据。
enum RosterSortKind {
  /// 用户手动拖拽出来的顺序（默认，不额外排序）。
  manual,

  /// 按姓名拼音排序。
  name,

  /// 按某个自定义扩展字段（宿舍、学号……）排序。
  field,
}

/// 主页名单的排序设置（依据 + 方向）。
///
/// 排序只影响展示顺序，不会改动 [Person] 在名单里的真实次序（「第 N 号」）。
class RosterSort {
  const RosterSort({
    this.kind = RosterSortKind.manual,
    this.fieldName,
    this.direction = RosterSortDirection.ascending,
  });

  /// 排序依据。
  final RosterSortKind kind;

  /// [kind] 为 [RosterSortKind.field] 时按哪个字段排序。
  final String? fieldName;

  /// 升序 / 降序。
  final RosterSortDirection direction;

  bool get isManual => kind == RosterSortKind.manual;

  bool get isAscending => direction == RosterSortDirection.ascending;

  /// 展示给用户看的名称（如「默认顺序」「姓名」「宿舍」）。
  String get label => switch (kind) {
    RosterSortKind.manual => '默认顺序',
    RosterSortKind.name => '姓名',
    RosterSortKind.field =>
      (fieldName == null || fieldName!.isEmpty) ? '字段' : fieldName!,
  };

  static const Object _fieldNameUnset = Object();

  RosterSort copyWith({
    RosterSortKind? kind,
    Object? fieldName = _fieldNameUnset,
    RosterSortDirection? direction,
  }) => RosterSort(
    kind: kind ?? this.kind,
    fieldName: identical(fieldName, _fieldNameUnset)
        ? this.fieldName
        : fieldName as String?,
    direction: direction ?? this.direction,
  );

  /// 存储编码，便于以后扩展字段名里的特殊字符。
  String toStorage() => jsonEncode({
    'kind': kind.name,
    'field': fieldName,
    'direction': direction.name,
  });

  /// 解析存储值，任何异常输入都退化成默认顺序。
  static RosterSort decode(String? raw) {
    if (raw == null || raw.isEmpty) return const RosterSort();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const RosterSort();
      final kind = RosterSortKind.values.firstWhere(
        (value) => value.name == decoded['kind'],
        orElse: () => RosterSortKind.manual,
      );
      final direction = RosterSortDirection.values.firstWhere(
        (value) => value.name == decoded['direction'],
        orElse: () => RosterSortDirection.ascending,
      );
      final fieldName = decoded['field'];
      return RosterSort(
        kind: kind,
        fieldName: fieldName is String && fieldName.isNotEmpty
            ? fieldName
            : null,
        direction: direction,
      );
    } catch (_) {
      return const RosterSort();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RosterSort &&
      other.kind == kind &&
      other.fieldName == fieldName &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(kind, fieldName, direction);

  @override
  String toString() => 'RosterSort($label, $direction)';
}

/// 取某人在某个排序依据下的比较值；返回 null / 空串表示该字段没有内容。
String? rosterSortValue(Person person, RosterSort sort) => switch (sort.kind) {
  RosterSortKind.manual => null,
  RosterSortKind.name => person.fullPinyin,
  RosterSortKind.field =>
    sort.fieldName == null ? null : person.fields[sort.fieldName!],
};

/// 按 [sort] 比较两个人。
///
/// - 缺失值（没有填该字段）无论升序降序都排在最后；
/// - 值内部带数字时按数值比较（比如「10 栋」排在「2 栋」之后）；
/// - 完全相等时回退到名单序号，保证顺序稳定。
int comparePeopleBySort(Person a, Person b, RosterSort sort) {
  final valueA = rosterSortValue(a, sort);
  final valueB = rosterSortValue(b, sort);
  final missingA = valueA == null || valueA.trim().isEmpty;
  final missingB = valueB == null || valueB.trim().isEmpty;
  if (missingA || missingB) {
    if (missingA && missingB) return 0;
    return missingA ? 1 : -1;
  }
  final result = compareNatural(valueA, valueB);
  if (result == 0) return 0;
  return sort.isAscending ? result : -result;
}

/// 自然排序比较：数字片段按数值大小，其余按码点；忽略大小写与首尾空白。
///
/// 例如 `2` < `10`、`A2` < `A10`、`a2` == `A2`。
int compareNatural(String a, String b) {
  final left = a.trim().toLowerCase();
  final right = b.trim().toLowerCase();
  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    final leftIsDigit = _isAsciiDigit(left.codeUnitAt(i));
    final rightIsDigit = _isAsciiDigit(right.codeUnitAt(j));
    if (leftIsDigit && rightIsDigit) {
      var leftEnd = i;
      while (leftEnd < left.length && _isAsciiDigit(left.codeUnitAt(leftEnd))) {
        leftEnd++;
      }
      var rightEnd = j;
      while (rightEnd < right.length &&
          _isAsciiDigit(right.codeUnitAt(rightEnd))) {
        rightEnd++;
      }
      final numberLeft = _stripLeadingZeros(left.substring(i, leftEnd));
      final numberRight = _stripLeadingZeros(right.substring(j, rightEnd));
      if (numberLeft.length != numberRight.length) {
        return numberLeft.length < numberRight.length ? -1 : 1;
      }
      final numberCompare = numberLeft.compareTo(numberRight);
      if (numberCompare != 0) return numberCompare < 0 ? -1 : 1;
      i = leftEnd;
      j = rightEnd;
    } else {
      final charLeft = left.codeUnitAt(i);
      final charRight = right.codeUnitAt(j);
      if (charLeft != charRight) return charLeft < charRight ? -1 : 1;
      i++;
      j++;
    }
  }
  final remaining = (left.length - i) - (right.length - j);
  return remaining == 0 ? 0 : (remaining < 0 ? -1 : 1);
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

String _stripLeadingZeros(String value) {
  var start = 0;
  while (start < value.length - 1 && value.codeUnitAt(start) == 0x30) {
    start++;
  }
  return value.substring(start);
}
