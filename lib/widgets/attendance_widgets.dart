import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../models/attendance.dart';
import '../models/person.dart';
import '../services/haptic_service.dart';

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasStatus = person.status != AttendanceStatus.unmarked;
    final rowColor = selected
        ? colorScheme.primaryContainer
        : hasStatus
        ? person.status.adaptiveSoftColor(context)
        : theme.cardTheme.color ?? colorScheme.surface;
    final borderColor = selected
        ? colorScheme.primary.withValues(alpha: .65)
        : hasStatus
        ? person.status.adaptiveColor(context).withValues(alpha: .55)
        : theme.dividerColor;

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
                      ? colorScheme.surface.withValues(alpha: .82)
                      : person.status.adaptiveSoftColor(context),
                  foregroundColor: person.status.adaptiveColor(context),
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
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: person.status.adaptiveSoftColor(context),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            person.status.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: person.status.adaptiveColor(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (person.fieldSummary.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        person.fieldSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!selectionMode)
                for (final status in [
                  AttendanceStatus.present,
                  AttendanceStatus.truancy,
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: status == AttendanceStatus.truancy
                        ? AttendanceExceptionStatusButton(
                            status: isAttendanceExceptionStatus(person.status)
                                ? person.status
                                : AttendanceStatus.truancy,
                            active: isAttendanceExceptionStatus(person.status),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = status.adaptiveColor(context);
    return Tooltip(
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
            color: active
                ? status.adaptiveSoftColor(context)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? statusColor.withValues(alpha: .45)
                  : theme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? status.icon,
                size: 19,
                color: active ? statusColor : colorScheme.onSurfaceVariant,
              ),
              if (showLabel) ...[
                const SizedBox(width: 5),
                Text(
                  label ?? status.label,
                  style: TextStyle(
                    color: active ? statusColor : colorScheme.onSurfaceVariant,
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
}

/// Displays non-standard attendance actions in a popup anchored to this button.
class AttendanceExceptionStatusButton extends StatelessWidget {
  const AttendanceExceptionStatusButton({
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
    AttendanceStatus.truancy,
    AttendanceStatus.late,
    AttendanceStatus.earlyLeave,
    AttendanceStatus.leave,
    AttendanceStatus.personalLeave,
    AttendanceStatus.sickLeave,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassMenu(
      menuWidth: 168,
      menuHeight: _options.length * 52 + 12,
      menuBorderRadius: 18,
      itemBorderRadius: 13,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      autoAdjustToScreen: true,
      quality: GlassQuality.standard,
      glowColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: .16),
      settings: LiquidGlassSettings(
        glassColor: scheme.surface.withValues(alpha: .14),
        thickness: 30,
        blur: 8,
        refractiveIndex: 1.24,
        lightIntensity: 1.1,
        ambientStrength: .18,
        fresnelStrength: 1.3,
        glowIntensity: .75,
        shadowElevation: 3,
      ),
      triggerBuilder: (buttonContext, toggleMenu) {
        if (compact) {
          return IconButton.filledTonal(
            tooltip: '选择异常考勤状态',
            onPressed: toggleMenu,
            icon: Icon(status.icon, color: status.adaptiveColor(context)),
          );
        }

        return Tooltip(
          message: '选择异常考勤状态',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: toggleMenu,
            child: QuickStatusButton(
              status: status,
              active: active,
              showLabel: showLabel,
              onTap: null,
            ),
          ),
        );
      },
      items: [
        for (final option in _options)
          GlassMenuItem(
            key: ValueKey('attendance-exception-option-${option.name}'),
            title: option.label,
            height: 48,
            icon: Icon(option.icon),
            iconColor: option.adaptiveColor(context),
            isSelected: option == status && active,
            titleStyle: TextStyle(
              fontWeight: option == status && active
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
            trailing: option == status && active
                ? Icon(
                    Icons.check_rounded,
                    size: 19,
                    color: option.adaptiveColor(context),
                  )
                : null,
            onTap: () {
              Haptic.light();
              onSelected(option);
            },
          ),
      ],
    );
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
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: Icon(
                      Icons.format_list_bulleted_add,
                      size: 33,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '名单还是空的',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '一行一个名字，简单直接。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Transform.translate(
        offset: const Offset(1, 1),
        child: Icon(
          Icons.how_to_reg_rounded,
          color: colorScheme.onPrimary,
          size: 21,
        ),
      ),
    );
  }
}
