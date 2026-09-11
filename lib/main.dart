import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/attendance.dart';
import 'models/attendance_copy_template.dart';
import 'models/course_schedule.dart';
import 'models/person.dart';
import 'services/quick_import/backend_binding.dart';
import 'theme/app_theme.dart';
import 'widgets/attendance_widgets.dart';
import 'widgets/copy_format_dialog.dart';
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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.hasPeople,
    required this.scheduleName,
    required this.onImportRoster,
    required this.onExportRoster,
    required this.onCustomizeCopyFormat,
    required this.onSyncSchedule,
  });

  final bool hasPeople;
  final String? scheduleName;
  final VoidCallback onImportRoster;
  final VoidCallback onExportRoster;
  final VoidCallback onCustomizeCopyFormat;
  final VoidCallback onSyncSchedule;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _SettingsSectionLabel('名单'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
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
          const _SettingsSectionLabel('复制'),
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
          const _SettingsSectionLabel('课程表'),
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
        ],
      ),
    ),
  );
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel(this.label);

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

class _ToolbarSliverDelegate extends SliverPersistentHeaderDelegate {
  const _ToolbarSliverDelegate({required this.child, required this.height});

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
  bool shouldRebuild(covariant _ToolbarSliverDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
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
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      HapticFeedback.selectionClick();
    }
  }
}

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
    with WidgetsBindingObserver {
  static const _storageKey = 'roll_call_people_v1';
  static const _hasImportedRosterKey = 'roll_call_has_imported_v1';
  static const _lastModifiedStorageKey = 'roll_call_last_modified_v1';
  static const _wakeUpAuthTokenKey = 'wakeup_auth_token_v1';
  static const _wakeUpScheduleDataKey = 'wakeup_schedule_data_v1';
  static const _wakeUpScheduleSyncedAtKey = 'wakeup_schedule_synced_at_v1';
  static const _attendanceCopyTemplateKey = 'attendance_copy_template_v2';
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
  final _topSearchFocusNode = FocusNode();
  final _rosterScrollController = ScrollController();
  final _overviewKey = GlobalKey();
  final _quickImportBackend = createQuickImportBackend();
  final List<Person> _people = [];
  final Set<int> _selected = {};
  RosterFilter _filter = RosterFilter.all;
  List<_VisiblePerson>? _visiblePeopleCache;
  String _visiblePeopleCacheKeyword = '';
  RosterFilter _visiblePeopleCacheFilter = RosterFilter.all;
  Map<AttendanceStatus, int>? _statusCountsCache;
  bool _loading = true;
  bool _hasImportedRoster = false;
  bool _selectionMode = false;
  bool _overviewCollapsed = false;
  bool _topSearchMode = false;
  bool _keepOverviewHidden = false;
  double _innerScrollOffset = 0;
  ScrollPosition? _innerScrollPosition;
  int _nextId = 1;
  DateTime? _lastModifiedAt;
  WakeUpSchedule? _wakeUpSchedule;
  DateTime? _wakeUpScheduleSyncedAt;
  String? _attendanceCopyTemplate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rosterScrollController.addListener(_handleRosterScroll);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rosterScrollController
      ..removeListener(_handleRosterScroll)
      ..dispose();
    _searchController.dispose();
    _topSearchFocusNode.dispose();
    super.dispose();
  }

  void _handleRosterScroll() {
    if (!_rosterScrollController.hasClients || !mounted) return;
    if (_keepOverviewHidden) {
      if (_rosterScrollController.offset <= 1) {
        setState(() {
          _keepOverviewHidden = false;
          _overviewCollapsed = false;
        });
      }
      return;
    }
    final overviewContext = _overviewKey.currentContext;
    final overviewRenderObject = overviewContext?.findRenderObject();
    if (overviewRenderObject is! RenderBox) return;
    final collapsed =
        _rosterScrollController.offset >= overviewRenderObject.size.height - 1;
    if (collapsed != _overviewCollapsed) {
      setState(() => _overviewCollapsed = collapsed);
    }
  }

  void _openTopSearch() {
    setState(() => _topSearchMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_topSearchMode && mounted) {
        _topSearchFocusNode.requestFocus();
      }
    });
  }

  void _closeTopSearch() {
    _searchController.clear();
    _topSearchFocusNode.unfocus();
    _invalidatePeopleCache();
    final keepOverviewHidden = _innerScrollOffset > 1 || _overviewCollapsed;
    setState(() {
      _topSearchMode = false;
      _keepOverviewHidden = keepOverviewHidden;
      _overviewCollapsed = keepOverviewHidden;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final position = _innerScrollPosition;
      if (position == null || !position.hasContentDimensions) return;
      final targetOffset = _innerScrollOffset.clamp(
        0.0,
        position.maxScrollExtent,
      );
      if ((position.pixels - targetOffset).abs() > 0.5) {
        position.jumpTo(targetOffset);
      }
      if (targetOffset <= 1 && mounted) {
        setState(() {
          _keepOverviewHidden = false;
          _overviewCollapsed = false;
        });
      }
    });
  }

  void _scrollToTop() {
    if (!mounted || _topSearchMode) return;

    if (_keepOverviewHidden) {
      setState(() {
        _keepOverviewHidden = false;
        _overviewCollapsed = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      const duration = Duration(milliseconds: 360);
      const curve = Curves.easeOutCubic;
      final innerPosition = _innerScrollPosition;
      if (innerPosition != null && innerPosition.hasContentDimensions) {
        innerPosition.animateTo(0, duration: duration, curve: curve);
      }
      if (_rosterScrollController.hasClients) {
        _rosterScrollController.animateTo(0, duration: duration, curve: curve);
      }
    });
  }

  bool _handleInnerScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical) {
      _innerScrollOffset = notification.metrics.pixels;
      _innerScrollPosition = Scrollable.maybeOf(notification.context!)
          ?.position;
      if (_keepOverviewHidden && _innerScrollOffset <= 1 && mounted) {
        setState(() {
          _keepOverviewHidden = false;
          _overviewCollapsed = false;
        });
      }
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
    _lastModifiedAt = DateTime.tryParse(
      prefs.getString(_lastModifiedStorageKey) ?? '',
    );
    final cachedSchedule = prefs.getString(_wakeUpScheduleDataKey);
    _attendanceCopyTemplate = prefs.getString(_attendanceCopyTemplateKey);
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
      final searched =
          keyword.isEmpty ||
          person.name.toLowerCase().contains(keyword) ||
          person.fullPinyin.contains(keyword) ||
          person.pinyinInitials.contains(keyword);
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
    setState(() {
      _selectionMode = true;
      if (!_selected.add(person.id)) _selected.remove(person.id);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _toggleSelectionMode() {
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
    _invalidatePeopleCache();
    setState(() {
      _people.removeWhere((person) => _selected.contains(person.id));
      _selected.clear();
      _selectionMode = false;
    });
    await _save();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsPage(
          hasPeople: _people.isNotEmpty,
          scheduleName: _wakeUpSchedule?.name,
          onImportRoster: _openImportPage,
          onExportRoster: _exportRoster,
          onCustomizeCopyFormat: _openCopyFormatPage,
          onSyncSchedule: _syncWakeUpSchedule,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 840;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
        titleSpacing: _topSearchMode ? 0 : 16,
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: _topSearchMode
            ? const SizedBox(
                width: 48,
                child: Center(child: Icon(Icons.search_rounded)),
              )
            : null,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _topSearchMode ? null : _scrollToTop,
          child: SizedBox(
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) => TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _topSearchMode ? 1 : 0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeInOutCubic,
                builder: (context, progress, child) {
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Opacity(
                        opacity: 1 - progress,
                        child: Tooltip(
                          message: '回到顶部',
                          child: InkWell(
                            onTap: _scrollToTop,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  const AppMark(),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Text(
                                          '快捷考勤喵',
                                          style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '上次修改：$_lastModifiedLabel',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  );
                },
                child: TextField(
                  controller: _searchController,
                  focusNode: _topSearchFocusNode,
                  onChanged: _handleSearchChanged,
                  decoration: InputDecoration(
                    hintText: '搜索姓名',
                    isDense: true,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              _searchController.clear();
                              _invalidatePeopleCache();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          if (_topSearchMode)
            IconButton(
              tooltip: '关闭搜索',
              onPressed: _closeTopSearch,
              icon: const Icon(Icons.close_rounded),
            )
          else if (_overviewCollapsed)
            IconButton(
              tooltip: '搜索姓名',
              onPressed: _openTopSearch,
              icon: const Icon(Icons.search_rounded),
            ),
          if (!_topSearchMode && !_selectionMode)
            IconButton(
              tooltip: '添加人员',
              onPressed: _addPerson,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          if (!_topSearchMode)
            IconButton(
              tooltip: '复制考勤情况',
              onPressed: _people.isEmpty ? null : _copyAttendanceSummary,
              icon: const Icon(Icons.content_copy_rounded),
            ),
          if (!_topSearchMode)
            IconButton(
              tooltip: '未点名全部标记为旷课',
              onPressed: _count(AttendanceStatus.unmarked) == 0
                  ? null
                  : _markUnmarkedTruancy,
              icon: const Icon(Icons.assignment_late_outlined),
            ),
          if (!_topSearchMode)
            IconButton(
              tooltip: '重置考勤',
              onPressed: _people.isEmpty ? null : _resetAttendance,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          if (!_topSearchMode)
            IconButton(
              tooltip: '设置',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isWide ? 28 : 14,
                      6,
                      isWide ? 28 : 14,
                      12,
                    ),
                    child: NestedScrollView(
                      controller: _rosterScrollController,
                      headerSliverBuilder: (context, innerBoxIsScrolled) => [
                        if (!_topSearchMode && !_keepOverviewHidden)
                          SliverToBoxAdapter(
                            child: Column(
                              key: _overviewKey,
                              children: [
                                const SizedBox(height: 14),
                                _buildStats(),
                                const SizedBox(height: 16),
                                _buildSearchToolbar(isWide),
                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _ToolbarSliverDelegate(
                            height: 52,
                            child: SizedBox.expand(
                              child: ColoredBox(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: _buildFilterToolbar(isWide),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      body: _buildRoster(isWide),
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: _selectionMode ? _buildBatchBar() : null,
    );
  }

  Widget _buildStats() {
    final availableWidth = MediaQuery.sizeOf(context).width - 28;
    final isWide = MediaQuery.sizeOf(context).width >= 560;
    final items = [
      (
        '未点名',
        '${_count(AttendanceStatus.unmarked)}/${_people.length}',
        AttendanceStatus.unmarked.adaptiveColor(context),
        Icons.pending_actions_rounded,
      ),
      (
        '正常',
        _count(AttendanceStatus.present),
        AttendanceStatus.present.adaptiveColor(context),
        Icons.check_circle_rounded,
      ),
      (
        '异常',
        _countAttendanceIssues(),
        AttendanceStatus.truancy.adaptiveColor(context),
        Icons.warning_amber_rounded,
      ),
      (
        '请假',
        _countLeaveTypes(),
        AttendanceStatus.leave.adaptiveColor(context),
        Icons.beach_access_rounded,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 4 : 2,
        childAspectRatio: isWide ? 2.35 : (availableWidth >= 480 ? 4.0 : 2.6),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(item.$4, size: 19, color: item.$3),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          '${item.$2}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: _handleSearchChanged,
      decoration: InputDecoration(
        hintText: '搜索姓名',
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
      (RosterFilter.all, '全部'),
      (RosterFilter.unmarked, '未点名'),
      (RosterFilter.present, '正常'),
      (RosterFilter.issue, '异常'),
      (RosterFilter.leave, '请假'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in filters) ...[
            FilterChip(
              label: Text(item.$2),
              selected: _filter == item.$1,
              onSelected: (_) => _setFilter(item.$1),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchToolbar(bool isWide) {
    final search = _buildSearchField();
    if (isWide) {
      return Row(
        children: [
          Text(
            '名单',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 260, child: search),
          const Spacer(),
        ],
      );
    }
    return Row(children: [Expanded(child: search)]);
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
    final list = _selectionMode
        ? ListView.separated(
            padding: const EdgeInsets.only(bottom: 82),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 7),
            itemBuilder: (context, index) =>
                _buildPersonRow(visible[index], isWide),
          )
        : ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 82),
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

    return NotificationListener<ScrollNotification>(
      onNotification: _handleInnerScroll,
      child: list,
    );
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
