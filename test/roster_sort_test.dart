import 'package:callrool_app/models/person.dart';
import 'package:callrool_app/models/roster_sort.dart';
import 'package:flutter_test/flutter_test.dart';

Person _person(String name, {Map<String, String>? fields, int id = 1}) =>
    Person(id: id, name: name, fields: fields);

void main() {
  group('compareNatural', () {
    test('数字片段按数值大小比较', () {
      expect(compareNatural('2', '10'), lessThan(0));
      expect(compareNatural('10', '2'), greaterThan(0));
      expect(compareNatural('A2', 'A10'), lessThan(0));
      expect(compareNatural('宿舍 2 栋', '宿舍 10 栋'), lessThan(0));
    });

    test('前导零不影响相等判断', () {
      expect(compareNatural('007', '7'), 0);
      expect(compareNatural('A01', 'A1'), 0);
    });

    test('忽略大小写与首尾空白', () {
      expect(compareNatural('a2', 'A2'), 0);
      expect(compareNatural('  张三', '张三  '), 0);
    });

    test('纯文本按码点排序', () {
      expect(compareNatural('apple', 'banana'), lessThan(0));
      expect(compareNatural('banana', 'apple'), greaterThan(0));
    });
  });

  group('comparePeopleBySort', () {
    test('姓名按拼音升序', () {
      const sort = RosterSort(kind: RosterSortKind.name);
      final chen = _person('陈二');
      final liu = _person('刘一');
      expect(comparePeopleBySort(chen, liu, sort), lessThan(0));
    });

    test('自定义字段按自然顺序比较，缺失值排最后', () {
      const sort = RosterSort(kind: RosterSortKind.field, fieldName: '宿舍');
      final first = _person('甲', fields: {'宿舍': '101'});
      final second = _person('乙', fields: {'宿舍': '302'});
      final missing = _person('丙');
      expect(comparePeopleBySort(first, second, sort), lessThan(0));
      expect(comparePeopleBySort(missing, first, sort), greaterThan(0));
      expect(comparePeopleBySort(second, missing, sort), lessThan(0));
    });

    test('降序时缺失值仍然排最后', () {
      const sort = RosterSort(
        kind: RosterSortKind.field,
        fieldName: '宿舍',
        direction: RosterSortDirection.descending,
      );
      final first = _person('甲', fields: {'宿舍': '101'});
      final second = _person('乙', fields: {'宿舍': '302'});
      final missing = _person('丙');
      // 降序：302 在前。
      expect(comparePeopleBySort(second, first, sort), lessThan(0));
      // 但没填宿舍的依旧垫底。
      expect(comparePeopleBySort(missing, first, sort), greaterThan(0));
    });
  });

  group('RosterSort 编解码', () {
    test('往返保持一致', () {
      const sort = RosterSort(
        kind: RosterSortKind.field,
        fieldName: '宿舍',
        direction: RosterSortDirection.descending,
      );
      expect(RosterSort.decode(sort.toStorage()), sort);
    });

    test('非法或缺失值退回默认顺序', () {
      expect(RosterSort.decode(null), const RosterSort());
      expect(RosterSort.decode('not json'), const RosterSort());
      expect(
        RosterSort.decode('{"kind":"unknown","direction":"up"}'),
        const RosterSort(),
      );
    });
  });
}
