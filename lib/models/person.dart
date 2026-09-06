import 'package:lpinyin/lpinyin.dart';

import 'attendance.dart';

class Person {
  Person({
    required this.id,
    required this.name,
    this.status = AttendanceStatus.unmarked,
  });
  final int id;
  final String name;
  AttendanceStatus status;
  late final String fullPinyin = PinyinHelper.getPinyinE(
    name,
    separator: '',
  ).toLowerCase();
  late final String pinyinInitials = PinyinHelper.getShortPinyin(name)
      .toLowerCase();

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'status': status.name,
  };
  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as int,
    name: json['name'] as String,
    status: AttendanceStatus.values.firstWhere(
      (status) => status.name == json['status'],
      orElse: () => AttendanceStatus.unmarked,
    ),
  );
}
