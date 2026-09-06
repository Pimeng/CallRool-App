import 'package:flutter/material.dart';

class WakeUpScheduleCredentials {
  const WakeUpScheduleCredentials({
    required this.authToken,
    required this.shareCode,
  });

  final String authToken;
  final String shareCode;
}

class WakeUpScheduleDialog extends StatefulWidget {
  const WakeUpScheduleDialog({
    super.key,
    required this.initialAuthToken,
    this.currentScheduleLabel,
  });

  final String initialAuthToken;
  final String? currentScheduleLabel;

  @override
  State<WakeUpScheduleDialog> createState() => _WakeUpScheduleDialogState();
}

class _WakeUpScheduleDialogState extends State<WakeUpScheduleDialog> {
  late final TextEditingController _authTokenController;
  final _shareCodeController = TextEditingController();
  bool _hideToken = true;

  bool get _canSubmit =>
      _authTokenController.text.trim().isNotEmpty &&
      _shareCodeController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _authTokenController = TextEditingController(text: widget.initialAuthToken);
  }

  @override
  void dispose() {
    _authTokenController.dispose();
    _shareCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      title: const Text('同步 WakeUp 课程表'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.currentScheduleLabel != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.currentScheduleLabel!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _authTokenController,
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
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _shareCodeController,
              autofocus: widget.initialAuthToken.isNotEmpty,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'shareCode',
                helperText: '每次同步手动填写，不会保存',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: const Icon(Icons.sync_rounded),
          label: const Text('同步'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(
      context,
      WakeUpScheduleCredentials(
        authToken: _authTokenController.text.trim(),
        shareCode: _shareCodeController.text.trim(),
      ),
    );
  }
}
