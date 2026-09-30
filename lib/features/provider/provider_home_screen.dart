import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/app_user.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/services/location_service.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/services/push_notifications.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/job_matching.dart';
import '../notifications/notification_permission.dart';
import 'provider_service_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/status_chip.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/provider_job_card.dart';

class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({
    required this.providerUid,
    required this.providerName,
    required this.repository,
    this.photoUrl,
    this.onSignOut,
    this.onUpdateProfilePhoto,
    this.push,
    this.location = const GeolocatorLocationService(),
    super.key,
  });

  final String providerUid;
  final String providerName;
  final String? photoUrl;
  final MarketplaceRepository repository;
  final Future<void> Function()? onSignOut;
  final Future<String> Function(Uint8List bytes, String fileName)?
      onUpdateProfilePhoto;

  /// Used to ask for notification permission the first time the provider
  /// goes online. Null in tests and when push isn't available.
  final PushNotifications? push;

  /// Device location, for setting the base location.
  final LocationService location;

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
      length: 3,
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
            _OnlineSwitch(
              providerUid: widget.providerUid,
              repository: widget.repository,
              push: widget.push,
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
              Tab(text: 'Job board'),
              Tab(text: 'My jobs'),
              Tab(text: 'Service'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _JobBoard(
              repository: widget.repository,
              providerUid: widget.providerUid,
              actions: _actions,
              onOpenJob: (id) => _openJob(context, id),
            ),
            _JobList(
              requests: widget.repository.watchProviderJobs(widget.providerUid),
              emptyMessage: 'Accepted jobs will appear here.',
              actions: _actions,
              onOpenJob: (id) => _openJob(context, id),
              showEarnings: true,
            ),
            ProviderServiceSettings(
              providerUid: widget.providerUid,
              repository: widget.repository,
              location: widget.location,
            ),
          ],
        ),
      ),
    );
  }

  ProviderJobActions get _actions => ProviderJobActions(
    repository: widget.repository,
    providerUid: widget.providerUid,
    providerName: widget.providerName,
  );

  void _openJob(BuildContext context, String requestId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobDetailScreen(
          requestId: requestId,
          viewerUid: widget.providerUid,
          viewerName: widget.providerName,
          viewerRole: UserRole.provider,
          repository: widget.repository,
        ),
      ),
    );
  }
}

/// Takes the provider online (visible to customers, sent new jobs) or
/// offline. Going online is when we first ask for notification permission.
class _OnlineSwitch extends StatelessWidget {
  const _OnlineSwitch({
    required this.providerUid,
    required this.repository,
    required this.push,
  });

  final String providerUid;
  final MarketplaceRepository repository;
  final PushNotifications? push;

  Future<void> _set(BuildContext context, bool online) async {
    await runWithFeedback(
      context,
      () => repository.setProviderAvailability(providerUid, online),
      failureMessage: online
          ? 'Could not go online. Try again.'
          : 'Could not go offline. Try again.',
      successMessage: online ? 'You are online.' : 'You are offline.',
    );
    final push = this.push;
    if (online && push != null && context.mounted) {
      await askForNotificationsIfUseful(
        context: context,
        push: push,
        uid: providerUid,
        title: 'Get new jobs as they come in?',
        reason:
            'Turn on notifications to hear about jobs posted near you, '
            'jobs sent directly to you, and when customers accept your quote '
            'or send a message.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProviderProfile?>(
      stream: repository.watchProviderProfile(providerUid),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final online = profile?.isAvailable ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              online ? 'Online' : 'Offline',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Switch(
              value: online,
              onChanged: profile == null
                  ? null
                  : (value) => _set(context, value),
            ),
          ],
        );
      },
    );
  }
}

/// Open jobs for this provider: sent to them first, then within their
/// radius by distance, then older jobs without coordinates.
class _JobBoard extends StatelessWidget {
  const _JobBoard({
    required this.repository,
    required this.providerUid,
    required this.actions,
    required this.onOpenJob,
  });

  final MarketplaceRepository repository;
  final String providerUid;
  final ProviderJobActions actions;
  final void Function(String requestId) onOpenJob;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProviderProfile?>(
      stream: repository.watchProviderProfile(providerUid),
      builder: (context, profileSnapshot) {
        return StreamBuilder<List<ServiceRequest>>(
          stream: repository.watchOpenRequests(providerUid),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _EmptyState(
                icon: Icons.cloud_off_outlined,
                message: 'Could not load jobs. Check your connection.',
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting ||
                profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = profileSnapshot.data;
            final board = buildJobBoard(
              jobs: snapshot.data ?? const [],
              providerUid: providerUid,
              profile: profile,
            );
            final noBase = profile != null && profile.baseLocation == null;
            final radius = (profile?.serviceRadiusKm ?? defaultServiceRadiusKm)
                .round();

            return ContentWidth(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (noBase) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.near_me_outlined),
                        title: const Text('Set your base location'),
                        subtitle: const Text(
                          'Then you only see jobs within your radius, '
                          'nearest first.',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            DefaultTabController.of(context).animateTo(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (board.isEmpty)
                    _EmptyState(
                      icon: Icons.inbox_outlined,
                      message: noBase || profile == null
                          ? 'No open jobs yet.'
                          : 'No open jobs within $radius km yet.',
                    ),
                  for (final entry in board) ...[
                    ProviderJobCard(
                      request: entry.request,
                      actions: actions,
                      onOpenDetails: () => onOpenJob(entry.request.id),
                      distanceLabel: entry.distanceKm == null
                          ? null
                          : formatDistance(entry.distanceKm!),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.requests,
    required this.emptyMessage,
    required this.actions,
    required this.onOpenJob,
    this.showEarnings = false,
  });

  final Stream<List<ServiceRequest>> requests;
  final String emptyMessage;
  final ProviderJobActions actions;
  final void Function(String requestId) onOpenJob;
  final bool showEarnings;

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
        if (items.isEmpty && !showEarnings) {
          return _EmptyState(icon: Icons.inbox_outlined, message: emptyMessage);
        }

        return ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (showEarnings) ...[
                _EarningsCard(jobs: items),
                const SizedBox(height: 12),
              ],
              if (items.isEmpty)
                _EmptyState(icon: Icons.work_outline, message: emptyMessage),
              for (final request in items) ...[
                ProviderJobCard(
                  request: request,
                  actions: actions,
                  onOpenDetails: () => onOpenJob(request.id),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
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
          Icon(icon, size: 32, color: AppTheme.inkMuted),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
