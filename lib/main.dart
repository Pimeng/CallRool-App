import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _performanceDiagnostics = bool.fromEnvironment(
  'ROLLCALL_PERF',
  defaultValue: false,
);

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

class RollCallApp extends StatelessWidget {
  const RollCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: kDebugMode && _performanceDiagnostics,
      title: '快捷考勤',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B45)),
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
        fontFamily: 'Microsoft YaHei',
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE1E7E2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4E9A70), width: 1.5),
          ),
        ),
      ),
      home: const RollCallPage(),
    );
  }
}

enum AttendanceStatus {
  unmarked,
  present,
  absent,
  leave,
  personalLeave,
  sickLeave,
}

extension AttendanceStatusUi on AttendanceStatus {
  String get label => switch (this) {
    AttendanceStatus.unmarked => '未点名',
    AttendanceStatus.present => '正常',
    AttendanceStatus.absent => '缺勤',
    AttendanceStatus.leave => '公假',
    AttendanceStatus.personalLeave => '事假',
    AttendanceStatus.sickLeave => '病假',
  };
  Color get color => switch (this) {
    AttendanceStatus.unmarked => const Color(0xFF77817B),
    AttendanceStatus.present => const Color(0xFF198754),
    AttendanceStatus.absent => const Color(0xFFD14C3E),
    AttendanceStatus.leave => const Color(0xFFDA8610),
    AttendanceStatus.personalLeave => const Color(0xFF8B5FBF),
    AttendanceStatus.sickLeave => const Color(0xFF3D7DB8),
  };
  Color get softColor => switch (this) {
    AttendanceStatus.unmarked => const Color(0xFFF0F2F0),
    AttendanceStatus.present => const Color(0xFFE6F5EC),
    AttendanceStatus.absent => const Color(0xFFFCEAE7),
    AttendanceStatus.leave => const Color(0xFFFFF3DD),
    AttendanceStatus.personalLeave => const Color(0xFFF2E9FA),
    AttendanceStatus.sickLeave => const Color(0xFFE6F1FB),
  };
  IconData get icon => switch (this) {
    AttendanceStatus.unmarked => Icons.remove_rounded,
    AttendanceStatus.present => Icons.check_rounded,
    AttendanceStatus.absent => Icons.close_rounded,
    AttendanceStatus.leave => Icons.beach_access_rounded,
    AttendanceStatus.personalLeave => Icons.person_outline_rounded,
    AttendanceStatus.sickLeave => Icons.local_hospital_outlined,
  };
}

bool _isAbsenceStatus(AttendanceStatus status) =>
    status == AttendanceStatus.absent ||
    status == AttendanceStatus.leave ||
    status == AttendanceStatus.personalLeave ||
    status == AttendanceStatus.sickLeave;

class Person {
  Person({
    required this.id,
    required this.name,
    this.status = AttendanceStatus.unmarked,
  });
  final int id;
  final String name;
  AttendanceStatus status;

  late final String fullPinyin =
      PinyinHelper.getPinyinE(name, separator: '').toLowerCase();
  late final String pinyinInitials =
      PinyinHelper.getShortPinyin(name).toLowerCase();

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

class _VisiblePerson {
  const _VisiblePerson({required this.person, required this.number});

  final Person person;
  final int number;
}

enum RosterFilter { all, unmarked, present, absent }

class RollCallPage extends StatefulWidget {
  const RollCallPage({super.key});

  @override
  State<RollCallPage> createState() => _RollCallPageState();
}

class _RollCallPageState extends State<RollCallPage>
    with WidgetsBindingObserver {
  static const _storageKey = 'roll_call_people_v1';
  final _searchController = TextEditingController();
  final List<Person> _people = [];
  final Set<int> _selected = {};
  RosterFilter _filter = RosterFilter.all;
  List<_VisiblePerson>? _visiblePeopleCache;
  String _visiblePeopleCacheKeyword = '';
  RosterFilter _visiblePeopleCacheFilter = RosterFilter.all;
  Map<AttendanceStatus, int>? _statusCountsCache;
  bool _loading = true;
  bool _selectionMode = false;
  int _nextId = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
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
    if (raw != null) {
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
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_people.map((person) => person.toJson()).toList()),
    );
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

  int _countAbsentTypes() => _people
      .where((person) => person.status != AttendanceStatus.unmarked)
      .where((person) => person.status != AttendanceStatus.present)
      .length;

