import 'package:flutter/material.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/attention.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/job_photos.dart';
import '../../core/widgets/reason_dialog.dart';
import '../../core/widgets/status_chip.dart';
import '../messaging/job_chat_sheet.dart';

/// Everything a provider can do to a job, with user feedback. Shared by the
/// job board, "My jobs" and the job detail page.
class ProviderJobActions {
  const ProviderJobActions({
    required this.repository,
    required this.providerUid,
    required this.providerName,
  });

  final MarketplaceRepository repository;
  final String providerUid;
  final String providerName;

  /// The next status this provider can move [request] to, if any.
  static String? nextStatus(ServiceRequest request) => switch (request.status) {
    RequestStatus.accepted => RequestStatus.onTheWay,
    RequestStatus.onTheWay => RequestStatus.arrived,
    RequestStatus.arrived => RequestStatus.inProgress,
    RequestStatus.inProgress => RequestStatus.providerCompleted,
    _ => null,
  };

  static String? nextStatusLabel(ServiceRequest request) =>
      switch (request.status) {
        RequestStatus.accepted => 'On the way',
        RequestStatus.onTheWay => 'Mark arrived',
        RequestStatus.arrived => 'Start job',
        RequestStatus.inProgress => 'Mark provider complete',
        _ => null,
      };

  Future<void> sendQuote(BuildContext context, ServiceRequest request) async {
    final quote = await showDialog<_QuoteSubmission>(
      context: context,
      builder: (_) => const _QuoteDialog(),
    );
    if (quote == null || !context.mounted) return;
    await runWithFeedback(
      context,
      () => repository.sendQuote(
        requestId: request.id,
        providerUid: providerUid,
        providerName: providerName,
        price: quote.price,
        note: quote.note,
      ),
      failureMessage: 'Could not send the quote.',
      successMessage: 'Quote sent.',
    );
  }

  Future<void> decline(BuildContext context, ServiceRequest request) =>
      runWithFeedback(
        context,
        () => repository.declineRequest(request.id, providerUid),
        failureMessage: 'Could not decline the request.',
        successMessage: request.providerUid == providerUid
            ? 'Declined. The job is now open to other providers.'
            : null,
      );

  Future<void> withdraw(BuildContext context, ServiceRequest request) async {
    final reason = await showReasonDialog(
      context,
      title: "Can't make it?",
      message:
          '${request.customerName} will be told, and the job reopens for other providers to quote.',
      confirmLabel: 'Withdraw',
      dismissLabel: 'Keep job',
    );
    if (reason == null || !context.mounted) return;
    await runWithFeedback(
      context,
      () => repository.withdrawFromJob(
        request.id,
        providerUid,
        reason: reason.isEmpty ? null : reason,
      ),
      failureMessage: 'Could not withdraw from this job.',
      successMessage: 'You withdrew from the job.',
    );
  }

  Future<void> advance(BuildContext context, ServiceRequest request) {
    final next = nextStatus(request);
    if (next == null) return Future.value();
    return runWithFeedback(
      context,
      () => repository.advanceRequest(request.id, next),
      failureMessage: 'Could not update the request.',
    );
  }

  Future<void> confirmCash(BuildContext context, ServiceRequest request) =>
      runWithFeedback(
        context,
        () => repository.confirmCashPayment(request.id, providerUid),
        failureMessage: 'Could not confirm payment.',
      );

  Future<void> openChat(BuildContext context, ServiceRequest request) =>
      showJobChatSheet(
        context: context,
        requestId: request.id,
        currentUid: providerUid,
        currentName: providerName,
        repository: repository,
      );
}

/// A provider's view of a job: an open request on the board, or one of
/// their booked jobs.
class ProviderJobCard extends StatelessWidget {
  const ProviderJobCard({
    required this.request,
    required this.actions,
    this.onOpenDetails,
    this.distanceLabel,
    super.key,
  });

  final ServiceRequest request;
  final ProviderJobActions actions;
  final VoidCallback? onOpenDetails;

  /// For example "2.3 km away". Shown on the job board.
  final String? distanceLabel;

  bool get _isAssigned =>
      request.providerUid == actions.providerUid &&
      request.status != RequestStatus.requested &&
      request.status != RequestStatus.quoted;

  bool get _isOpen =>
      request.status == RequestStatus.requested ||
      request.status == RequestStatus.quoted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nextLabel = _isAssigned
        ? ProviderJobActions.nextStatusLabel(request)
        : null;
    final sentToMe = _isOpen && request.providerUid == actions.providerUid;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(request.category, style: textTheme.titleMedium),
                ),
                StatusChip(
                  status: request.status,
                  needsYou: providerNeedsToAct(request, actions.providerUid),
                ),
              ],
            ),
            if (sentToMe)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Sent directly to you',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(request.description),
            JobPhotoStrip(urls: request.photoUrls),
            const SizedBox(height: 8),
            Text(
              _isAssigned
                  ? '${request.serviceArea} · ${request.customerName}'
                  : '${request.serviceArea} · Requested by ${request.customerName}',
              style: textTheme.bodySmall,
            ),
            if (distanceLabel != null)
              Text(
                distanceLabel!,
                style: textTheme.bodySmall?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (request.scheduledAt != null)
              Text(
                'Scheduled: ${formatDateTime(request.scheduledAt!)}',
                style: textTheme.bodySmall,
              ),
            if (request.quotedPrice != null)
              Text('Agreed quote: ${formatPeso(request.quotedPrice!)}'),
            if (request.status == RequestStatus.cancelled)
              Text(
                request.cancelReason == null
                    ? 'The customer cancelled this job.'
                    : 'The customer cancelled: ${request.cancelReason}',
                style: textTheme.bodySmall,
              ),
            if (request.paymentStatus == 'paid')
              Text(
                'Payment received',
                style: textTheme.bodySmall?.copyWith(
                  color: AppTheme.success,
                  fontWeight: FontWeight.w600,
                ),
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
                if (_isAssigned && request.status != RequestStatus.cancelled)
                  TextButton.icon(
                    onPressed: () => actions.openChat(context, request),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Chat'),
                  ),
                if (_isOpen)
                  TextButton(
                    onPressed: () => actions.decline(context, request),
                    child: const Text('Decline'),
                  ),
                if (_isOpen)
                  FilledButton(
                    onPressed: () => actions.sendQuote(context, request),
                    child: const Text('Send quote'),
                  ),
                if (_isAssigned &&
                    (request.status == RequestStatus.accepted ||
                        request.status == RequestStatus.onTheWay))
                  TextButton(
                    onPressed: () => actions.withdraw(context, request),
                    child: const Text("Can't make it"),
                  ),
                if (nextLabel != null)
                  FilledButton(
                    onPressed: () => actions.advance(context, request),
                    child: Text(nextLabel),
                  ),
                if (request.status == RequestStatus.completed &&
                    request.paymentStatus == 'pending_provider_confirmation')
                  FilledButton.icon(
                    onPressed: () => actions.confirmCash(context, request),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Confirm cash received'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteSubmission {
  const _QuoteSubmission(this.price, this.note);

  final int price;
  final String note;
}

class _QuoteDialog extends StatefulWidget {
  const _QuoteDialog();

  @override
  State<_QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<_QuoteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _priceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send quote'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price (PHP)'),
              validator: (value) {
                final price = int.tryParse(value?.trim() ?? '');
                return price == null || price < 1
                    ? 'Enter a valid price'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message to customer',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Add a short note'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _QuoteSubmission(
                int.parse(_priceController.text.trim()),
                _noteController.text.trim(),
              ),
            );
          },
          child: const Text('Send quote'),
        ),
      ],
    );
  }
}
