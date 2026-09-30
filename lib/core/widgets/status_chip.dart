import 'package:flutter/material.dart';

import '../models/marketplace_models.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// A compact pill describing a service request's status.
///
/// When [needsYou] is true the chip turns yellow, the one place the app uses
/// [AppTheme.attention]: the job is waiting on the person looking at it.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, this.needsYou = false, super.key});

  final String status;
  final bool needsYou;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = needsYou
        ? (AppTheme.attention, AppTheme.ink)
        : switch (status) {
            RequestStatus.completed => (AppTheme.successTint, AppTheme.success),
            RequestStatus.cancelled => (AppTheme.tint, AppTheme.inkMuted),
            _ => (AppTheme.tint, AppTheme.ink),
          };
    final label = requestStatusLabel(status);
    return Semantics(
      label: needsYou ? '$label, needs your action' : label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (needsYou) ...[
              Icon(Icons.priority_high_rounded, size: 14, color: foreground),
              const SizedBox(width: 2),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centers [child] and caps its width so screens stay readable on wide
/// browser windows and tablets.
class ContentWidth extends StatelessWidget {
  const ContentWidth({required this.child, this.maxWidth = 720, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