  List<_VisiblePerson> get _visiblePeople {
    final keyword = _searchController.text
        .trim()
        .toLowerCase()
        .replaceAll(' ', '');
    final cached = _visiblePeopleCache;
    if (cached != null &&
        keyword == _visiblePeopleCacheKeyword &&
        _filter == _visiblePeopleCacheFilter) {
      return cached;
    }

    final visible = <_VisiblePerson>[];
    for (var index = 0; index < _people.length; index++) {
      final person = _people[index];
      final searched = keyword.isEmpty ||
          person.name.toLowerCase().contains(keyword) ||
          person.fullPinyin.contains(keyword) ||
          person.pinyinInitials.contains(keyword);
      final filtered = switch (_filter) {
        RosterFilter.all => true,
        RosterFilter.unmarked => person.status == AttendanceStatus.unmarked,
        RosterFilter.present => person.status == AttendanceStatus.present,
        RosterFilter.absent =>
          person.status != AttendanceStatus.unmarked &&
              person.status != AttendanceStatus.present,
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

  List<String> _parseNames(String text) {
    final seen = <String>{};
    return const LineSplitter()
        .convert(text.replaceAll('\r', ''))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && seen.add(name.toLowerCase()))
        .toList();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<AttendanceStatus?> _chooseAbsenceType() async {
    return showDialog<AttendanceStatus>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择缺勤类型'),
        children: [
          for (final status in [
            AttendanceStatus.absent,
            AttendanceStatus.leave,
            AttendanceStatus.personalLeave,
            AttendanceStatus.sickLeave,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, status),
              child: Row(
                children: [
                  Icon(status.icon, color: status.color),
                  const SizedBox(width: 12),
                  Text(status.label),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, AttendanceStatus.unmarked),
            child: Row(
              children: [
                Icon(
                  AttendanceStatus.unmarked.icon,
                  color: AttendanceStatus.unmarked.color,
                ),
                const SizedBox(width: 12),
                const Text('重置'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setStatus(Person person, AttendanceStatus status) async {
    if (status == AttendanceStatus.absent) {
      final selected = await _chooseAbsenceType();
      if (selected == null || !mounted) return;
      status = selected;
    }
    _invalidatePeopleCache();
    setState(
      () => person.status = person.status == status
          ? AttendanceStatus.unmarked
          : status,
    );
    _save();
  }

  void _toggleSelection(Person person) {
    setState(() {
      _selectionMode = true;
      if (!_selected.add(person.id)) _selected.remove(person.id);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelectionMode() {
    setState(() {
      _selected.clear();
      _selectionMode = true;
    });
  }

  void _batchSetStatus(AttendanceStatus status) async {
    if (_selected.isEmpty) return;
    if (status == AttendanceStatus.absent) {
      final selected = await _chooseAbsenceType();
      if (selected == null || !mounted) return;
      status = selected;
    }
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

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    var names = <String>[];
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          title: const Text('导入名单'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('一行一个名字，自动忽略空行和重复姓名。'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 7,
                  maxLines: 9,
                  decoration: const InputDecoration(hintText: '张三\n李四\n王五'),
                  onChanged: (value) =>
                      setDialogState(() => names = _parseNames(value)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.pickFile(
                          dialogTitle: '选择名单文件',
                          type: FileType.custom,
                          allowedExtensions: const ['txt'],
                        );
                        if (picked == null) return;
                        final text = utf8.decode(
                          await picked.readAsBytes(),
                          allowMalformed: true,
                        );
                        controller.text = text;
                        setDialogState(() => names = _parseNames(text));
                      },
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('选择 TXT'),
                    ),
                    const Spacer(),
                    Text(
                      '${names.length} 人',
                      style: const TextStyle(color: Color(0xFF66736B)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: names.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, 'append'),
              child: const Text('追加'),
            ),
            FilledButton(
              onPressed: names.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, 'replace'),
              child: const Text('替换现有'),
            ),
          ],
        ),
      ),
    );
    if (action == null || names.isEmpty) return;
    _invalidatePeopleCache();
    setState(() {
      if (action == 'replace') {
        _people.clear();
        _selected.clear();
      }
      final existing = _people
          .map((person) => person.name.toLowerCase())
          .toSet();
      for (final name in names) {
        if (existing.add(name.toLowerCase())) {
          _people.add(Person(id: _nextId++, name: name));
        }
      }
    });
    await _save();
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

  Future<void> _addPerson() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加人员'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: '姓名'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (_people.any(
      (person) => person.name.toLowerCase() == name.toLowerCase(),
    )) {
      _toast('名单中已有这个名字');
      return;
    }
    _invalidatePeopleCache();
    setState(() => _people.add(Person(id: _nextId++, name: name)));
    await _save();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除已选 ${_selected.length} 人？'),
        content: const Text('他们的当前考勤状态也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(76, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
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

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 840;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
        titleSpacing: 16,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFF5F7F5),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppMark(),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '快捷考勤',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                Text(
                  '班委快捷考勤APP',
                  style: TextStyle(fontSize: 11, color: Color(0xFF718078)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '重置考勤',
            onPressed: _people.isEmpty ? null : _resetAttendance,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '名单操作',
            onSelected: (value) =>
                value == 'import' ? _showImportDialog() : _exportRoster(),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_file_rounded),
                  title: Text('导入名单'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download_rounded),
                  title: Text('导出名单'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
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
                    child: Column(
                      children: [
                        const SizedBox(height: 14),
                        _buildStats(),
                        const SizedBox(height: 16),
                        _buildToolbar(isWide),
                        const SizedBox(height: 10),
                        Expanded(child: _buildRoster(isWide)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _addPerson,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('添加'),
            ),
      bottomNavigationBar: _selectionMode ? _buildBatchBar() : null,
    );
  }

  Widget _buildStats() {
    final items = [
      (
        '未点名',
        _count(AttendanceStatus.unmarked),
        AttendanceStatus.unmarked.color,
        Icons.pending_actions_rounded,
      ),
      (
        '正常',
        _count(AttendanceStatus.present),
        AttendanceStatus.present.color,
        Icons.check_circle_rounded,
      ),
      (
        '缺勤',
        _countAbsentTypes(),
        AttendanceStatus.absent.color,
        Icons.cancel_rounded,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 2.35,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFFE3E9E4)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: item.$3.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(item.$4, size: 15, color: item.$3),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${item.$2}',
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF718078),
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

  Widget _buildToolbar(bool isWide) {
    final filters = [
      (RosterFilter.all, '全部'),
      (RosterFilter.unmarked, '未点名'),
      (RosterFilter.present, '正常'),
      (RosterFilter.absent, '缺勤'),
    ];
    final search = TextField(
      controller: _searchController,
      onChanged: (_) {
        _invalidatePeopleCache();
        setState(() {});
      },
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
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in filters) ...[
            FilterChip(
              label: Text(item.$2),
              selected: _filter == item.$1,
              onSelected: (_) {
                _invalidatePeopleCache();
                setState(() => _filter = item.$1);
              },
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
    if (isWide) {
      return Row(
        children: [
          const Text(
            '名单',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF526159),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 260, child: search),
          const SizedBox(width: 12),
          Expanded(child: chips),
          TextButton.icon(
            onPressed: _enterSelectionMode,
            icon: const Icon(Icons.checklist_rounded),
            label: const Text('批量'),
          ),
        ],
      );
    }
    return Column(
      children: [
        search,
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: chips),
            IconButton(
              tooltip: '批量选择',
              onPressed: _enterSelectionMode,
              icon: const Icon(Icons.checklist_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRoster(bool isWide) {
    if (_people.isEmpty) {
      return _EmptyState(onImport: _showImportDialog);
    }
    final visible = _visiblePeople;
    if (visible.isEmpty) {
      return const Center(
        child: Text('没有匹配的人员', style: TextStyle(color: Color(0xFF718078))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 82),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 7),
      itemBuilder: (context, index) => _PersonRow(
        person: visible[index].person,
        number: visible[index].number,
        selected: _selected.contains(visible[index].person.id),
        selectionMode: _selectionMode,
        wide: isWide,
        onToggleSelection: () => _toggleSelection(visible[index].person),
        onStatus: (status) => _setStatus(visible[index].person, status),
      ),
    );
  }

  Widget _buildBatchBar() {
    return SafeArea(
      top: false,
      child: Material(
        elevation: 16,
        color: const Color(0xFF1F2D26),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _selected.clear();
                  _selectionMode = false;
                }),
                color: Colors.white,
                icon: const Icon(Icons.close_rounded),
              ),
              Text(
                '${_selected.length}人',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              for (final status in [
                AttendanceStatus.present,
                AttendanceStatus.absent,
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: IconButton.filledTonal(
                    tooltip: status.label,
                    onPressed: () => _batchSetStatus(status),
                    icon: Icon(status.icon, color: status.color),
                  ),
                ),
              IconButton(
                tooltip: '删除',
                onPressed: _deleteSelected,
                color: const Color(0xFFFFB4AB),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
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
                    child: _QuickStatusButton(
                      status: status == AttendanceStatus.absent &&
                              _isAbsenceStatus(person.status)
                          ? person.status
                          : status,
                      active: status == AttendanceStatus.absent
                          ? _isAbsenceStatus(person.status)
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

class _QuickStatusButton extends StatelessWidget {
  const _QuickStatusButton({
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
  Widget build(BuildContext context) {
    return Tooltip(
      message: status.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          // Keep both animation endpoints finite. Animating from `null`
          // (unbounded/content-sized) to a fixed width causes
          // BoxConstraints.lerp to assert during window resizing.
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});
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

class _AppMark extends StatelessWidget {
  const _AppMark();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        color: const Color(0xFF176B45),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.how_to_reg_rounded,
        color: Colors.white,
        size: 21,
      ),
    );
  }
}
