import 'package:flutter/material.dart';

import '../models/person.dart';

/// 「编辑名单」页返回的结果：编辑后的名单与最新的扩展字段定义。
class RosterEditorResult {
  const RosterEditorResult({required this.people, required this.fieldNames});

  final List<Person> people;
  final List<String> fieldNames;
}

/// 编辑某个人：姓名 + 各扩展字段的值。
typedef _PersonDraft = ({String name, Map<String, String> fields});

/// 字段管理里的一个草稿项。[original] 为原有字段名，新增项为 null，
/// 用来在重命名时把旧值迁移到新字段名下。
///
/// [id] 只用于给列表项提供稳定 key：增删字段时 Flutter 会按 key 复用 Element，
/// 否则同一位置的 TextField 会被换上另一个控制器。
class _FieldDraft {
  _FieldDraft({this.original, String name = ''})
    : id = _nextId++,
      controller = TextEditingController(text: name);

  static int _nextId = 0;

  final int id;
  final String? original;
  final TextEditingController controller;

  void dispose() => controller.dispose();
}

/// 名单编辑器：为每个人维护姓名与自定义扩展字段，并管理字段定义本身。
class RosterEditorPage extends StatefulWidget {
  const RosterEditorPage({
    super.key,
    required this.people,
    required this.fieldNames,
  });

  final List<Person> people;
  final List<String> fieldNames;

  @override
  State<RosterEditorPage> createState() => _RosterEditorPageState();
}

class _RosterEditorPageState extends State<RosterEditorPage> {
  late List<Person> _people;
  late List<String> _fieldNames;

  @override
  void initState() {
    super.initState();
    _people = List.of(widget.people);
    _fieldNames = List.of(widget.fieldNames);
  }

  RosterEditorResult _result() => RosterEditorResult(
    people: List.unmodifiable(_people),
    fieldNames: List.unmodifiable(_fieldNames),
  );

