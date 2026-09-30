import 'package:flutter/material.dart';

/// Confirms a destructive action and collects an optional short reason.
/// Returns null when dismissed, or the (possibly empty) trimmed reason.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String dismissLabel,
  String reasonLabel = 'Reason (optional)',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ReasonDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      dismissLabel: dismissLabel,
      reasonLabel: reasonLabel,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.dismissLabel,
    required this.reasonLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String dismissLabel;
  final String reasonLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLength: 200,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(labelText: widget.reasonLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.dismissLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
