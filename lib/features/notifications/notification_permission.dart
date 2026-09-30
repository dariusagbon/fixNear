import 'package:flutter/material.dart';

import '../../core/services/push_notifications.dart';

/// Asks for notification permission at a moment when it's obviously useful
/// (first job posted, first time going online), with a short explanation
/// before the system prompt. Does nothing if the device was already asked.
Future<void> askForNotificationsIfUseful({
  required BuildContext context,
  required PushNotifications push,
  required String uid,
  required String title,
  required String reason,
}) async {
  if (!await push.canAskPermission() || !context.mounted) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: Text(title),
      content: Text(reason),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  if (accepted != true) return;
  if (await push.requestPermission()) {
    await push.registerDevice(uid);
  }
}
