import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/status_chip.dart';
import '../messaging/job_chat_sheet.dart';

class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({
    required this.providerUid,
    required this.providerName,
    required this.repository,
    this.photoUrl,
    this.onSignOut,
    this.onUpdateProfilePhoto,
    super.key,
  });

  final String providerUid;
  final String providerName;
  final String? photoUrl;
  final MarketplaceRepository repository;
  final Future<void> Function()? onSignOut;
  final Future<String> Function(Uint8List bytes, String fileName)?
  onUpdateProfilePhoto;

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> {
  Future<void> _uploadProfilePhoto() async {
    if (widget.onUpdateProfilePhoto == null) return;

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      final bytes = await image.readAsBytes();
      await widget.onUpdateProfilePhoto!(bytes, image.name);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update your profile photo. ${error.toString()}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              if (widget.photoUrl != null) ...[
                CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(widget.photoUrl!),
                ),
                const SizedBox(width: 10),
              ],
              Text(widget.providerName),
            ],
          ),
          actions: [
            if (widget.onUpdateProfilePhoto != null)
              IconButton(
                tooltip: 'Update profile photo',
                onPressed: _uploadProfilePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
              ),
            if (widget.onSignOut != null)
              IconButton(
                tooltip: 'Sign out',
                onPressed: widget.onSignOut,
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
              requests: widget.repository.watchOpenRequests(widget.providerUid),
              emptyMessage: 'No open requests nearby yet.',
              actionLabel: 'Send quote',
              onAction: (request) async {
                final quote = await showDialog<_QuoteSubmission>(
                  context: context,
                  builder: (_) => const _QuoteDialog(),
                );
                if (quote == null) return;
                await widget.repository.sendQuote(
                  requestId: request.id,
                  providerUid: widget.providerUid,
                  providerName: widget.providerName,
                  price: quote.price,
                  note: quote.note,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Quote sent.')));
              },
              onDecline: (request) =>
                  widget.repository.declineRequest(request.id, widget.providerUid),
            ),
            _RequestList(
              requests: widget.repository.watchProviderJobs(widget.providerUid),
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
                return widget.repository.advanceRequest(request.id, nextStatus);
              },
              onOpenChat: (request) => showJobChatSheet(
                context: context,
                requestId: request.id,
                currentUid: widget.providerUid,
                currentName: widget.providerName,
                repository: widget.repository,
              ),
              onConfirmCashPayment: (request) =>
                  widget.repository.confirmCashPayment(request.id, widget.providerUid),
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
          return const _EmptyState(
            icon: Icons.cloud_off_outlined,
            message: 'Could not load requests. Check your connection.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? const <ServiceRequest>[];
        if (items.isEmpty && !showProgressActions) {
          return _EmptyState(icon: Icons.inbox_outlined, message: emptyMessage);
        }

        return ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (showProgressActions) ...[
                _EarningsCard(jobs: items),
                const SizedBox(height: 12),
              ],
              if (items.isEmpty)
                _EmptyState(icon: Icons.work_outline, message: emptyMessage),
              for (final request in items) ...[
                _buildRequestCard(context, request),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRequestCard(BuildContext context, ServiceRequest request) {
    final progressLabel = switch (request.status) {
      RequestStatus.accepted => 'On the way',
      RequestStatus.onTheWay => 'Mark arrived',
      RequestStatus.arrived => 'Start job',
      RequestStatus.inProgress => 'Mark provider complete',
      _ => null,
    };
    final label = showProgressActions ? progressLabel : actionLabel;
    final textTheme = Theme.of(context).textTheme;

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
                StatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(request.description),
            const SizedBox(height: 8),
            Text(
              '${request.serviceArea} · ${showProgressActions ? request.customerName : 'Requested by ${request.customerName}'}',
              style: textTheme.bodySmall,
            ),
            if (request.scheduledAt != null)
              Text(
                'Scheduled: ${formatDateTime(request.scheduledAt!)}',
                style: textTheme.bodySmall,
              ),
            if (request.quotedPrice != null)
              Text('Agreed quote: ${formatPeso(request.quotedPrice!)}'),
            if (onOpenChat != null &&
                request.status != RequestStatus.requested &&
                request.status != RequestStatus.quoted)
              TextButton.icon(
                onPressed: () => onOpenChat!(request),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Chat'),
              ),
            if (request.status == RequestStatus.completed &&
                request.paymentStatus == 'pending_provider_confirmation' &&
                onConfirmCashPayment != null)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _runPaymentConfirmation(context, request),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Confirm cash received'),
                ),
              ),
            if (request.paymentStatus == 'paid')
              Text(
                'Payment received',
                style: textTheme.bodySmall?.copyWith(
                  color: AppTheme.successGreen,
                  fontWeight: FontWeight.w600,
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
                  const SizedBox(width: 8),
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
  }

  Future<void> _runAction(BuildContext context, ServiceRequest request) async {
    try {
      await onAction(request);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not update the request.'),
          ),
        ),
      );
    }
  }

  Future<void> _runDecline(BuildContext context, ServiceRequest request) async {
    try {
      await onDecline!(request);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not decline the request.'),
          ),
        ),
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
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not confirm payment.'),
          ),
        ),
      );
    }
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.jobs});

  final List<ServiceRequest> jobs;

  @override
  Widget build(BuildContext context) {
    final paidJobs = jobs.where(
      (request) =>
          request.status == RequestStatus.completed &&
          request.paymentStatus == 'paid',
    );
    final earnings = paidJobs.fold<int>(
      0,
      (sum, request) => sum + (request.quotedPrice ?? 0),
    );
    final activeJobs = jobs
        .where(
          (request) =>
              request.status != RequestStatus.completed &&
              request.status != RequestStatus.cancelled,
        )
        .length;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: const Text('Confirmed earnings'),
        subtitle: Text('${paidJobs.length} paid · $activeJobs active'),
        trailing: Text(
          formatPeso(earnings),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppTheme.textSecondary),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
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
