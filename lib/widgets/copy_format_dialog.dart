import 'package:flutter/material.dart';

import '../models/attendance_copy_template.dart';

class CopyFormatDialogResult {
  const CopyFormatDialogResult.save(this.template) : reset = false;
  const CopyFormatDialogResult.reset() : template = null, reset = true;

  final String? template;
  final bool reset;
}

class CopyFormatDialog extends StatefulWidget {
  const CopyFormatDialog({
    super.key,
    required this.initialTemplate,
    required this.previewValues,
    required this.usesCustomTemplate,
  });

  final String initialTemplate;
  final Map<String, String> previewValues;
  final bool usesCustomTemplate;

  @override
  State<CopyFormatDialog> createState() => _CopyFormatDialogState();
}

class _CopyFormatDialogState extends State<CopyFormatDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTemplate)
      ..addListener(_handleChanged);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged() => setState(() {});

  void _insertVariable(String token) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final preview = AttendanceCopyTemplate.render(
      _controller.text,
      widget.previewValues,
    );
    return AlertDialog(
      title: const Text('自定义复制格式'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '点击变量，或将变量拖到编辑框后插入光标位置。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final variable in AttendanceCopyTemplate.variables)
                    Draggable<String>(
                      data: variable.token,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Chip(label: Text(variable.name)),
                      ),
                      childWhenDragging: Opacity(
                        opacity: .45,
                        child: ActionChip(
                          label: Text(variable.name),
                          onPressed: () => _insertVariable(variable.token),
                        ),
                      ),
                      child: Tooltip(
                        message: variable.description,
                        child: ActionChip(
                          label: Text(variable.name),
                          onPressed: () => _insertVariable(variable.token),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              DragTarget<String>(
                onAcceptWithDetails: (details) => _insertVariable(details.data),
                builder: (context, candidateData, rejectedData) =>
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          width: candidateData.isEmpty ? 0 : 2,
                          color: candidateData.isEmpty
                              ? Colors.transparent
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      child: TextField(
                        key: const ValueKey('copy-format-editor'),
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 6,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          labelText: '复制格式',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
              ),
              const SizedBox(height: 14),
              Text('预览', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  preview.isEmpty ? '复制内容不能为空' : preview,
                  key: const ValueKey('copy-format-preview'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.usesCustomTemplate)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const CopyFormatDialogResult.reset()),
            child: const Text('恢复默认'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  CopyFormatDialogResult.save(_controller.text),
                ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