  void _close() => Navigator.of(context).pop(_result());

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _addPerson() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NamePromptDialog(
        title: '添加人员',
        confirmLabel: '添加',
        nameLabel: '姓名',
      ),
    );
    if (name == null || !mounted) return;
    if (_people.any((person) => person.name.toLowerCase() == name.toLowerCase())) {
      _toast('名单中已有这个名字');
      return;
    }
    final nextId = _people.isEmpty
        ? 1
        : _people.map((person) => person.id).reduce((a, b) => a > b ? a : b) + 1;
    setState(() => _people.add(Person(id: nextId, name: name)));
  }

  Future<void> _editPerson(Person person) async {
    final draft = await showDialog<_PersonDraft>(
      context: context,
      builder: (_) => _EditPersonDialog(person: person, fieldNames: _fieldNames),
    );
    if (draft == null || !mounted) return;
    if (_people.any(
      (other) =>
          other.id != person.id &&
          other.name.toLowerCase() == draft.name.toLowerCase(),
    )) {
      _toast('名单中已有这个名字');
      return;
    }
    setState(() {
      final index = _people.indexOf(person);
      if (index < 0) return;
      _people[index] = Person(
        id: person.id,
        name: draft.name,
        status: person.status,
        fields: draft.fields,
      );
    });
  }

  Future<void> _deletePerson(Person person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除「${person.name}」？'),
        content: const Text('该人员的扩展字段与当前考勤状态会一并删除。'),
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
    setState(() => _people.remove(person));
  }

  Future<void> _manageFields() async {
    final definitions = await showDialog<List<({String? original, String name})>>(
      context: context,
      builder: (_) => _ManageFieldsDialog(fieldNames: _fieldNames),
    );
    if (definitions == null || !mounted) return;
    final names = normalizePersonFields(
      definitions.map((definition) => definition.name),
    );
    setState(() {
      _fieldNames = names;
      // 按「原字段名 -> 新字段名」的映射迁移每个人的字段值，
      // 这样重命名字段不会丢数据，删除字段也只丢弃对应值。
      _people = [
        for (final person in _people)
          Person(
            id: person.id,
            name: person.name,
            status: person.status,
            fields: {
              for (final definition in definitions)
                if (definition.original != null &&
                    (person.fields[definition.original] ?? '').trim().isNotEmpty)
                  definition.name.trim(): person.fields[definition.original]!,
            },
          ),
      ];
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
          title: const Text('编辑名单'),
          actions: [
            IconButton(
              tooltip: '管理字段',
              onPressed: _manageFields,
              icon: const Icon(Icons.view_column_rounded),
            ),
            IconButton(
              tooltip: '添加人员',
              onPressed: _addPerson,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _people.isEmpty
              ? const Center(child: Text('名单为空，先添加一位成员吧'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  itemCount: _people.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final person = _people[index];
                    final summary = person.fieldSummary;
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(person.name.characters.first),
                        ),
                        title: Text(person.name),
                        subtitle: Text(
                          summary.isEmpty ? '未设置扩展字段' : summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _deletePerson(person),
                        ),
                        onTap: () => _editPerson(person),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// 只输入一个名称的对话框。
///
/// 控制器由对话框自己持有：如果改成在外面创建、`showDialog` 返回后立即
/// `dispose()`，退场动画期间 TextField 还在树上，会抛
/// 「A TextEditingController was used after being disposed」。
class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.confirmLabel,
    required this.nameLabel,
  });

  final String title;
  final String confirmLabel;
  final String nameLabel;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: widget.nameLabel),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty ? null : _submit,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

/// 编辑单个人员的姓名与扩展字段。
class _EditPersonDialog extends StatefulWidget {
  const _EditPersonDialog({required this.person, required this.fieldNames});

  final Person person;
  final List<String> fieldNames;

  @override
  State<_EditPersonDialog> createState() => _EditPersonDialogState();
}

class _EditPersonDialogState extends State<_EditPersonDialog> {
  late final TextEditingController _nameController;
  late final Map<String, TextEditingController> _fieldControllers;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person.name);
    _fieldControllers = {
      for (final name in widget.fieldNames)
        name: TextEditingController(text: widget.person.fields[name] ?? ''),
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (
      name: name,
      fields: {
        for (final entry in _fieldControllers.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑人员'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '姓名'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              for (final name in widget.fieldNames) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _fieldControllers[name],
                  decoration: InputDecoration(labelText: name),
                  textInputAction: TextInputAction.next,
                ),
              ],
              if (widget.fieldNames.isEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '还没有扩展字段，可在右上角「管理字段」中添加。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _nameController.text.trim().isEmpty ? null : _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 管理扩展字段：新增、重命名、删除。
class _ManageFieldsDialog extends StatefulWidget {
  const _ManageFieldsDialog({required this.fieldNames});

  final List<String> fieldNames;

  @override
  State<_ManageFieldsDialog> createState() => _ManageFieldsDialogState();
}

class _ManageFieldsDialogState extends State<_ManageFieldsDialog> {
  late final List<_FieldDraft> _drafts = [
    for (final name in widget.fieldNames) _FieldDraft(original: name, name: name),
  ];
  String? _error;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final names = [for (final draft in _drafts) draft.controller.text.trim()];
    if (names.any((name) => name.isEmpty)) {
      setState(() => _error = '字段名不能为空');
      return;
    }
    if (names.toSet().length != names.length) {
      setState(() => _error = '字段名不能重复');
      return;
    }
    Navigator.pop(context, [
      for (var index = 0; index < _drafts.length; index++)
        (original: _drafts[index].original, name: names[index]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理扩展字段'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '字段可自定义，默认提供「宿舍」「学号」。删除字段会同时删除所有人的该字段值。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < _drafts.length; index++)
                Padding(
                  key: ValueKey(_drafts[index].id),
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _drafts[index].controller,
                          decoration: const InputDecoration(
                            labelText: '字段名',
                          ),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: '删除字段',
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () => setState(() {
                          _drafts.removeAt(index).dispose();
                          _error = null;
                        }),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _drafts.add(_FieldDraft());
                    _error = null;
                  }),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加字段'),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
