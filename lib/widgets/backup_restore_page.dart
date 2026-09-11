import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/backup_service.dart';

/// 备份与还原页：导出全部本地数据为 JSON，或从备份文件覆盖还原。
///
/// 还原成功后 pop `true`，由调用方重新从本地存储加载数据。
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  BackupSummary? _summary;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshSummary();
  }

  Future<void> _refreshSummary() async {
    final summary = await BackupService.currentSummary();
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('操作失败'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}';
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final content = await BackupService.export();
      final uri = await FilePicker.saveFile(
        dialogTitle: '导出备份',
        fileName: '点名备份_${_timestamp()}.json',
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
      );
      if (!mounted) return;
      if (uri != null) _toast('备份已导出');
    } catch (error) {
      if (mounted) await _showError('导出备份失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择备份文件',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked == null) return;
      final raw = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
      if (!mounted) return;

      final BackupSummary summary;
      try {
        summary = BackupService.inspect(raw);
      } on BackupException catch (error) {
        await _showError(error.message);
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('用备份覆盖当前数据？'),
          content: Text(
            '备份包含 ${summary.peopleCount} 人名单、'
            '${summary.historyCount} 条考勤记录'
            '${summary.hasSchedule ? '、课程表信息' : ''}。\n\n'
            '还原后当前名单、考勤状态、历史记录和扩展字段都会被替换，此操作无法撤销。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('覆盖还原'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final restored = await BackupService.restore(raw);
      if (!mounted) return;
      _toast(
        '已还原 ${restored.peopleCount} 人名单、'
        '${restored.historyCount} 条考勤记录',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) await _showError('还原失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('备份与还原')),
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
                    const Text(
                      '导出备份',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '把以下本机数据保存成一个 JSON 文件，方便换机或重装后恢复：'
                      '\n· 名单、考勤状态与扩展字段'
                      '\n· 已保存的考勤历史记录'
                      '\n· 自定义复制格式'
                      '\n· 已同步的 WakeUp 课程表',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '为保护账号安全，登录凭据不会写入备份文件，还原后重新同步一次课程表即可。',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary == null
                          ? '正在统计本机数据…'
                          : '当前本机：${summary.peopleCount} 人名单'
                                '${summary.historyCount > 0 ? '、${summary.historyCount} 条考勤记录' : ''}'
                                '${summary.hasSchedule ? '、已同步课程表' : ''}',
                      style: TextStyle(fontSize: 12, color: scheme.primary),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _export,
                        icon: const Icon(Icons.save_alt_rounded),
                        label: const Text('导出为文件'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '从备份还原',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择之前导出的备份文件，本机的名单、考勤状态、历史记录和扩展字段'
                      '将被备份内容覆盖。',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '还原前建议先导出一份当前数据，避免误操作。',
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _import,
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('选择备份文件'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
