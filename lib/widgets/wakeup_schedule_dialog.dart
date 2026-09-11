import 'package:flutter/material.dart';

import '../models/course_schedule.dart';
import '../services/wakeup_schedule_service.dart';

DateTime _currentTime() => DateTime.now();

class WakeUpSchedulePageResult {
  const WakeUpSchedulePageResult({
    required this.authToken,
    required this.shareData,
    required this.schedule,
  });

  final String authToken;
  final String shareData;
  final WakeUpSchedule schedule;
}

class WakeUpSchedulePage extends StatefulWidget {
  const WakeUpSchedulePage({
    super.key,
    required this.initialAuthToken,
    required this.service,
    required this.onAuthTokenSaved,
    this.now = _currentTime,
    this.currentScheduleLabel,
  });

  final String initialAuthToken;
  final String? currentScheduleLabel;
  final WakeUpScheduleService service;
  final Future<void> Function(String value) onAuthTokenSaved;
  final DateTime Function() now;

  @override
  State<WakeUpSchedulePage> createState() => _WakeUpSchedulePageState();
}

class _WakeUpSchedulePageState extends State<WakeUpSchedulePage> {
  final _shareCodeController = TextEditingController();
  late String _authToken;
  bool _loading = false;
  String? _errorMessage;
  String? _previewShareData;
  WakeUpSchedule? _previewSchedule;
  DateTime? _previewedAt;

