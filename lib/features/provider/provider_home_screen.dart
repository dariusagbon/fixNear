import 'package:flutter/material.dart';

import '../../core/models/app_user.dart';
import '../../core/services/cloudinary_service.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/services/location_service.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/services/push_notifications.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/job_matching.dart';
import '../../core/widgets/profile_avatar.dart';
import '../notifications/notification_permission.dart';
import '../profile/edit_profile_screen.dart';
import 'provider_service_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/status_chip.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/provider_job_card.dart';

class ProviderHomeScreen extends StatelessWidget {
  const ProviderHomeScreen({
    required this.providerUid,
    required this.providerName,
    required this.repository,
    this.onSignOut,
    this.push,
    this.location = const GeolocatorLocationService(),
    this.profile,
    this.imageUploader,
    this.onSaveProfile,
    this.pickPhoto = pickPhotoWithImagePicker,
    this.account,
    super.key,
  });

  final String providerUid;
  final String providerName;
  final MarketplaceRepository repository;
  final Future<void> Function()? onSignOut;

  /// Used to ask for notification permission the first time the provider
  /// goes online. Null in tests and when push isn't available.
  final PushNotifications? push;

  /// Device location, for setting the base location.
  final LocationService location;

  /// The provider's account profile. Profile editing (name, phone, photo) is
  /// available when this, [imageUploader] and [onSaveProfile] are provided.
  final AppUser? profile;
  final ImageUploader? imageUploader;
  final ProfileSaver? onSaveProfile;
  final PhotoPicker pickPhoto;

  /// Email verification and account deletion, shown in Edit profile.
  final AccountControls? account;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 8,
          title: _ProfileTitle(
            name: profile?.name ?? providerName,
            photoUrl: profile?.photoUrl,
            onTap: _canEditProfile ? () => _openEditProfile(context) : null,
          ),
          actions: [
            _OnlineSwitch(
              providerUid: providerUid,
              repository: repository,
              push: push,
            ),
            if (onSignOut != null)
              IconButton(
                tooltip: 'Sign out',
                onPressed: onSignOut,
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
              repository: repository,
              providerUid: providerUid,
              actions: actions,
              onOpenJob: (id) => _openJob(context, id),
            ),
            _JobList(
              requests: repository.watchProviderJobs(providerUid),
              emptyMessage: 'Accepted jobs will appear here.',
              actions: actions,
              onOpenJob: (id) => _openJob(context, id),
              showEarnings: true,
            ),
            ProviderServiceSettings(
              providerUid: providerUid,
              repository: repository,
              location: location,
            ),
          ],
        ),
      ),
    );
  }

  bool get _canEditProfile =>
      profile != null && imageUploader != null && onSaveProfile != null;

  void _openEditProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditProfileScreen(
          profile: profile!,
          uploader: imageUploader!,
          onSave: onSaveProfile!,
          pickPhoto: pickPhoto,
          account: account,
        ),
      ),
    );
  }

  ProviderJobActions get actions => ProviderJobActions(
    repository: repository,
    providerUid: providerUid,
    providerName: providerName,
  );

  void _openJob(BuildContext context, String requestId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobDetailScreen(
          requestId: requestId,
          viewerUid: providerUid,
          viewerName: providerName,
          viewerRole: UserRole.provider,
          repository: repository,
        ),
      ),
    );
  }
}

/// The provider's photo and name; tapping opens Edit profile.
class _ProfileTitle extends StatelessWidget {
  const _ProfileTitle({required this.name, this.photoUrl, this.onTap});

  final String name;
  final String? photoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileAvatar(name: name, photoUrl: photoUrl, radius: 18),
          const SizedBox(width: 10),
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: 'Edit profile',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTheme.minTapTarget),
          child: content,
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
class _JobBoard extends StatefulWidget {
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
  State<_JobBoard> createState() => _JobBoardState();
}

class _JobBoardState extends State<_JobBoard> {
  bool _allCategories = false;

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final providerUid = widget.providerUid;
    final actions = widget.actions;
    final onOpenJob = widget.onOpenJob;
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
              allCategories: _allCategories,
            );
            final noBase = profile != null && profile.baseLocation == null;
            final radius = (profile?.serviceRadiusKm ?? defaultServiceRadiusKm)
                .round();

            return ContentWidth(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (profile != null) ...[
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text('${profile.category} jobs'),
                          selected: !_allCategories,
                          onSelected: (_) =>
                              setState(() => _allCategories = false),
                        ),
                        ChoiceChip(
                          label: const Text('All services'),
                          selected: _allCategories,
                          onSelected: (_) =>
                              setState(() => _allCategories = true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
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
                          : _allCategories
                          ? 'No open jobs within $radius km yet.'
                          : 'No ${profile.category.toLowerCase()} jobs within $radius km yet. Try All services.',
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
