import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/app_user.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/services/push_notifications.dart';
import '../jobs/job_detail_screen.dart';

/// Wraps a signed-in user's home screen: registers the device for push,
/// opens the job detail page when a notification is tapped, and shows
/// notifications that arrive while the app is open.
class NotificationHost extends StatefulWidget {
  const NotificationHost({
    required this.push,
    required this.repository,
    required this.uid,
    required this.name,
    required this.role,
    required this.child,
    super.key,
  });

  final PushNotifications push;
  final MarketplaceRepository repository;
  final String uid;
  final String name;
  final UserRole role;
  final Widget child;

  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost> {
  final _subscriptions = <StreamSubscription<Object>>[];

  @override
  void initState() {
    super.initState();
    // Silent: only saves a token if permission was granted before.
    widget.push.registerDevice(widget.uid);
    _subscriptions
      ..add(widget.push.openedJobIds.listen(_openJob))
      ..add(widget.push.foregroundNotices.listen(_showNotice));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await widget.push.takeInitialJobId();
      if (initial != null) _openJob(initial);
    });
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _openJob(String requestId) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobDetailScreen(
          requestId: requestId,
          viewerUid: widget.uid,
          viewerName: widget.name,
          viewerRole: widget.role,
          repository: widget.repository,
        ),
      ),
    );
  }

  void _showNotice(ForegroundNotice notice) {
    if (!mounted) return;
    final requestId = notice.requestId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notice.body.isEmpty
              ? notice.title
              : '${notice.title}: ${notice.body}',
        ),
        action: requestId == null
            ? null
            : SnackBarAction(
                label: 'View',
                onPressed: () => _openJob(requestId),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
