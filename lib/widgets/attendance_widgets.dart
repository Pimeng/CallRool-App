import 'package:flutter/material.dart';

import '../models/attendance.dart';
import '../models/person.dart';

class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.person,
    required this.number,
    required this.selected,
    required this.selectionMode,
    required this.wide,
    required this.onToggleSelection,
    required this.onStatus,
  });
  final Person person;
  final int number;
  final bool selected;
  final bool selectionMode;
  final bool wide;
  final VoidCallback onToggleSelection;
  final ValueChanged<AttendanceStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE7F3EB) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: selectionMode ? onToggleSelection : null,
        onLongPress: onToggleSelection,
        child: Container(
          constraints: const BoxConstraints(minHeight: 69),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF78AC8C)
                  : const Color(0xFFE3E9E4),
            ),
          ),
          child: Row(
            children: [
              if (selectionMode)
                Checkbox(value: selected, onChanged: (_) => onToggleSelection())
              else
                CircleAvatar(
                  radius: 20,
                  backgroundColor: person.status.softColor,
                  foregroundColor: person.status.color,
                  child: Text(
                    person.name.characters.first,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '第 $number 号 · ${person.status.label}',
                      style: TextStyle(
                        fontSize: 11,
                        color: person.status.color,
                      ),
                    ),
                  ],
                ),
              ),
              if (!selectionMode)
                for (final status in [
                  AttendanceStatus.present,
                  AttendanceStatus.absent,
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: QuickStatusButton(
                      status:
                          status == AttendanceStatus.absent &&
                              isAbsenceStatus(person.status)
                          ? person.status
                          : status,
                      active: status == AttendanceStatus.absent
                          ? isAbsenceStatus(person.status)
                          : person.status == status,
                      showLabel: wide,
                      onTap: () => onStatus(status),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickStatusButton extends StatelessWidget {
  const QuickStatusButton({
    super.key,
    required this.status,
    required this.active,
    required this.showLabel,
    required this.onTap,
  });
  final AttendanceStatus status;
  final bool active;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: status.label,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: showLabel ? 76 : 40,
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 10 : 0),
        decoration: BoxDecoration(
          color: active ? status.softColor : const Color(0xFFF4F6F4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? status.color.withValues(alpha: .45)
                : const Color(0xFFE5E9E6),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status.icon,
              size: 19,
              color: active ? status.color : const Color(0xFF738078),
            ),
            if (showLabel) ...[
              const SizedBox(width: 5),
              Text(
                status.label,
                style: TextStyle(
                  color: active ? status.color : const Color(0xFF56625B),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2F1E8),
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: const Icon(
                      Icons.format_list_bulleted_add,
                      size: 33,
                      color: Color(0xFF176B45),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '名单还是空的',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '一行一个名字，简单直接。',
                    style: TextStyle(color: Color(0xFF718078)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('导入名单'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppMark extends StatelessWidget {
  const AppMark({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 35,
    height: 35,
    decoration: BoxDecoration(
      color: const Color(0xFF176B45),
      borderRadius: BorderRadius.circular(11),
    ),
    child: const Icon(Icons.how_to_reg_rounded, color: Colors.white, size: 21),
  );
}
