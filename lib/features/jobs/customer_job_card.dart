import 'package:flutter/material.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/attention.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/job_photos.dart';
import '../../core/widgets/status_chip.dart';
import '../messaging/job_chat_sheet.dart';

/// Everything a customer can do to one of their jobs, with user feedback.
/// Shared by the requests list and the job detail page.
class CustomerJobActions {
  const CustomerJobActions({
    required this.repository,
    required this.customerUid,
    required this.customerName,
  });

  final MarketplaceRepository repository;
  final String customerUid;
  final String customerName;

  Future<void> acceptQuote(
    BuildContext context,
    ServiceRequest request,
    ProviderQuote quote,
  ) => runWithFeedback(
    context,
    () => repository.acceptQuote(request.id, quote),
    failureMessage: 'Could not accept this quote.',
    successMessage: 'Quote accepted.',
  );

  Future<void> cancel(BuildContext context, ServiceRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text(
          'Providers will no longer see your ${request.category.toLowerCase()} request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runWithFeedback(
      context,
      () => repository.cancelRequest(request.id),
      failureMessage: 'Could not cancel this request.',
      successMessage: 'Request cancelled.',
    );
  }

  Future<void> confirmCompletion(
    BuildContext context,
    ServiceRequest request,
  ) => runWithFeedback(
    context,
    () => repository.confirmCompletion(request.id, customerUid),
    failureMessage: 'Could not confirm completion.',
  );

  Future<void> payCash(BuildContext context, ServiceRequest request) =>
      runWithFeedback(
        context,
        () => repository.recordCashPayment(request.id, customerUid),
        failureMessage: 'Could not record cash payment.',
      );

  Future<void> openChat(BuildContext context, ServiceRequest request) =>
      showJobChatSheet(
        context: context,
        requestId: request.id,
        currentUid: customerUid,
        currentName: customerName,
        repository: repository,
      );
}

/// A customer's view of one of their jobs, with the actions that apply to
/// its current status.
class CustomerRequestCard extends StatelessWidget {
  const CustomerRequestCard({
    required this.request,
    required this.actions,
    this.onOpenDetails,
    super.key,
  });

  final ServiceRequest request;
  final CustomerJobActions actions;

  /// Opens the job detail page. Hidden when null (e.g. on that page).
  final VoidCallback? onOpenDetails;

  bool get _isOpen =>
      request.status == RequestStatus.requested ||
      request.status == RequestStatus.quoted;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.category,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusChip(
                  status: request.status,
                  needsYou: customerNeedsToAct(request),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(request.description),
            const SizedBox(height: 6),
            Text('Area: ${request.serviceArea}'),
            if (request.scheduledAt != null)
              Text('Scheduled: ${formatDateTime(request.scheduledAt!)}'),
            if (request.providerName != null)
              Text('Provider: ${request.providerName}'),
            if (request.quotedPrice != null)
              Text('Agreed quote: ${formatPeso(request.quotedPrice!)}'),
            JobPhotoStrip(urls: request.photoUrls),
            if (_isOpen)
              _QuoteList(
                quotes: actions.repository.watchQuotes(request.id),
                onAccept: (quote) =>
                    actions.acceptQuote(context, request, quote),
              ),
            if (request.paymentStatus == 'pending_provider_confirmation')
              const _CardNote(
                icon: Icons.hourglass_empty_rounded,
                text: 'Cash payment awaiting provider confirmation.',
              ),
            if (request.paymentStatus == 'paid')
              const _CardNote(
                icon: Icons.check_circle_outline_rounded,
                text: 'Payment confirmed.',
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onOpenDetails != null)
                  TextButton(
                    onPressed: onOpenDetails,
                    child: const Text('Details'),
                  ),
                if (request.providerUid != null &&
                    request.status != RequestStatus.cancelled)
                  TextButton.icon(
                    onPressed: () => actions.openChat(context, request),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Chat'),
                  ),
                if (_isOpen)
                  TextButton.icon(
                    onPressed: () => actions.cancel(context, request),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel request'),
                  ),
                if (request.status == RequestStatus.providerCompleted)
                  FilledButton(
                    onPressed: () =>
                        actions.confirmCompletion(context, request),
                    child: const Text('Confirm completion'),
                  ),
                if (request.status == RequestStatus.completed &&
                    request.paymentStatus == 'unpaid')
                  FilledButton.icon(
                    onPressed: () => actions.payCash(context, request),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Pay cash'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteList extends StatelessWidget {
  const _QuoteList({required this.quotes, required this.onAccept});

  final Stream<List<ProviderQuote>> quotes;
  final void Function(ProviderQuote quote) onAccept;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProviderQuote>>(
      stream: quotes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _CardNote(
            icon: Icons.cloud_off_outlined,
            text: 'Could not load quotes. Check your connection.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          );
        }
        final available = snapshot.data ?? const <ProviderQuote>[];
        if (available.isEmpty) {
          return const _CardNote(
            icon: Icons.hourglass_empty_rounded,
            text: 'Waiting for providers to send quotes.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              'Provider quotes',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final quote in available)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${quote.providerName} · ${formatPeso(quote.price)}',
                ),
                subtitle: Text(quote.note),
                trailing: FilledButton(
                  onPressed: () => onAccept(quote),
                  child: const Text('Accept'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A small icon-and-text line inside a card, for inline states.
class _CardNote extends StatelessWidget {
  const _CardNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
