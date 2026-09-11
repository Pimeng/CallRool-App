import 'package:flutter/material.dart';

import '../models/attendance_copy_template.dart';

class CopyFormatPageResult {
  const CopyFormatPageResult.save(this.template) : reset = false;
  const CopyFormatPageResult.reset() : template = null, reset = true;

  final String? template;
  final bool reset;
}

class CopyFormatPage extends StatefulWidget {
  const CopyFormatPage({
    super.key,
    required this.initialTemplate,
    required this.previewValues,
    required this.usesCustomTemplate,
  });

  final String initialTemplate;
  final Map<String, String> previewValues;
  final bool usesCustomTemplate;

  @override
  State<CopyFormatPage> createState() => _CopyFormatPageState();
}

class _CopyFormatPageState extends State<CopyFormatPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  final _editorKey = GlobalKey();

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

  void _insertVariable(String token, {TextSelection? targetSelection}) {
    final selection = targetSelection ?? _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    _focusNode.requestFocus();
  }

  void _insertVariableAtDrop(DragTargetDetails<String> details) {
    final editableText = _findEditableTextState();
    final position = editableText?.renderEditable.getPositionForPoint(
      details.offset,
    );
    _insertVariable(
      details.data,
      targetSelection: position == null
          ? null
          : TextSelection.collapsed(offset: position.offset),
    );
  }

  EditableTextState? _findEditableTextState() {
    final editorContext = _editorKey.currentContext;
    if (editorContext == null) return null;
    EditableTextState? result;
    void visit(Element element) {
      if (result != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        result = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    editorContext.visitChildElements(visit);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final preview = AttendanceCopyTemplate.render(
      _controller.text,
      widget.previewValues,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('自定义复制格式')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '点击变量可插入光标位置，也可拖到编辑框中的指定位置。',
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
                          dragAnchorStrategy: pointerDragAnchorStrategy,
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
                    onAcceptWithDetails: _insertVariableAtDrop,
                    builder: (context, candidateData, rejectedData) =>
                        AnimatedContainer(
                          key: _editorKey,
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
                            minLines: 8,
                            maxLines: 14,
                            decoration: const InputDecoration(
                              labelText: '复制格式',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(height: 18),
                  Text('预览', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
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
        ),
      ),
      bottomNavigationBar: SafeArea(
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
            child: Row(
              children: [
                if (widget.usesCustomTemplate) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const CopyFormatPageResult.reset(),
                      ),
                      child: const Text('恢复默认'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _controller.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            CopyFormatPageResult.save(_controller.text),
                          ),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
