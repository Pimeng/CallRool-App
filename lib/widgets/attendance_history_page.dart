import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/attendance.dart';
import '../models/attendance_record.dart';
import '../models/attendance_record_filter.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String formatRecordTime(DateTime value) =>
    '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)} '
    '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';

/// 考勤记录列表。返回删除后的最新列表；没有改动时返回 null。
class AttendanceHistoryPage extends StatefulWidget {
  const AttendanceHistoryPage({super.key, required this.records});

  final List<AttendanceRecord> records;

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  late final List<AttendanceRecord> _records = List.of(widget.records);
  final _searchController = TextEditingController();
  AttendanceRecordFilter _filter = AttendanceRecordFilter.empty;
  bool _changed = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _close() =>
      Navigator.of(context).pop(_changed ? List.unmodifiable(_records) : null);

  List<AttendanceRecord> get _visibleRecords => _filter.apply(_records);

  List<String> get _courseOptions =>
      AttendanceRecordFilter.courseOptions(_records);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  /// 删掉记录后，已选课程可能已经不复存在，这里把失效的选择剔除，
  /// 避免筛选按钮显示一个列表里根本看不到的课程。
  void _pruneFilter() {
    if (!_filter.hasCourseFilter) return;
    final options = _courseOptions.toSet();
    final kept = _filter.courses.where(options.contains).toSet();
    if (kept.length != _filter.courses.length) {
      _filter = _filter.withCourses(kept);
    }
  }

