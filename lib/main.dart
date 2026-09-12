import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/attendance.dart';
import 'models/attendance_copy_template.dart';
import 'models/attendance_record.dart';
import 'models/course_schedule.dart';
import 'models/person.dart';
import 'services/attendance_history_store.dart';
import 'services/haptic_service.dart';
import 'services/quick_import/backend_binding.dart';
import 'services/storage_keys.dart';
import 'theme/app_theme.dart';
import 'widgets/attendance_history_page.dart';
import 'widgets/attendance_widgets.dart';
import 'widgets/backup_restore_page.dart';
import 'widgets/copy_format_dialog.dart';
import 'widgets/random_picker_page.dart';
import 'widgets/roster_editor_page.dart';
import 'widgets/wakeup_schedule_dialog.dart';

const _performanceDiagnostics = bool.fromEnvironment(
  'ROLLCALL_PERF',
  defaultValue: false,
);

class RollCallApp extends StatelessWidget {
  const RollCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: kDebugMode && _performanceDiagnostics,
      title: '快捷考勤喵',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const RollCallPage(),
    );
  }
}

class _VisiblePerson {
  const _VisiblePerson({required this.person, required this.number});
  final Person person;
  final int number;
}

class _AddPersonDialog extends StatefulWidget {
  const _AddPersonDialog();

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  final _controller = TextEditingController();
  AttendanceStatus _selectedStatus = AttendanceStatus.unmarked;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name, _selectedStatus));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加人员'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: '姓名'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<AttendanceStatus>(
            initialValue: _selectedStatus,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '当前考勤状态'),
            items: [
              for (final status in AttendanceStatus.values)
                DropdownMenuItem(
                  value: status,
                  child: Row(
                    children: [
                      Icon(status.icon, size: 19, color: status.color),
                      const SizedBox(width: 10),
                      Text(status.label),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedStatus = value);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty ? null : _submit,
        child: const Text('添加'),
      ),
    ],
  );
}

/// 保存考勤记录前的确认弹窗：填写备注，并提示还有多少人未点名。
class _SaveRecordDialog extends StatefulWidget {
  const _SaveRecordDialog({
    required this.suggestedNote,
    required this.courseSummary,
    required this.unmarkedCount,
  });

  final String suggestedNote;
  final String? courseSummary;
  final int unmarkedCount;

  @override
  State<_SaveRecordDialog> createState() => _SaveRecordDialogState();
}

