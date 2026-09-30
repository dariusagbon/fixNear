import 'package:flutter/material.dart';

import '../../core/models/app_user.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/status_chip.dart';
import 'customer_job_card.dart';
import 'provider_job_card.dart';

/// One job with its progress and the viewer's actions. Notification taps
/// open this page.
class JobDetailScreen extends StatelessWidget {
  const JobDetailScreen({
    required this.requestId,
    required this.viewerUid,
    required this.viewerName,
    required this.viewerRole,
    required this.repository,
    super.key,
  });

  final String requestId;
  final String viewerUid;
  final String viewerName;
  final UserRole viewerRole;
  final MarketplaceRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Job details')),
      body: SafeArea(
        child: StreamBuilder<ServiceRequest?>(
          stream: repository.watchRequest(requestId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _Message(
                icon: Icons.cloud_off_outlined,
                text: 'Could not load this job. It may no longer be available to you, or you may be offline.',
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final request = snapshot.data;
            if (request == null) {
              return const _Message(
                icon: Icons.search_off_rounded,
                text: 'This job no longer exists.',
              );
            }
            return ContentWidth(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  switch (viewerRole) {
                    UserRole.customer => CustomerRequestCard(
                      request: request,
                      actions: CustomerJobActions(
                        repository: repository,
                        customerUid: viewerUid,
                        customerName: viewerName,
                      ),
                    ),
                    UserRole.provider => ProviderJobCard(
                      request: request,
                      actions: ProviderJobActions(
                        repository: repository,
                        providerUid: viewerUid,
                        providerName: viewerName,
                      ),
                    ),
                  },
                  const SizedBox(height: 16),
                  _Progress(request: request),
                  if (request.locationLabel != null &&
                      request.locationLabel!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(request.locationLabel!),
                        subtitle: Text(request.serviceArea),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The job's status steps, with the current one highlighted.
class _Progress extends StatelessWidget {
  const _Progress({required this.request});

  final ServiceRequest request;

  static const _steps = [
    RequestStatus.requested,
    RequestStatus.quoted,
    RequestStatus.accepted,
    RequestStatus.onTheWay,
    RequestStatus.arrived,
    RequestStatus.inProgress,
    RequestStatus.providerCompleted,
    RequestStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (request.status == RequestStatus.cancelled) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cancel_outlined),
          title: Text('This request was cancelled.'),
        ),
      );
    }
    final current = _steps.indexOf(request.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < _steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      i < current
                          ? Icons.check_circle_rounded
                          : i == current
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: i <= current ? AppTheme.ink : AppTheme.fieldBorder,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        requestStatusLabel(_steps[i]),
                        style: i == current
                            ? textTheme.bodyMedium?.copyWith(
                                color: AppTheme.ink,
                                fontWeight: FontWeight.w700,
                              )
                            : textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            if (request.paymentStatus != 'unpaid') ...[
              const Divider(height: 24),
              Text(
                request.paymentStatus == 'paid' ? 'Cash payment confirmed' : 'Cash payment recorded, waiting for the provider to confirm',
                style: textTheme.bodyMedium?.copyWith(color: AppTheme.ink),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppTheme.inkMuted),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