  void _handleKeyword(String value) {
    setState(() => _filter = _filter.withKeyword(value));
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() => _filter = AttendanceRecordFilter.empty);
  }

  Future<void> _pickDateFilter() async {
    final preset = await showModalBottomSheet<RecordDatePreset>(
      context: context,
      showDragHandle: true,
      builder: (_) => _DateFilterSheet(current: _filter.preset),
    );
    if (preset == null || !mounted) return;
    if (preset != RecordDatePreset.custom) {
      setState(() => _filter = _filter.withDate(preset));
      return;
    }

    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: _filter.customRange,
      helpText: '选择日期范围',
      saveText: '确定',
    );
    if (range == null || !mounted) return;
    setState(
      () => _filter = _filter.withDate(RecordDatePreset.custom, custom: range),
    );
  }

  Future<void> _pickCourseFilter() async {
    final options = _courseOptions;
    if (options.isEmpty) {
      _toast('还没有可筛选的课程');
      return;
    }
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          _CourseFilterSheet(options: options, initial: _filter.courses),
    );
    if (selected == null || !mounted) return;
    setState(() => _filter = _filter.withCourses(selected));
  }

  Future<void> _delete(AttendanceRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条考勤记录？'),
        content: Text('${record.note}\n${formatRecordTime(record.savedAt)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _records.remove(record);
      _pruneFilter();
      _changed = true;
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空全部考勤记录？'),
        content: Text('共 ${_records.length} 条记录将被删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _records.clear();
      _filter = AttendanceRecordFilter.empty;
      _searchController.clear();
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: '返回',
            onPressed: _close,
          ),
          title: const Text('考勤记录'),
          actions: [
            if (_records.isNotEmpty)
              IconButton(
                tooltip: '清空全部',
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _records.isEmpty
              ? const _HistoryEmptyState()
              : Column(
                  children: [
                    _buildFilterBar(context),
                    Expanded(child: _buildRecordList(context)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: _handleKeyword,
            decoration: InputDecoration(
              hintText: '搜索备注、课程、教师、教室',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除关键词',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        _handleKeyword('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FilterButton(
                  key: const ValueKey('history-date-filter'),
                  icon: Icons.event_rounded,
                  label: '日期：${_filter.dateLabel}',
                  highlighted: _filter.hasDateFilter,
                  onTap: _pickDateFilter,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterButton(
                  key: const ValueKey('history-course-filter'),
                  icon: Icons.menu_book_rounded,
                  label: '课程：${_filter.courseLabel}',
                  highlighted: _filter.hasCourseFilter,
                  onTap: _pickCourseFilter,
                ),
              ),
              if (_filter.isActive)
                IconButton(
                  tooltip: '清除筛选',
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded),
                ),
            ],
          ),
          if (_filter.isActive)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                '筛选后 ${_visibleRecords.length} / ${_records.length} 条',
                key: const ValueKey('history-filter-count'),
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordList(BuildContext context) {
    final visible = _visibleRecords;
    if (visible.isEmpty) {
      return _NoMatchState(onClear: _clearFilters);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final record = visible[index];
        final subtitle = record.courseSummary;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: _DateBadge(savedAt: record.savedAt),
            title: Text(
              record.note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatRecordTime(record.savedAt)} · '
                  '应到 ${record.total} 实到 ${record.presentCount}',
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            isThreeLine: subtitle != null,
            trailing: IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(record),
            ),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => AttendanceRecordDetailPage(record: record),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 筛选栏上的一个下拉式筛选按钮，命中条件时高亮。
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return highlighted
        ? FilledButton(onPressed: onTap, child: child)
        : OutlinedButton(onPressed: onTap, child: child);
  }
}

/// 日期筛选面板：把预设区间和「自定义范围」列出来。
class _DateFilterSheet extends StatelessWidget {
  const _DateFilterSheet({required this.current});

  final RecordDatePreset current;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    // 底部弹出面板的高度受路由限制，用可滚动容器兜底，选项多时不会溢出。
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '按日期筛选',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          for (final preset in RecordDatePreset.values)
            ListTile(
              title: Text(preset.label),
              trailing: preset == current
                  ? Icon(
                      Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(context, preset),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// 课程筛选面板：多选，支持全选 / 清空。
class _CourseFilterSheet extends StatefulWidget {
  const _CourseFilterSheet({required this.options, required this.initial});

  final List<String> options;
  final Set<String> initial;

  @override
  State<_CourseFilterSheet> createState() => _CourseFilterSheetState();
}

class _CourseFilterSheetState extends State<_CourseFilterSheet> {
  late final Set<String> _selected = {...widget.initial};

  bool get _allSelected =>
      widget.options.isNotEmpty && _selected.length == widget.options.length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '按课程筛选',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (_allSelected) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(widget.options);
                      }
                    }),
                    child: Text(_allSelected ? '清空' : '全选'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                _selected.isEmpty
                    ? '未选择课程时显示全部记录'
                    : '已选 ${_selected.length} / ${widget.options.length} 个课程，命中任意一个即可',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final option in widget.options)
                    CheckboxListTile(
                      value: _selected.contains(option),
                      title: Text(option),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(option);
                        } else {
                          _selected.remove(option);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 筛选后没有匹配记录时的提示。
class _NoMatchState extends StatelessWidget {
  const _NoMatchState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_rounded,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text(
              '没有符合筛选条件的记录',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '试试更换课程或日期范围。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('清除筛选'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.savedAt});

  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${savedAt.month}/${savedAt.day}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    '${_twoDigits(savedAt.hour)}:${_twoDigits(savedAt.minute)}',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      color: scheme.onPrimaryContainer.withValues(alpha: .8),
                    ),
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

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text(
              '还没有考勤记录',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '在考勤页点击右下角按钮，选择「保存当前考勤记录」，之后就能在这里回看。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条考勤记录的详情：逐状态名单与扩展字段。
class AttendanceRecordDetailPage extends StatelessWidget {
  const AttendanceRecordDetailPage({super.key, required this.record});

  final AttendanceRecord record;

  String _buildCopyText() {
    final buffer = StringBuffer()
      ..writeln('${formatRecordTime(record.savedAt)} 考勤记录：${record.note}');
    final course = record.courseSummary;
    if (course != null) buffer.writeln('课程信息：$course');
    buffer.writeln('应到 ${record.total} 人，实到 ${record.presentCount} 人');
    for (final status in AttendanceStatus.values) {
      if (status == AttendanceStatus.unmarked) continue;
      final names = record.entries
          .where((entry) => entry.status == status)
          .map((entry) => entry.name)
          .toList();
      if (names.isEmpty) continue;
      buffer.writeln('${status.label}（${names.length}）：${names.join('、')}');
    }
    if (record.unmarkedCount > 0) {
      final names = record.entries
          .where((entry) => entry.status == AttendanceStatus.unmarked)
          .map((entry) => entry.name)
          .toList();
      buffer.writeln('未点名（${names.length}）：${names.join('、')}');
    }
    return buffer.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final withFields = record.entries.where(
      (entry) => entry.fields.values.any((value) => value.trim().isNotEmpty),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(record.note, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '复制考勤情况',
            icon: const Icon(Icons.content_copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _buildCopyText()));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('考勤情况已复制到剪贴板'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatRecordTime(record.savedAt),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (record.courseSummary != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        record.courseSummary!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatChip(label: '应到', value: record.total),
                        _StatChip(
                          label: '实到',
                          value: record.presentCount,
                          color: AttendanceStatus.present.adaptiveColor(context),
                        ),
                        _StatChip(
                          label: '请假',
                          value: record.leaveCount,
                          color: AttendanceStatus.leave.adaptiveColor(context),
                        ),
                        _StatChip(
                          label: '异常',
                          value: record.issueCount,
                          color: AttendanceStatus.truancy
                              .adaptiveColor(context),
                        ),
                        _StatChip(
                          label: '未点名',
                          value: record.unmarkedCount,
                          color: AttendanceStatus.unmarked
                              .adaptiveColor(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            for (final status in AttendanceStatus.values)
              if (record.countWhere((value) => value == status) > 0)
                _StatusSection(record: record, status: status),
            if (withFields.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '扩展字段',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final entry in withFields)
                      ListTile(
                        dense: true,
                        title: Text(entry.name),
                        subtitle: Text(
                          [
                            for (final field in entry.fields.entries)
                              if (field.value.trim().isNotEmpty)
                                '${field.key} ${field.value.trim()}',
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.record, required this.status});

  final AttendanceRecord record;
  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final names = record.entries
        .where((entry) => entry.status == status)
        .map((entry) => entry.name)
        .toList();
    final color = status.adaptiveColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(status.icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(
                    '${status.label}（${names.length}）',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(names.join('、')),
            ],
          ),
        ),
      ),
    );
  }
}