class _SaveRecordDialogState extends State<_SaveRecordDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.suggestedNote,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('保存当前考勤记录'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '备注',
                helperText: '留空则使用课程名或当前时间',
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            if (widget.courseSummary != null) ...[
              const SizedBox(height: 12),
              Text(
                '课程信息：${widget.courseSummary}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (widget.unmarkedCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                '还有 ${widget.unmarkedCount} 人未点名，记录中会保留为“未点名”。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

typedef _ImportRosterResult = ({List<String> names, bool replace});

class _ImportRosterPage extends StatefulWidget {
  const _ImportRosterPage({
    required this.existingCount,
    required this.isFirstImport,
  });

  final int existingCount;
  final bool isFirstImport;

  @override
  State<_ImportRosterPage> createState() => _ImportRosterPageState();
}

class _ImportRosterPageState extends State<_ImportRosterPage> {
  final _controller = TextEditingController();
  List<String> _names = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _parseNames(String text) {
    final seen = <String>{};
    return const LineSplitter()
        .convert(text.replaceAll('\r', ''))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && seen.add(name.toLowerCase()))
        .toList();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择名单文件',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (picked == null || !mounted) return;
    final value = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
    if (!mounted) return;
    _controller.text = value;
    setState(() => _names = _parseNames(value));
  }

  void _finish({required bool replace}) {
    Navigator.pop(context, (
      names: List<String>.unmodifiable(_names),
      replace: replace,
    ));
  }

  Future<void> _replace() async {
    if (widget.isFirstImport) {
      _finish(replace: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认替换现有名单？'),
        content: Text(
          '现有 ${widget.existingCount} 人及其考勤状态将被删除，并替换为 ${_names.length} 人。此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _finish(replace: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('导入名单'),
      actions: [
        IconButton(
          tooltip: '选择 TXT 文件',
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file_rounded),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('一行一个名字，自动忽略空行和重复姓名。')),
                    const SizedBox(width: 12),
                    Text(
                      '${_names.length} 人',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText: '张三\n李四\n王五',
                      alignLabelWithHint: true,
                    ),
                    onChanged: (value) =>
                        setState(() => _names = _parseNames(value)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: widget.isFirstImport
                    ? OutlinedButton(
                        onPressed: _names.isEmpty
                            ? null
                            : () => _finish(replace: false),
                        child: const Text('追加'),
                      )
                    : OutlinedButton(
                        onPressed: _names.isEmpty ? null : _replace,
                        child: const Text('替换现有'),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: widget.isFirstImport
                    ? FilledButton(
                        onPressed: _names.isEmpty ? null : _replace,
                        child: const Text('替换现有'),
                      )
                    : FilledButton(
                        onPressed: _names.isEmpty
                            ? null
                            : () => _finish(replace: false),
                        child: const Text('追加'),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 工具箱 Tab：集中放置与考勤相关的小工具。
class _ToolboxTab extends StatelessWidget {
  const _ToolboxTab({
    required this.onRandomPick,
    required this.onOpenHistory,
    required this.historyCount,
  });

  final VoidCallback onRandomPick;
  final VoidCallback onOpenHistory;
  final int historyCount;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
      children: [
        const _SectionLabel('抽签'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.casino_rounded),
            title: const Text('随机点人'),
            subtitle: const Text('从正常到勤人员中抽签，支持批量与不重复'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onRandomPick,
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('记录'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('考勤记录'),
            subtitle: Text(
              historyCount == 0 ? '还没有保存的记录' : '已保存 $historyCount 条记录',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenHistory,
          ),
        ),
      ],
    ),
  );
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.hasPeople,
    required this.scheduleName,
    required this.lastModifiedLabel,
    required this.hapticEnabled,
    required this.onHapticChanged,
    required this.onEditRoster,
    required this.onImportRoster,
    required this.onExportRoster,
    required this.onCustomizeCopyFormat,
    required this.onSyncSchedule,
    required this.onBackupRestore,
  });

  final bool hasPeople;
  final String? scheduleName;
  final String lastModifiedLabel;
  final bool hapticEnabled;
  final ValueChanged<bool> onHapticChanged;
  final VoidCallback onEditRoster;
  final VoidCallback onImportRoster;
  final VoidCallback onExportRoster;
  final VoidCallback onCustomizeCopyFormat;
  final VoidCallback onSyncSchedule;
  final VoidCallback onBackupRestore;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
      children: [
        const _SectionLabel('名单'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('编辑名单'),
                subtitle: const Text('修改姓名、自定义扩展字段（宿舍、学号等）'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onEditRoster,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.upload_file_rounded),
                title: const Text('导入名单'),
                subtitle: const Text('从文本或 TXT 文件追加、替换名单'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onImportRoster,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                enabled: hasPeople,
                leading: const Icon(Icons.download_rounded),
                title: const Text('导出名单'),
                subtitle: const Text('将当前名单保存为 TXT 文件'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: hasPeople ? onExportRoster : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('复制'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('自定义复制格式'),
            subtitle: const Text('编辑考勤汇总的内容和变量'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onCustomizeCopyFormat,
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('课程表'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.calendar_month_rounded),
            title: const Text('同步 WakeUp 课程表'),
            subtitle: Text(scheduleName ?? '尚未配置'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onSyncSchedule,
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('数据'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: const Text('备份与还原'),
            subtitle: const Text('导出或恢复名单、考勤记录、扩展字段与课程信息'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onBackupRestore,
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('通用'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: const Text('震动反馈'),
            subtitle: const Text('点按按钮、切换考勤状态时给出轻微震动'),
            value: hapticEnabled,
            onChanged: onHapticChanged,
          ),
        ),
        const SizedBox(height: 26),
        // 首页不再显示标题栏，名单的修改时间挪到这里做个脚注。
        Center(
          child: Text(
            '上次修改：$lastModifiedLabel',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 设置/工具箱里的分组小标题。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// 右下角悬浮按钮菜单里的一项操作。
class _FabMenuAction extends StatelessWidget {
  const _FabMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final foreground = enabled
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant.withValues(alpha: .45);
    return Material(
      color: enabled
          ? scheme.secondaryContainer
          : scheme.surfaceContainerHighest.withValues(alpha: .7),
      elevation: enabled ? 3 : 0,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 固定在顶部的筛选条（考勤页 NestedScrollView 的 header sliver）。
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedHeaderDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
}

/// 悬浮菜单里的一项：随菜单开合做「弹出 / 收回」动画。
///
/// `order` 表示距离悬浮按钮的远近，0 是最靠按钮、最先弹出的一项，
/// 这样展开时从下往上依次弹出，收起时又依次缩回按钮方向。
class _FabMenuEntry extends StatelessWidget {
  const _FabMenuEntry({
    required this.animation,
    required this.order,
    required this.count,
    required this.child,
  });

  final Animation<double> animation;
  final int order;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 每项错开 55% 的时间出发，剩下 45% 用来收尾，避免弹成一坨。
    final start = count <= 1 ? 0.0 : order / count * .55;
    final progress = animation.drive(
      CurveTween(curve: Interval(start, 1, curve: Curves.easeOutCubic)),
    );
    return SizeTransition(
      sizeFactor: progress,
      // SizeTransition 内部是 Align(heightFactor: ...)，宽度默认会撑满可用空间，
      // 只靠 alignment 定位就会把菜单项顶到屏幕左边。fixedCrossAxisSizeFactor: 1
      // 让宽度仍然按内容收缩，项才会老老实实贴着右下角的按钮。
      fixedCrossAxisSizeFactor: 1,
      // 高度向着悬浮按钮的方向展开/收缩，避免按钮跳位。
      alignment: AlignmentDirectional.bottomEnd,
      child: FadeTransition(
        opacity: progress,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .35),
            end: Offset.zero,
          ).animate(progress),
          child: ScaleTransition(
            scale: Tween<double>(begin: .8, end: 1).animate(progress),
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 筛选条上的数量角标，用来替代原先顶部的四块统计卡片。
class _FilterCount extends StatelessWidget {
  const _FilterCount(this.count, {required this.highlighted});

  final int count;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primary.withValues(alpha: .18)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: highlighted ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LongPressReorderableDragStartListener
    extends ReorderableDragStartListener {
  const _LongPressReorderableDragStartListener({
    super.key,
    required super.child,
    required super.index,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return _HapticDelayedMultiDragGestureRecognizer(
      delay: const Duration(milliseconds: 800),
      debugOwner: this,
    );
  }
}

class _HapticDelayedMultiDragGestureRecognizer
    extends DelayedMultiDragGestureRecognizer {
  _HapticDelayedMultiDragGestureRecognizer({
    required super.delay,
    super.debugOwner,
  });

  @override
  void acceptGesture(int pointer) {
    super.acceptGesture(pointer);
    Haptic.selection();
  }
}

/// 主页的三个 Tab。
enum _HomeTab { attendance, toolbox, settings }

class RollCallPage extends StatefulWidget {
  const RollCallPage({super.key});

  @override
  State<RollCallPage> createState() => _RollCallPageState();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode && _performanceDiagnostics) {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        if (timing.totalSpan >= const Duration(milliseconds: 50)) {
          debugPrint(
            '[rollcall][frame] '
            'total=${timing.totalSpan.inMilliseconds}ms '
            'build=${timing.buildDuration.inMilliseconds}ms '
            'raster=${timing.rasterDuration.inMilliseconds}ms',
          );
        }
      }
    });
  }
  runApp(const RollCallApp());
}

class _RollCallPageState extends State<RollCallPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _storageKey = StorageKeys.people;
  static const _hasImportedRosterKey = StorageKeys.hasImportedRoster;
  static const _lastModifiedStorageKey = StorageKeys.lastModified;
  static const _wakeUpAuthTokenKey = StorageKeys.wakeUpAuthToken;
  static const _wakeUpScheduleDataKey = StorageKeys.wakeUpScheduleData;
  static const _wakeUpScheduleSyncedAtKey = StorageKeys.wakeUpScheduleSyncedAt;
  static const _attendanceCopyTemplateKey = StorageKeys.attendanceCopyTemplate;
  static const _personFieldsKey = StorageKeys.personFields;
  static const _defaultNames = [
    '刘一',
    '陈二',
    '张三',
    '李四',
    '王五',
    '赵六',
    '孙七',
    '周八',
    '吴九',
    '郑十',
  ];
  final _searchController = TextEditingController();
  final _rosterScrollController = ScrollController();
  final _quickImportBackend = createQuickImportBackend();

  /// 驱动右下角菜单的展开/收起，同一根动画同时控制每项的错落节奏。
  late final AnimationController _fabController;
  final List<Person> _people = [];
  final Set<int> _selected = {};
  RosterFilter _filter = RosterFilter.all;
  List<_VisiblePerson>? _visiblePeopleCache;
  String _visiblePeopleCacheKeyword = '';
  RosterFilter _visiblePeopleCacheFilter = RosterFilter.all;
  Map<AttendanceStatus, int>? _statusCountsCache;
  _HomeTab _tab = _HomeTab.attendance;
  bool _loading = true;
  bool _hasImportedRoster = false;
  bool _selectionMode = false;
  bool _fabOpen = false;
  bool _navigationBarVisible = true;
  bool _hapticEnabled = true;
  int _nextId = 1;

  /// 内层名单列表的滚动位置（NestedScrollView 注入）。
  /// 「回到顶部」要同时归零内外两层位置。
  ScrollPosition? _innerScrollPosition;
  DateTime? _lastModifiedAt;
  WakeUpSchedule? _wakeUpSchedule;
  DateTime? _wakeUpScheduleSyncedAt;
  String? _attendanceCopyTemplate;

  /// 自定义扩展字段的字段名（如宿舍、学号），在「编辑名单」中增删。
  List<String> _personFields = List.of(kDefaultPersonFields);

  /// 已保存的考勤历史记录，最新的在最前面。
  final List<AttendanceRecord> _attendanceHistory = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    )..addStatusListener(_handleFabStatus);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fabController.dispose();
    _rosterScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 收起动画跑完后把菜单项真正从树上摘掉。
  void _handleFabStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  void _toggleActionMenu() {
    Haptic.light();
    setState(() {
      _fabOpen = !_fabOpen;
      if (_fabOpen) {
        _fabController.forward();
      } else {
        _fabController.reverse();
      }
    });
  }

  /// 选中菜单项后立即收起：马上会有弹窗或新页面盖上来，不必再走收起动画。
  void _dismissActionMenu() {
    _fabOpen = false;
    _fabController.value = 0;
    setState(() {});
  }

  void _selectTab(int index) {
    Haptic.selection();
    final next = _HomeTab.values[index];
    final reselected = next == _tab;
    // 离开考勤页时悬浮菜单会被移除，状态要一并复位，避免下次进来残着展开。
    _fabOpen = false;
    _fabController.value = 0;
    setState(() {
      _tab = next;
      _navigationBarVisible = true;
    });
    // 已经在考勤页时再点一次「考勤」，回到名单顶部（搜索框也顺带露出来）。
    if (reselected && next == _HomeTab.attendance) _scrollToTop();
  }

  void _scrollToTop() {
    if (!mounted) return;
    const duration = Duration(milliseconds: 360);
    const curve = Curves.easeOutCubic;
    // 头部（搜索框）在外层位置，名单在内层位置，两个都要回到 0。
    final innerPosition = _innerScrollPosition;
    if (innerPosition != null && innerPosition.hasContentDimensions) {
      innerPosition.animateTo(0, duration: duration, curve: curve);
    }
    if (_rosterScrollController.hasClients) {
      _rosterScrollController.animateTo(0, duration: duration, curve: curve);
    }
  }

  /// 记住内层名单列表的滚动位置，供「回到顶部」使用。
  bool _handleInnerScroll(ScrollNotification notification) {
    final context = notification.context;
    if (context != null && notification.metrics.axis == Axis.vertical) {
      _innerScrollPosition = Scrollable.maybeOf(context)?.position;
    }
    return false;
  }

  /// 考勤名单向下浏览时让底部导航暂时退场，反向滚动时立即恢复。
  bool _handleAttendanceScrollDirection(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical ||
        notification.direction == ScrollDirection.idle) {
      return false;
    }
    final visible = notification.direction == ScrollDirection.forward;
    if (visible != _navigationBarVisible) {
      setState(() => _navigationBarVisible = visible);
    }
    return false;
  }

  @override
  void didChangeMetrics() {
    if (!kDebugMode || !_performanceDiagnostics) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final logicalSize = view.physicalSize / view.devicePixelRatio;
    debugPrint(
      '[rollcall][window] '
      'size=${logicalSize.width.toStringAsFixed(0)}x'
      '${logicalSize.height.toStringAsFixed(0)} '
      'dpr=${view.devicePixelRatio.toStringAsFixed(2)}',
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _people.clear();
    _selected.clear();
    _selectionMode = false;
    _lastModifiedAt = DateTime.tryParse(
      prefs.getString(_lastModifiedStorageKey) ?? '',
    );
    _hapticEnabled = prefs.getBool(StorageKeys.hapticEnabled) ?? true;
    Haptic.setEnabled(_hapticEnabled);
    // 先清空再按存储重建，这样「备份还原」后重载不会残留旧数据。
    _wakeUpSchedule = null;
    _wakeUpScheduleSyncedAt = null;
    final cachedSchedule = prefs.getString(_wakeUpScheduleDataKey);
    _attendanceCopyTemplate = prefs.getString(_attendanceCopyTemplateKey);
    final rawFields = prefs.getString(_personFieldsKey);
    _personFields = rawFields == null
        ? List.of(kDefaultPersonFields)
        : _decodePersonFields(rawFields);
    _attendanceHistory
      ..clear()
      ..addAll(AttendanceHistoryStore.load(prefs));
    if (cachedSchedule != null && cachedSchedule.isNotEmpty) {
      try {
        _wakeUpSchedule = WakeUpSchedule.parse(cachedSchedule);
        _wakeUpScheduleSyncedAt = DateTime.tryParse(
          prefs.getString(_wakeUpScheduleSyncedAtKey) ?? '',
        );
      } on FormatException {
        _wakeUpSchedule = null;
        _wakeUpScheduleSyncedAt = null;
      }
    }
    if (raw == null) {
      _people.addAll(
        _defaultNames.asMap().entries.map(
          (entry) => Person(id: entry.key + 1, name: entry.value),
        ),
      );
      _nextId = _people.length + 1;
      await _save();
    } else {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _people.addAll(
          list.map((item) => Person.fromJson(item as Map<String, dynamic>)),
        );
        if (_people.isNotEmpty) {
          _nextId =
              _people
                  .map((person) => person.id)
                  .reduce((a, b) => a > b ? a : b) +
              1;
        }
      } catch (_) {}
    }
    _hasImportedRoster =
        prefs.getBool(_hasImportedRosterKey) ?? !_isUsingDefaultRoster;
    await prefs.setBool(_hasImportedRosterKey, _hasImportedRoster);
    _invalidatePeopleCache();
    if (mounted) setState(() => _loading = false);
  }

  bool get _isUsingDefaultRoster =>
      _people.length == _defaultNames.length &&
      List.generate(
        _people.length,
        (index) => _people[index].name == _defaultNames[index],
      ).every((matches) => matches);

  Future<void> _save() async {
    _lastModifiedAt = DateTime.now();
    if (mounted) setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(
        _storageKey,
        jsonEncode(_people.map((person) => person.toJson()).toList()),
      ),
      prefs.setString(
        _lastModifiedStorageKey,
        _lastModifiedAt!.toIso8601String(),
      ),
    ]);
  }

  List<String> _decodePersonFields(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return normalizePersonFields(decoded.map((item) => item.toString()));
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _savePersonFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_personFieldsKey, jsonEncode(_personFields));
  }

  Future<void> _saveAttendanceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await AttendanceHistoryStore.save(prefs, _attendanceHistory);
  }

  /// 设置页「震动反馈」开关：立即生效并落盘。
  Future<void> _setHapticEnabled(bool value) async {
    setState(() => _hapticEnabled = value);
    Haptic.setEnabled(value);
    // 开启时先给一次反馈，让用户马上感知到手感。
    if (value) Haptic.light();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.hapticEnabled, value);
  }

  /// 从本地存储重新加载全部数据（备份还原后调用）。
  Future<void> _reloadFromStorage() async {
    if (mounted) setState(() => _loading = true);
    await _load();
  }

  int _count(AttendanceStatus status) {
    final cached = _statusCountsCache;
    if (cached != null) return cached[status] ?? 0;

    final counts = <AttendanceStatus, int>{
      for (final value in AttendanceStatus.values) value: 0,
    };
    for (final person in _people) {
      counts[person.status] = counts[person.status]! + 1;
    }
    _statusCountsCache = counts;
    return counts[status] ?? 0;
  }

  int _countAttendanceIssues() =>
      _people.where((person) => isAttendanceIssueStatus(person.status)).length;

  int _countLeaveTypes() =>
      _people.where((person) => isLeaveStatus(person.status)).length;

  List<_VisiblePerson> get _visiblePeople {
    final keyword = _searchController.text.trim().toLowerCase().replaceAll(
      ' ',
      '',
    );
    final cached = _visiblePeopleCache;
    if (cached != null &&
        keyword == _visiblePeopleCacheKeyword &&
        _filter == _visiblePeopleCacheFilter) {
      return cached;
    }

    final visible = <_VisiblePerson>[];
    for (var index = 0; index < _people.length; index++) {
      final person = _people[index];
      final searched = keyword.isEmpty || person.searchText.contains(keyword);
      final filtered = switch (_filter) {
        RosterFilter.all => true,
        RosterFilter.unmarked => person.status == AttendanceStatus.unmarked,
        RosterFilter.present => person.status == AttendanceStatus.present,
        RosterFilter.issue => isAttendanceIssueStatus(person.status),
        RosterFilter.leave => isLeaveStatus(person.status),
      };
      if (searched && filtered) {
        visible.add(_VisiblePerson(person: person, number: index + 1));
      }
    }
    _visiblePeopleCacheKeyword = keyword;
    _visiblePeopleCacheFilter = _filter;
    _visiblePeopleCache = visible;
    return visible;
  }

  void _invalidatePeopleCache() {
    _visiblePeopleCache = null;
    _statusCountsCache = null;
  }

  String get _filterLabel => switch (_filter) {
    RosterFilter.all => '全部',
    RosterFilter.unmarked => '未点名',
    RosterFilter.present => '正常',
    RosterFilter.issue => '异常',
    RosterFilter.leave => '请假',
  };

  void _retainVisibleSelection({bool notifyWhenRemoved = false}) {
    if (_selected.isEmpty) return;
    final visibleIds = _visiblePeople.map((item) => item.person.id).toSet();
    final previousCount = _selected.length;
    _selected.retainWhere(visibleIds.contains);
    final removedCount = previousCount - _selected.length;
    if (notifyWhenRemoved && removedCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _toast('已取消 $removedCount 名筛选外人员的选择');
      });
    }
  }

  void _handleSearchChanged(String _) {
    _invalidatePeopleCache();
    setState(() => _retainVisibleSelection(notifyWhenRemoved: true));
  }

  void _setFilter(RosterFilter filter) {
    Haptic.selection();
    _invalidatePeopleCache();
    setState(() {
      _filter = filter;
      _retainVisibleSelection(notifyWhenRemoved: true);
    });
  }

  String get _lastModifiedLabel {
    final value = _lastModifiedAt;
    if (value == null) return '暂无修改记录';
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    final now = DateTime.now();
    final time = '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return '今天 $time';
    }
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} $time';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  bool _matchesFilter(AttendanceStatus status) => switch (_filter) {
    RosterFilter.all => true,
    RosterFilter.unmarked => status == AttendanceStatus.unmarked,
    RosterFilter.present => status == AttendanceStatus.present,
    RosterFilter.issue => isAttendanceIssueStatus(status),
    RosterFilter.leave => isLeaveStatus(status),
  };

  void _showFilteredAttendanceFeedback(
    Person person,
    AttendanceStatus previousStatus,
  ) {
    if (!mounted || _filter == RosterFilter.all) return;

    final currentStatus = person.status;
    if (_matchesFilter(currentStatus)) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已将 ${person.name} 标记为${currentStatus.label}'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              if (!mounted) return;
              _invalidatePeopleCache();
              setState(() => person.status = previousStatus);
              _save();
            },
          ),
        ),
      );
  }

  void _setStatus(Person person, AttendanceStatus status) {
    Haptic.light();
    final previousStatus = person.status;
    _invalidatePeopleCache();
    setState(
      () => person.status = person.status == status
          ? AttendanceStatus.unmarked
          : status,
    );
    _save();
    _showFilteredAttendanceFeedback(person, previousStatus);
  }

  void _toggleSelection(Person person) {
    Haptic.selection();
    setState(() {
      _selectionMode = true;
      if (!_selected.add(person.id)) _selected.remove(person.id);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _toggleSelectionMode() {
    Haptic.light();
    setState(() {
      if (_selectionMode) {
        _selected.clear();
        _selectionMode = false;
      } else {
        _selected.clear();
        _selectionMode = true;
      }
    });
  }

  bool get _allVisibleSelected {
    final ids = _visiblePeople.map((item) => item.person.id).toSet();
    return ids.isNotEmpty && ids.every(_selected.contains);
  }

  void _selectAllVisible() {
    Haptic.light();
    final ids = _visiblePeople.map((item) => item.person.id).toSet();
    setState(() {
      if (ids.isNotEmpty && ids.every(_selected.contains)) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
      _selectionMode = true;
    });
  }

  void _invertSelectionVisible() {
    Haptic.light();
    final ids = _visiblePeople.map((item) => item.person.id).toSet();
    setState(() {
      for (final id in ids) {
        if (!_selected.add(id)) _selected.remove(id);
      }
      _selectionMode = true;
    });
  }

  void _reorderPeople(int oldIndex, int newIndex) {
    final visible = _visiblePeople;
    if (oldIndex < 0 || oldIndex >= visible.length) return;

    if (newIndex < 0 || newIndex >= visible.length || oldIndex == newIndex) {
      return;
    }

    final visiblePeople = visible.map((item) => item.person).toList();
    final moving = visiblePeople.removeAt(oldIndex);
    visiblePeople.insert(newIndex, moving);

    // A search/filter can hide people between two visible rows. Replace only
    // the visible slots so hidden people keep their relative order and their
    // attendance data stays attached to the same person.
    final visibleIds = visible.map((item) => item.person.id).toSet();
    var reorderedIndex = 0;
    for (var index = 0; index < _people.length; index++) {
      if (visibleIds.contains(_people[index].id)) {
        _people[index] = visiblePeople[reorderedIndex++];
      }
    }

    _invalidatePeopleCache();
    setState(() {});
    _save();
    _toast('已将 ${moving.name} 调整到第 ${_people.indexOf(moving) + 1} 号');
  }

  void _batchSetStatus(AttendanceStatus status) {
    if (_selected.isEmpty) return;
    Haptic.light();
    _invalidatePeopleCache();
    setState(() {
      for (final person in _people.where(
        (person) => _selected.contains(person.id),
      )) {
        person.status = status;
      }
      _selected.clear();
      _selectionMode = false;
    });
    _save();
    _toast('已完成批量标记');
  }

  Future<void> _resetAttendance() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置本次点名？'),
        content: const Text('所有人的状态将恢复为“未点名”，名单不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _invalidatePeopleCache();
    setState(() {
      for (final person in _people) {
        person.status = AttendanceStatus.unmarked;
      }
    });
    await _save();
  }

  Future<void> _markUnmarkedTruancy() async {
    final unmarkedCount = _count(AttendanceStatus.unmarked);
    if (unmarkedCount == 0) {
      _toast('没有未点名人员');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('将未点名人员标记为旷课？'),
        content: Text('共 $unmarkedCount 人，已有考勤状态的人员不会改变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认标记'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _invalidatePeopleCache();
    setState(() {
      for (final person in _people) {
        if (person.status == AttendanceStatus.unmarked) {
          person.status = AttendanceStatus.truancy;
        }
      }
    });
    await _save();
    _toast('已将 $unmarkedCount 人标记为旷课');
  }

  Future<void> _openImportPage() async {
    final result = await Navigator.of(context).push<_ImportRosterResult>(
      MaterialPageRoute(
        builder: (_) => _ImportRosterPage(
          existingCount: _people.length,
          isFirstImport: !_hasImportedRoster,
        ),
      ),
    );
    if (!mounted || result == null || result.names.isEmpty) return;
    _invalidatePeopleCache();
    setState(() {
      if (result.replace) {
        _people.clear();
        _selected.clear();
      }
      final existing = _people
          .map((person) => person.name.toLowerCase())
          .toSet();
      for (final name in result.names) {
        if (existing.add(name.toLowerCase())) {
          _people.add(Person(id: _nextId++, name: name));
        }
      }
    });
    _hasImportedRoster = true;
    await _save();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasImportedRosterKey, true);
    _toast('名单已导入，共 ${_people.length} 人');
  }

  Future<void> _exportRoster() async {
    if (_people.isEmpty) return;
    final content = _people.map((person) => person.name).join('\n');
    final uri = await FilePicker.saveFile(
      dialogTitle: '导出名单',
      fileName: '点名名单.txt',
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: 'text/plain',
    );
    if (uri != null) _toast('名单已导出');
  }

  String _formatCompactDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  String? get _wakeUpScheduleLabel {
    final schedule = _wakeUpSchedule;
    if (schedule == null) return null;
    final syncedAt = _wakeUpScheduleSyncedAt;
    return syncedAt == null
        ? '已同步：${schedule.name}'
        : '已同步：${schedule.name} · ${_formatCompactDateTime(syncedAt)}';
  }

  Future<void> _saveWakeUpAuthToken(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wakeUpAuthTokenKey, value);
  }

  Future<void> _syncWakeUpSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final result = await Navigator.of(context).push<WakeUpSchedulePageResult>(
      MaterialPageRoute(
        builder: (_) => WakeUpSchedulePage(
          initialAuthToken: prefs.getString(_wakeUpAuthTokenKey) ?? '',
          currentScheduleLabel: _wakeUpScheduleLabel,
          backend: _quickImportBackend,
          onAuthTokenSaved: _saveWakeUpAuthToken,
        ),
      ),
    );
    if (result == null) return;

    final syncedAt = DateTime.now();
    await Future.wait([
      prefs.setString(_wakeUpAuthTokenKey, result.authToken),
      prefs.setString(_wakeUpScheduleDataKey, result.shareData),
      prefs.setString(_wakeUpScheduleSyncedAtKey, syncedAt.toIso8601String()),
    ]);
    if (!mounted) return;
    setState(() {
      _wakeUpSchedule = result.schedule;
      _wakeUpScheduleSyncedAt = syncedAt;
    });
    _toast('课程表已同步：${result.schedule.name}');
  }

  List<String> _currentCourseSummary(DateTime now) {
    final schedule = _wakeUpSchedule;
    if (schedule == null) return const [];
    final courses = schedule.currentCoursesAt(now);
    if (courses.isEmpty) return const ['当前课程：当前时段无课程'];
    return [
      '当前课程：${courses.first.summary}',
      for (final course in courses.skip(1)) '同时课程：${course.summary}',
    ];
  }

  Map<String, String> _copyTemplateValues(DateTime now) {
    final schedule = _wakeUpSchedule;
    final courses = schedule?.currentCoursesAt(now) ?? const <CurrentCourse>[];
    String namesWhere(bool Function(AttendanceStatus status) matches) => _people
        .where((person) => matches(person.status))
        .map((person) => person.name)
        .join('、');

    String countWhere(bool Function(AttendanceStatus status) matches) =>
        _people.where((person) => matches(person.status)).length.toString();

    String courseValue(String Function(CurrentCourse course) select) {
      if (schedule == null || courses.isEmpty) return '';
      final values = courses
          .map(select)
          .where((value) => value.trim().isNotEmpty)
          .toSet();
      return values.join('、');
    }

    return {
      '课程': courseValue((course) => course.name),
      '老师': courseValue((course) => course.teacher),
      '应出勤人数': _people.length.toString(),
      '实际出勤人数': _people
          .where((person) => isActuallyPresentStatus(person.status))
          .length
          .toString(),
      '请假名单': namesWhere(isLeaveStatus),
      '请假人数': countWhere(isLeaveStatus),
      '旷课名单': namesWhere((status) => status == AttendanceStatus.truancy),
      '旷课人数': countWhere((status) => status == AttendanceStatus.truancy),
      '迟到名单': namesWhere((status) => status == AttendanceStatus.late),
      '迟到人数': countWhere((status) => status == AttendanceStatus.late),
      '早退名单': namesWhere((status) => status == AttendanceStatus.earlyLeave),
      '早退人数': countWhere((status) => status == AttendanceStatus.earlyLeave),
      '教室': courseValue((course) => course.room),
    };
  }

  Future<void> _openCopyFormatPage() async {
    final result = await Navigator.of(context).push<CopyFormatPageResult>(
      MaterialPageRoute(
        builder: (_) => CopyFormatPage(
          initialTemplate:
              _attendanceCopyTemplate ?? AttendanceCopyTemplate.suggested,
          previewValues: _copyTemplateValues(DateTime.now()),
          usesCustomTemplate: _attendanceCopyTemplate != null,
        ),
      ),
    );
    if (result == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (result.reset) {
      await prefs.remove(_attendanceCopyTemplateKey);
      if (!mounted) return;
      setState(() => _attendanceCopyTemplate = null);
      _toast('已恢复默认复制格式');
      return;
    }

    final template = result.template;
    if (template == null || template.trim().isEmpty) return;
    await prefs.setString(_attendanceCopyTemplateKey, template);
    if (!mounted) return;
    setState(() => _attendanceCopyTemplate = template);
    _toast('自定义复制格式已保存');
  }

  Future<void> _copyAttendanceSummary() async {
    if (_people.isEmpty) return;

    final unmarked = <String>[];
    final present = <String>[];
    final leave = <String>[];
    final personalLeave = <String>[];
    final sickLeave = <String>[];
    final earlyLeave = <String>[];
    final truancy = <String>[];
    final late = <String>[];
    for (final person in _people) {
      switch (person.status) {
        case AttendanceStatus.present:
          present.add(person.name);
        case AttendanceStatus.leave:
          leave.add(person.name);
        case AttendanceStatus.personalLeave:
          personalLeave.add(person.name);
        case AttendanceStatus.sickLeave:
          sickLeave.add(person.name);
        case AttendanceStatus.earlyLeave:
          earlyLeave.add(person.name);
        case AttendanceStatus.truancy:
          truancy.add(person.name);
        case AttendanceStatus.late:
          late.add(person.name);
        case AttendanceStatus.unmarked:
          unmarked.add(person.name);
      }
    }

    if (unmarked.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('还有 ${unmarked.length} 人未点名'),
          content: const Text('当前考勤尚未完成，复制内容中会保留未点名人员提醒。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回点名'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续复制'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}-'
        '${twoDigits(now.month)}-${twoDigits(now.day)} '
        '${twoDigits(now.hour)}:${twoDigits(now.minute)}:${twoDigits(now.second)}';
    final customTemplate = _attendanceCopyTemplate;
    final content = customTemplate == null
        ? [
            '$timestamp 考勤情况：',
            ..._currentCourseSummary(now),
            '正常出勤：${present.join('、')}',
            '公假：${leave.join('、')}',
            '事假：${personalLeave.join('、')}',
            '病假：${sickLeave.join('、')}',
            '早退：${earlyLeave.join('、')}',
            '旷课：${truancy.join('、')}',
            '迟到：${late.join('、')}',
            if (unmarked.isNotEmpty)
              '未点名（${unmarked.length}人）：${unmarked.join('、')}',
          ].join('\n')
        : [
            AttendanceCopyTemplate.render(
              customTemplate,
              _copyTemplateValues(now),
            ),
            if (unmarked.isNotEmpty)
              '未点名（${unmarked.length}人）：${unmarked.join('、')}',
          ].join('\n');

    await Clipboard.setData(ClipboardData(text: content));
    _toast('考勤情况已复制到剪贴板');
  }

  Future<void> _addPerson() async {
    final result = await showDialog<(String, AttendanceStatus)>(
      context: context,
      builder: (_) => const _AddPersonDialog(),
    );
    if (!mounted || result == null) return;
    final name = result.$1;
    if (name.isEmpty) return;
    if (_people.any(
      (person) => person.name.toLowerCase() == name.toLowerCase(),
    )) {
      _toast('名单中已有这个名字');
      return;
    }
    _invalidatePeopleCache();
    setState(
      () => _people.add(Person(id: _nextId++, name: name, status: result.$2)),
    );
    await _save();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final selectedNames = _people
        .where((person) => _selected.contains(person.id))
        .map((person) => person.name)
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('将要删除${selectedNames.length}人'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: Text(
              '${selectedNames.join('、')} 将会被删除，且连同他们目前的考勤状态一并删除，是否继续？',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(76, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    Haptic.light();
    _invalidatePeopleCache();
    setState(() {
      _people.removeWhere((person) => _selected.contains(person.id));
      _selected.clear();
      _selectionMode = false;
    });
    await _save();
  }

  Future<void> _pickRandomPerson() async {
    // 抽签只针对正常到勤（present）的人员，其他状态一律不参与。
    final candidates = _people
        .where((person) => person.status == AttendanceStatus.present)
        .map((person) => RandomCandidate(id: person.id, name: person.name))
        .toList(growable: false);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RandomPickerPage(candidates: candidates),
      ),
    );
  }

  /// 把当前考勤快照保存成一条历史记录，可从「工具箱 > 考勤记录」回看。
  Future<void> _saveAttendanceRecord() async {
    if (_people.isEmpty) return;
    final now = DateTime.now();
    final courses =
        _wakeUpSchedule?.currentCoursesAt(now) ?? const <CurrentCourse>[];
    final course = courses.isEmpty ? null : courses.first;
    final suggestedNote = course?.name ?? _formatCompactDateTime(now);
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _SaveRecordDialog(
        suggestedNote: suggestedNote,
        courseSummary: course?.summary,
        unmarkedCount: _count(AttendanceStatus.unmarked),
      ),
    );
    if (note == null || !mounted) return;
    final record = AttendanceRecord(
      id: '${now.microsecondsSinceEpoch}',
      savedAt: now,
      note: note.trim().isEmpty ? suggestedNote : note.trim(),
      courseName: course?.name,
      teacher: course?.teacher,
      room: course?.room,
      timeRange: course == null ? null : '${course.startTime}-${course.endTime}',
      entries: [
        for (final person in _people)
          AttendanceRecordEntry(
            personId: person.id,
            name: person.name,
            status: person.status,
            fields: Map.of(person.fields),
          ),
      ],
    );
    setState(() => _attendanceHistory.insert(0, record));
    await _saveAttendanceHistory();
    _toast('已保存考勤记录');
  }

  Future<void> _openAttendanceHistory() async {
    final updated = await Navigator.of(context).push<List<AttendanceRecord>>(
      MaterialPageRoute(
        builder: (_) => AttendanceHistoryPage(records: _attendanceHistory),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _attendanceHistory
        ..clear()
        ..addAll(updated);
    });
    await _saveAttendanceHistory();
  }

  Future<void> _openRosterEditor() async {
    final result = await Navigator.of(context).push<RosterEditorResult>(
      MaterialPageRoute(
        builder: (_) => RosterEditorPage(
          people: _people,
          fieldNames: _personFields,
        ),
      ),
    );
    if (!mounted || result == null) return;
    _invalidatePeopleCache();
    setState(() {
      _people
        ..clear()
        ..addAll(result.people);
      _personFields = result.fieldNames;
      _selected.removeWhere(
        (id) => !_people.any((person) => person.id == id),
      );
      if (_people.isEmpty) _selectionMode = false;
      if (_people.isNotEmpty) {
        _nextId =
            _people
                .map((person) => person.id)
                .reduce((a, b) => a > b ? a : b) +
            1;
      }
    });
    await _save();
    await _savePersonFields();
  }

  Future<void> _openBackupRestore() async {
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BackupRestorePage()),
    );
    if (restored != true || !mounted) return;
    await _reloadFromStorage();
    _toast('数据已还原');
  }

  bool get _showActionButton => _tab == _HomeTab.attendance && !_selectionMode;

  /// 考勤 Tab 不设标题栏，头部只有搜索框与筛选条；其余 Tab 保留各自的标题栏。
  PreferredSizeWidget? _buildAppBar() {
    switch (_tab) {
      case _HomeTab.attendance:
        return null;
      case _HomeTab.toolbox:
        return AppBar(title: const Text('工具箱'));
      case _HomeTab.settings:
        return AppBar(title: const Text('设置'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 840;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : switch (_tab) {
            _HomeTab.attendance => _buildAttendanceTab(isWide),
            _HomeTab.toolbox => _ToolboxTab(
              onRandomPick: _pickRandomPerson,
              onOpenHistory: _openAttendanceHistory,
              historyCount: _attendanceHistory.length,
            ),
            _HomeTab.settings => _SettingsTab(
              hasPeople: _people.isNotEmpty,
              scheduleName: _wakeUpSchedule?.name,
              lastModifiedLabel: _lastModifiedLabel,
              hapticEnabled: _hapticEnabled,
              onHapticChanged: _setHapticEnabled,
              onEditRoster: _openRosterEditor,
              onImportRoster: _openImportPage,
              onExportRoster: _exportRoster,
              onCustomizeCopyFormat: _openCopyFormatPage,
              onSyncSchedule: _syncWakeUpSchedule,
              onBackupRestore: _openBackupRestore,
            ),
          };
    // 考勤页没有 AppBar，状态栏图标的明暗得自己声明，否则深色主题下可能
    // 沿用系统主题的深色图标，贴在深色背景上看不见（有 AppBar 的 Tab 由它覆盖）。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        extendBody: !_selectionMode,
        appBar: _buildAppBar(),
        // extendBody 让页面铺到底栏背后，避免为圆角导航留出矩形背景板。
        body: body,
        floatingActionButton: (!_loading && _showActionButton)
            ? _buildActionMenu()
            : null,
        bottomNavigationBar: _selectionMode
            ? _buildBatchBar()
            : _buildBottomNavigationBar(),
      ),
    );
  }

  /// 参考 PiliPlus 的胶囊形悬浮导航：保留 Material 3 的目的地交互，
  /// 只把外层改为带边距、圆角和轻微阴影的浮动容器。
  Widget _buildBottomNavigationBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final bar = Material(
      key: const ValueKey('floating-bottom-navigation'),
      color: colorScheme.surfaceContainer,
      surfaceTintColor: colorScheme.surfaceTint,
      elevation: 3,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _buildNavigationDestination(
                index: _HomeTab.attendance.index,
                icon: Icons.fact_check_outlined,
                selectedIcon: Icons.fact_check_rounded,
                label: '考勤',
              ),
              _buildNavigationDestination(
                index: _HomeTab.toolbox.index,
                icon: Icons.widgets_outlined,
                selectedIcon: Icons.widgets_rounded,
                label: '工具箱',
              ),
              _buildNavigationDestination(
                index: _HomeTab.settings.index,
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );

    return AnimatedSlide(
      key: const ValueKey('bottom-navigation-slide'),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      offset: Offset(
        0,
        _tab == _HomeTab.attendance && !_navigationBarVisible ? 1 : 0,
      ),
      child: IgnorePointer(
        ignoring: _tab == _HomeTab.attendance && !_navigationBarVisible,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 258),
              child: bar,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationDestination({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _tab.index == index;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final shape = BorderRadius.circular(28);

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Tooltip(
          message: label,
          child: AnimatedContainer(
            key: ValueKey('bottom-navigation-destination-$index'),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: shape,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('bottom-navigation-button-$index'),
                borderRadius: shape,
                onTap: () => _selectTab(index),
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return colorScheme.primary.withValues(alpha: 0.14);
                  }
                  if (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)) {
                    return foreground.withValues(alpha: 0.08);
                  }
                  return null;
                }),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(selected ? selectedIcon : icon, color: foreground),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceTab(bool isWide) {
    final horizontal = isWide ? 28.0 : 14.0;
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
            // 搜索框放在非固定的 header sliver 里，随手指逐帧滑走；
            // 筛选条固定在顶部，名单在内层滚动（NestedScrollView 会注入内层控制器）。
            child: NotificationListener<UserScrollNotification>(
              onNotification: _handleAttendanceScrollDirection,
              child: NestedScrollView(
                controller: _rosterScrollController,
                headerSliverBuilder: (context, bodyIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildSearchField(),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedHeaderDelegate(
                      height: 52,
                      child: SizedBox.expand(
                        child: ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: _buildFilterToolbar(isWide),
                        ),
                      ),
                    ),
                  ),
                ],
                body: NotificationListener<ScrollNotification>(
                  onNotification: _handleInnerScroll,
                  child: _buildRoster(isWide),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 右下角悬浮菜单，替代原来标题栏右侧的一排操作按钮。
  Widget _buildActionMenu() {
    final unmarked = _count(AttendanceStatus.unmarked);
    final actions = <({IconData icon, String label, VoidCallback? onTap})>[
      (
        icon: Icons.save_rounded,
        label: '保存当前考勤记录',
        onTap: _people.isEmpty ? null : _saveAttendanceRecord,
      ),
      (icon: Icons.person_add_alt_1_rounded, label: '添加人员', onTap: _addPerson),
      (
        icon: Icons.content_copy_rounded,
        label: '复制考勤情况',
        onTap: _people.isEmpty ? null : _copyAttendanceSummary,
      ),
      (
        icon: Icons.assignment_late_outlined,
        label: '未点名全部标记为旷课',
        onTap: unmarked == 0 ? null : _markUnmarkedTruancy,
      ),
      (
        icon: Icons.restart_alt_rounded,
        label: '重置考勤',
        onTap: _people.isEmpty ? null : _resetAttendance,
      ),
    ];
    final showItems = _fabOpen || _fabController.value > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showItems)
          for (var index = 0; index < actions.length; index++)
            _FabMenuEntry(
              animation: _fabController,
              // 列表第一个在最上面，所以离按钮最近的序号要倒着数。
              order: actions.length - 1 - index,
              count: actions.length,
              child: _FabMenuAction(
                icon: actions[index].icon,
                label: actions[index].label,
                onTap: actions[index].onTap == null
                    ? null
                    : () {
                        _dismissActionMenu();
                        actions[index].onTap!();
                      },
              ),
            ),
        FloatingActionButton(
          key: const ValueKey('fab-menu-toggle'),
          tooltip: _fabOpen ? '收起操作' : '更多操作',
          onPressed: _toggleActionMenu,
          child: RotationTransition(
            // 和菜单用同一根动画，展开和收起时图标都转得连贯。
            turns: _fabController.drive(
              Tween<double>(
                begin: 0,
                end: .125,
              ).chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: _handleSearchChanged,
      decoration: InputDecoration(
        hintText: '搜索姓名、学号、宿舍…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  _invalidatePeopleCache();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = [
      (RosterFilter.all, '全部', _people.length),
      (RosterFilter.unmarked, '未点名', _count(AttendanceStatus.unmarked)),
      (RosterFilter.present, '正常', _count(AttendanceStatus.present)),
      (RosterFilter.issue, '异常', _countAttendanceIssues()),
      (RosterFilter.leave, '请假', _countLeaveTypes()),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in filters) ...[
            FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.$2),
                  const SizedBox(width: 6),
                  _FilterCount(item.$3, highlighted: _filter == item.$1),
                ],
              ),
              selected: _filter == item.$1,
              onSelected: (_) => _setFilter(item.$1),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterToolbar(bool isWide) {
    final chips = _buildFilterChips();
    if (!isWide) {
      return Row(
        children: [
          Expanded(child: chips),
          IconButton(
            tooltip: _selectionMode ? '退出批量' : '批量选择',
            onPressed: _toggleSelectionMode,
            icon: Icon(
              _selectionMode ? Icons.close_rounded : Icons.checklist_rounded,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Text(
          '筛选',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: chips),
        TextButton.icon(
          onPressed: _toggleSelectionMode,
          icon: Icon(
            _selectionMode ? Icons.close_rounded : Icons.checklist_rounded,
          ),
          label: Text(_selectionMode ? '退出批量' : '批量'),
        ),
      ],
    );
  }

  Widget _buildRoster(bool isWide) {
    if (_people.isEmpty) {
      return EmptyState(onImport: _openImportPage);
    }
    final visible = _visiblePeople;
    if (visible.isEmpty) {
      final keyword = _searchController.text.trim();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '在“$_filterLabel”筛选下没有匹配人员',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (keyword.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '当前搜索：“$keyword”',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    // 这两个列表不能用 _rosterScrollController，它属于外层（头部）位置，
    // 内层控制器由 NestedScrollView 通过 PrimaryScrollController 注入。
    final list = _selectionMode
        ? ListView.separated(
            padding: const EdgeInsets.only(bottom: 104),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 7),
            itemBuilder: (context, index) =>
                _buildPersonRow(visible[index], isWide),
          )
        : ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 104),
            itemCount: visible.length,
            buildDefaultDragHandles: false,
            onReorderItem: _reorderPeople,
            proxyDecorator: (child, _, _) => child,
            itemBuilder: (context, index) =>
                _LongPressReorderableDragStartListener(
                  key: ValueKey(visible[index].person.id),
                  index: index,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: index == visible.length - 1 ? 0 : 7,
                    ),
                    child: _buildPersonRow(visible[index], isWide),
                  ),
                ),
          );

    return list;
  }

  Widget _buildPersonRow(_VisiblePerson item, bool isWide) {
    return PersonRow(
      person: item.person,
      number: item.number,
      selected: _selected.contains(item.person.id),
      selectionMode: _selectionMode,
      wide: isWide,
      onToggleSelection: () => _toggleSelection(item.person),
      onStatus: (status) => _setStatus(item.person, status),
    );
  }

  Widget _buildBatchBar() {
    return SafeArea(
      top: false,
      child: Material(
        elevation: 16,
        color: Theme.of(context).colorScheme.inverseSurface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _selected.clear();
                  _selectionMode = false;
                }),
                color: Theme.of(context).colorScheme.onInverseSurface,
                icon: const Icon(Icons.close_rounded),
              ),
              Text(
                '${_selected.length}人',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                onPressed: _selectAllVisible,
                tooltip: _allVisibleSelected ? '全不选' : '全选',
                color: Theme.of(context).colorScheme.onInverseSurface,
                icon: Icon(
                  _allVisibleSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                ),
              ),
              IconButton(
                onPressed: _invertSelectionVisible,
                tooltip: '反选',
                color: Theme.of(context).colorScheme.onInverseSurface,
                icon: const Icon(Icons.flip_to_back_rounded),
              ),
              const Spacer(),
              for (final status in [
                AttendanceStatus.present,
                AttendanceStatus.truancy,
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: status == AttendanceStatus.truancy
                      ? AttendanceExceptionStatusButton(
                          status: AttendanceStatus.truancy,
                          active: false,
                          showLabel: false,
                          compact: true,
                          onSelected: _batchSetStatus,
                        )
                      : IconButton.filledTonal(
                          tooltip: status.label,
                          onPressed: () => _batchSetStatus(status),
                          icon: Icon(
                            status.icon,
                            color: status.adaptiveColor(context),
                          ),
                        ),
                ),
              IconButton(
                tooltip: '删除',
                onPressed: _deleteSelected,
                color: Theme.of(context).colorScheme.errorContainer,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