  bool get _canPreview =>
      !_loading &&
      _authToken.isNotEmpty &&
      _shareCodeController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _authToken = widget.initialAuthToken.trim();
  }

  @override
  void dispose() {
    _shareCodeController.dispose();
    super.dispose();
  }

  Future<void> _editAuthToken() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _AuthTokenDialog(initialValue: _authToken),
    );
    if (!mounted || value == null) return;
    setState(() {
      _authToken = value;
      _previewSchedule = null;
      _previewShareData = null;
      _errorMessage = null;
    });
    await widget.onAuthTokenSaved(value);
  }

  void _handleShareCodeChanged(String value) {
    final shareCode = extractWakeUpShareCode(value);
    if (shareCode != value.trim()) {
      _shareCodeController.value = TextEditingValue(
        text: shareCode,
        selection: TextSelection.collapsed(offset: shareCode.length),
      );
    }
    setState(() {
      _previewSchedule = null;
      _previewShareData = null;
      _errorMessage = null;
    });
  }

  Future<void> _preview() async {
    if (!_canPreview) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _errorMessage = null;
      _previewSchedule = null;
      _previewShareData = null;
    });
    try {
      final shareData = await widget.service.fetchShareData(
        authToken: _authToken,
        shareCode: extractWakeUpShareCode(_shareCodeController.text),
      );
      final schedule = WakeUpSchedule.parse(shareData);
      if (!mounted) return;
      setState(() {
        _previewShareData = shareData;
        _previewSchedule = schedule;
        _previewedAt = widget.now();
      });
    } on WakeUpScheduleException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } on FormatException {
      if (mounted) {
        setState(() => _errorMessage = '课程表数据不完整或格式不受支持。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sync() {
    final shareData = _previewShareData;
    final schedule = _previewSchedule;
    if (shareData == null || schedule == null) return;
    Navigator.pop(
      context,
      WakeUpSchedulePageResult(
        authToken: _authToken,
        shareData: shareData,
        schedule: schedule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _previewSchedule;
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步 WakeUp 课程表'),
        actions: [
          IconButton(
            tooltip: '设置 authToken',
            onPressed: _editAuthToken,
            icon: Icon(
              _authToken.isEmpty
                  ? Icons.settings_outlined
                  : Icons.settings_rounded,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (widget.currentScheduleLabel != null) ...[
                  _InfoPanel(
                    icon: Icons.event_available_rounded,
                    text: widget.currentScheduleLabel!,
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _shareCodeController,
                  autofocus: _authToken.isNotEmpty,
                  autocorrect: false,
                  minLines: 5,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: 'shareCode 或 WakeUp 分享口令',
                    alignLabelWithHint: true,
                    helperText: _authToken.isEmpty
                        ? '请先通过右上角设置 authToken'
                        : '可直接粘贴完整分享口令，不会保存',
                  ),
                  onChanged: _handleShareCodeChanged,
                  onSubmitted: (_) => _preview(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _canPreview ? _preview : null,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.preview_rounded),
                  label: Text(_loading ? '正在获取课程表…' : '预览课程'),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  _InfoPanel(
                    icon: Icons.error_outline_rounded,
                    text: _errorMessage!,
                    error: true,
                  ),
                ],
                if (schedule != null) ...[
                  const SizedBox(height: 22),
                  Text(
                    schedule.name,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _SchedulePreview(schedule: schedule, now: _previewedAt!),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: schedule == null
          ? null
          : SafeArea(
              top: false,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _sync,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('同步此课程表'),
                  ),
                ),
              ),
            ),
    );
  }
}

class _AuthTokenDialog extends StatefulWidget {
  const _AuthTokenDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_AuthTokenDialog> createState() => _AuthTokenDialogState();
}

class _AuthTokenDialogState extends State<_AuthTokenDialog> {
  late final TextEditingController _controller;
  bool _hideToken = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('设置 authToken'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      obscureText: _hideToken,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'authToken',
        helperText: '仅保存在本机，用于获取课程表',
        suffixIcon: IconButton(
          tooltip: _hideToken ? '显示 authToken' : '隐藏 authToken',
          onPressed: () => setState(() => _hideToken = !_hideToken),
          icon: Icon(
            _hideToken
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty ? null : _save,
        child: const Text('保存'),
      ),
    ],
  );

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }
}

class _SchedulePreview extends StatelessWidget {
  const _SchedulePreview({required this.schedule, required this.now});

  final WakeUpSchedule schedule;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final current = schedule.currentCoursesAt(now);
    final upcoming = schedule.upcomingCoursesAt(
      now,
      limit: current.isEmpty ? 2 : 1,
    );
    return Column(
      children: [
        for (final course in current)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CoursePreviewCard(
              label: '当前课程',
              name: course.name,
              teacher: course.teacher,
              room: course.room,
              time: '${course.startTime}-${course.endTime}',
            ),
          ),
        for (var index = 0; index < upcoming.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CoursePreviewCard(
              label: current.isNotEmpty ? '下一节课' : '接下来第 ${index + 1} 节',
              name: upcoming[index].name,
              teacher: upcoming[index].teacher,
              room: upcoming[index].room,
              time:
                  '${_dateLabel(upcoming[index].startAt, now)} '
                  '${upcoming[index].startTime}-${upcoming[index].endTime}',
            ),
          ),
        if (current.isEmpty && upcoming.isEmpty)
          const _InfoPanel(icon: Icons.event_busy_rounded, text: '本学期接下来没有课程'),
      ],
    );
  }

  String _dateLabel(DateTime value, DateTime now) {
    final date = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = date.difference(today).inDays;
    if (difference == 0) return '今天';
    if (difference == 1) return '明天';
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${value.month}月${value.day}日 周${weekdays[value.weekday - 1]}';
  }
}

class _CoursePreviewCard extends StatelessWidget {
  const _CoursePreviewCard({
    required this.label,
    required this.name,
    required this.teacher,
    required this.room,
    required this.time,
  });

  final String label;
  final String name;
  final String teacher;
  final String room;
  final String time;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.menu_book_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(time),
                Text(room.isEmpty ? '地点未填写' : room),
                if (teacher.isNotEmpty) Text(teacher),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.text,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: error ? colors.onErrorContainer : colors.onPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: error
                    ? colors.onErrorContainer
                    : colors.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
