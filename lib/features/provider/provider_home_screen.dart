import 'package:flutter/material.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/services/marketplace_service.dart';
import '../messaging/job_chat_sheet.dart';

class ProviderHomeScreen extends StatelessWidget {
  const ProviderHomeScreen({
    required this.providerUid,
    required this.providerName,
    required this.repository,
    this.onSignOut,
    super.key,
  });

  final String providerUid;
  final String providerName;
  final MarketplaceRepository repository;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Provider workspace'),
          actions: [
            if (onSignOut != null)
              IconButton(
                tooltip: 'Sign out',
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_rounded),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Open requests'),
              Tab(text: 'My jobs'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RequestList(
              requests: repository.watchOpenRequests(providerUid),
              emptyMessage: 'No open requests nearby yet.',
              actionLabel: 'Send quote',
              onAction: (request) async {
                final quote = await showDialog<_QuoteSubmission>(
                  context: context,
                  builder: (_) => const _QuoteDialog(),
                );
                if (quote == null) return;
                await repository.sendQuote(
                  requestId: request.id,
                  providerUid: providerUid,
                  providerName: providerName,
                  price: quote.price,
                  note: quote.note,
                );
              },
              onDecline: (request) =>
                  repository.declineRequest(request.id, providerUid),
            ),
            _RequestList(
              requests: repository.watchProviderJobs(providerUid),
              emptyMessage: 'Accepted jobs will appear here.',
              actionLabel: null,
              onAction: (request) {
                final nextStatus = switch (request.status) {
                  RequestStatus.accepted => RequestStatus.onTheWay,
                  RequestStatus.onTheWay => RequestStatus.arrived,
                  RequestStatus.arrived => RequestStatus.inProgress,
                  RequestStatus.inProgress => RequestStatus.providerCompleted,
                  _ => null,
                };
                if (nextStatus == null) return Future.value();
                return repository.advanceRequest(request.id, nextStatus);
              },
              onOpenChat: (request) => showJobChatSheet(
                context: context,
                requestId: request.id,
                currentUid: providerUid,
                currentName: providerName,
                repository: repository,
              ),
              onConfirmCashPayment: (request) =>
                  repository.confirmCashPayment(request.id, providerUid),
              showProgressActions: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({
    required this.requests,
    required this.emptyMessage,
    required this.actionLabel,
    required this.onAction,
    this.onDecline,
    this.onOpenChat,
    this.onConfirmCashPayment,
    this.showProgressActions = false,
  });

  final Stream<List<ServiceRequest>> requests;
  final String emptyMessage;
  final String? actionLabel;
  final Future<void> Function(ServiceRequest request) onAction;
  final Future<void> Function(ServiceRequest request)? onDecline;
  final Future<void> Function(ServiceRequest request)? onOpenChat;
  final Future<void> Function(ServiceRequest request)? onConfirmCashPayment;
  final bool showProgressActions;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ServiceRequest>>(
      stream: requests,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load requests.'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? const <ServiceRequest>[];
        if (items.isEmpty && !showProgressActions) {
          return Center(child: Text(emptyMessage));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length + (showProgressActions ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (showProgressActions && index == 0) {
              final earnings = items
                  .where(
                    (request) =>
                        request.status == RequestStatus.completed &&
                        request.paymentStatus == 'paid',
                  )
                  .fold<int>(
                    0,
                    (sum, request) => sum + (request.quotedPrice ?? 0),
                  );
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Confirmed earnings'),
                  trailing: Text('₱$earnings'),
                ),
              );
            }
            if (items.isEmpty) return Center(child: Text(emptyMessage));
            final request = items[index - (showProgressActions ? 1 : 0)];
            final progressLabel = switch (request.status) {
              RequestStatus.accepted => 'On the way',
              RequestStatus.onTheWay => 'Mark arrived',
              RequestStatus.arrived => 'Start job',
              RequestStatus.inProgress => 'Mark provider complete',
              _ => null,
            };
            final label = showProgressActions ? progressLabel : actionLabel;

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
                        _StatusLabel(status: request.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(request.description),
                    const SizedBox(height: 8),
                    Text(
                      '${request.serviceArea} · ${showProgressActions ? request.customerName : 'Requested by ${request.customerName}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (request.quotedPrice != null)
                      Text('Agreed quote: ₱${request.quotedPrice}'),
                    if (onOpenChat != null &&
                        request.status != RequestStatus.requested &&
                        request.status != RequestStatus.quoted)
                      TextButton.icon(
                        onPressed: () => onOpenChat!(request),
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('Chat'),
                      ),
                    if (request.status == RequestStatus.completed &&
                        request.paymentStatus ==
                            'pending_provider_confirmation' &&
                        onConfirmCashPayment != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () =>
                              _runPaymentConfirmation(context, request),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Confirm cash received'),
                        ),
                      ),
                    if (label != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (onDecline != null)
                            TextButton(
                              onPressed: () => _runDecline(context, request),
                              child: const Text('Decline'),
                            ),
                          FilledButton(
                            onPressed: () => _runAction(context, request),
                            child: Text(label),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _runAction(BuildContext context, ServiceRequest request) async {
    try {
      await onAction(request);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the request: $error')),
      );
    }
  }

  Future<void> _runDecline(BuildContext context, ServiceRequest request) async {
    try {
      await onDecline!(request);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not decline the request: $error')),
      );
    }
  }

  Future<void> _runPaymentConfirmation(
    BuildContext context,
    ServiceRequest request,
  ) async {
    try {
      await onConfirmCashPayment!(request);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not confirm payment: $error')),
      );
    }
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      RequestStatus.quoted => 'Quotes received',
      RequestStatus.onTheWay => 'On the way',
      RequestStatus.inProgress => 'In progress',
      RequestStatus.providerCompleted => 'Awaiting confirmation',
      RequestStatus.completed => 'Completed',
      RequestStatus.cancelled => 'Cancelled',
      _ => status[0].toUpperCase() + status.substring(1),
    };
    return Chip(label: Text(label));
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
