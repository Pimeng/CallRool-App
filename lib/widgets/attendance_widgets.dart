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
    final hasStatus = person.status != AttendanceStatus.unmarked;
    final rowColor = selected
        ? const Color(0xFFE7F3EB)
        : hasStatus
        ? person.status.softColor
        : Colors.white;
    final borderColor = selected
        ? const Color(0xFF78AC8C)
        : hasStatus
        ? person.status.color.withValues(alpha: .55)
        : const Color(0xFFE3E9E4);

    return Material(
      color: rowColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: selectionMode ? onToggleSelection : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 69),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              if (selectionMode)
                Checkbox(value: selected, onChanged: (_) => onToggleSelection())
              else
                CircleAvatar(
                  radius: 20,
                  backgroundColor: hasStatus
                      ? Colors.white.withValues(alpha: .82)
                      : person.status.softColor,
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
                    Row(
                      children: [
                        Text(
                          '第 $number 号',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF66736B),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: person.status.softColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            person.status.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: person.status.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
                    child: status == AttendanceStatus.absent
                        ? AbsenceStatusButton(
                            status: isAbsenceStatus(person.status)
                                ? person.status
                                : AttendanceStatus.absent,
                            active: isAbsenceStatus(person.status),
                            showLabel: wide,
                            onSelected: onStatus,
                          )
                        : QuickStatusButton(
                            status: status,
                            active:
                                status != AttendanceStatus.unmarked &&
                                person.status == status,
                            showLabel: wide,
                            label: status == AttendanceStatus.unmarked
                                ? '重置'
                                : null,
                            icon: status == AttendanceStatus.unmarked
                                ? Icons.restart_alt_rounded
                                : null,
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
    this.label,
    this.icon,
  });
  final AttendanceStatus status;
  final bool active;
  final bool showLabel;
  final VoidCallback? onTap;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label ?? status.label,
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
              icon ?? status.icon,
              size: 19,
              color: active ? status.color : const Color(0xFF738078),
            ),
            if (showLabel) ...[
              const SizedBox(width: 5),
              Text(
                label ?? status.label,
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

/// Displays absence-related actions in a popup anchored to this button.
class AbsenceStatusButton extends StatelessWidget {
  const AbsenceStatusButton({
    super.key,
    required this.status,
    required this.active,
    required this.showLabel,
    required this.onSelected,
    this.compact = false,
  });

  final AttendanceStatus status;
  final bool active;
  final bool showLabel;
  final ValueChanged<AttendanceStatus> onSelected;
  final bool compact;

  static const _options = [
    AttendanceStatus.absent,
    AttendanceStatus.leave,
    AttendanceStatus.personalLeave,
    AttendanceStatus.sickLeave,
  ];

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        if (compact) {
          return IconButton.filledTonal(
            tooltip: '选择缺勤类型',
            onPressed: () => _showMenu(buttonContext),
            icon: Icon(status.icon, color: status.color),
          );
        }

        return Tooltip(
          message: '选择缺勤类型',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showMenu(buttonContext),
            child: QuickStatusButton(
              status: status,
              active: active,
              showLabel: showLabel,
              onTap: null,
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMenu(BuildContext buttonContext) async {
    final overlay = Overlay.of(buttonContext);
    final overlayBox = overlay.context.findRenderObject();
    final buttonBox = buttonContext.findRenderObject();
    if (overlayBox is! RenderBox || buttonBox is! RenderBox) return;

    final buttonTopLeftInOverlay = overlayBox.globalToLocal(
      buttonBox.localToGlobal(Offset.zero),
    );
    final buttonRect = buttonTopLeftInOverlay & buttonBox.size;

    const menuWidth = 168.0;
    const menuHeight = 4 * 48.0 + 8.0;
    const gap = 6.0;
    const screenPadding = 8.0;
    final screenSize = overlayBox.size;
    final canOpenBelow =
        buttonRect.bottom + gap + menuHeight <=
        screenSize.height - screenPadding;
    final canOpenAbove = buttonRect.top - gap - menuHeight >= screenPadding;
    final openAbove =
        !canOpenBelow &&
        (canOpenAbove ||
            buttonRect.top > screenSize.height - buttonRect.bottom);
    final menuTop =
        (openAbove
                ? buttonRect.top - gap - menuHeight
                : buttonRect.bottom + gap)
            .clamp(
              screenPadding,
              screenSize.height - menuHeight - screenPadding,
            )
            .toDouble();
    final menuLeft = (buttonRect.right - menuWidth)
        .clamp(screenPadding, screenSize.width - menuWidth - screenPadding)
        .toDouble();

    final selected = await showGeneralDialog<AttendanceStatus>(
      context: buttonContext,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: '关闭缺勤类型选择',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SizedBox(
          width: menuWidth,
          height: menuHeight,
          child: Material(
            key: const ValueKey('absence-status-menu'),
            elevation: 0,
            color: Colors.white,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFDDE4DF)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in _options)
                    SizedBox(
                      height: 48,
                      child: Ink(
                        color: option == status && active
                            ? option.softColor
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                Icon(
                                  option.icon,
                                  size: 20,
                                  color: option.color,
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: TextStyle(
                                      fontWeight: option == status && active
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (option == status && active)
                                  Icon(
                                    Icons.check_rounded,
                                    size: 19,
                                    color: option.color,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Stack(
          children: [
            Positioned(
              left: menuLeft,
              top: menuTop,
              width: menuWidth,
              child: FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: animation.drive(
                    Tween<double>(
                      begin: .96,
                      end: 1,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  alignment: openAbove
                      ? Alignment.bottomRight
                      : Alignment.topRight,
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (selected != null) onSelected(selected);
  }
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
