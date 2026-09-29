import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/models/app_user.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/services/cloudinary_service.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/attention.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/status_chip.dart';
import '../messaging/job_chat_sheet.dart';
import '../profile/edit_profile_screen.dart';

class CustomerMarketplaceScreen extends StatefulWidget {
  const CustomerMarketplaceScreen({
    required this.customerUid,
    required this.customerName,
    required this.repository,
    this.onSignOut,
    this.profile,
    this.imageUploader,
    this.onSaveProfile,
    this.pickPhoto = pickPhotoWithImagePicker,
    super.key,
  });

  final String customerUid;
  final String customerName;
  final MarketplaceRepository repository;
  final Future<void> Function()? onSignOut;

  /// The signed-in customer's profile. Profile editing is available when this,
  /// [imageUploader] and [onSaveProfile] are all provided.
  final AppUser? profile;
  final ImageUploader? imageUploader;
  final ProfileSaver? onSaveProfile;
  final PhotoPicker pickPhoto;

  @override
  State<CustomerMarketplaceScreen> createState() =>
      _CustomerMarketplaceScreenState();
}

class _CustomerMarketplaceScreenState extends State<CustomerMarketplaceScreen> {
  final _searchController = TextEditingController();
  String? _selectedCategory;
  int _selectedTab = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_selectedTab) {
          0 => _buildDiscover(),
          1 => _buildRequests(),
          _ => _buildAccount(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }

  Widget _buildDiscover() {
    final firstName = widget.customerName.trim().split(RegExp(r'\s+')).first;
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            children: [
              const Icon(Icons.handyman_rounded, color: AppTheme.ink),
              const SizedBox(width: 8),
              Text('FixNear', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: 'My requests',
                onPressed: () => setState(() => _selectedTab = 1),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              IconButton(
                tooltip: 'Account',
                onPressed: () => setState(() => _selectedTab = 2),
                icon: ProfileAvatar(
                  name: widget.customerName,
                  photoUrl: widget.profile?.photoUrl,
                  radius: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (firstName.isNotEmpty)
            Text(
              'Hi, $firstName',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 4),
          Text(
            'What can we help you with?',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search services or providers',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: serviceCategories.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final category = index == 0
                    ? null
                    : serviceCategories[index - 1];
                final selected = category == _selectedCategory;
                final label = category ?? 'All';
                return ChoiceChip(
                  selected: selected,
                  label: Text(label),
                  avatar: Icon(
                    _categoryIcon(category),
                    size: 18,
                    color: selected ? Colors.white : AppTheme.ink,
                  ),
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => _selectedCategory = category),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Available providers',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => _showRequestForm(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Request service'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<ProviderProfile>>(
            stream: widget.repository.watchProviders(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _InlineMessage(
                  icon: Icons.cloud_off_outlined,
                  message: 'Could not load providers. Check your connection and try again.',
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final query = _searchController.text.trim().toLowerCase();
              final providers = (snapshot.data ?? const <ProviderProfile>[])
                  .where((provider) {
                    final matchesCategory =
                        _selectedCategory == null ||
                        provider.category == _selectedCategory;
                    final matchesQuery =
                        query.isEmpty ||
                        provider.name.toLowerCase().contains(query) ||
                        provider.category.toLowerCase().contains(query) ||
                        provider.serviceArea.toLowerCase().contains(query);
                    return matchesCategory && matchesQuery;
                  })
                  .toList();

              if (providers.isEmpty) {
                return const _InlineMessage(
                  icon: Icons.search_off_rounded,
                  message: 'No providers match this search yet. Try another category or send a service request.',
                );
              }

              return Column(
                children: providers
                    .map(
                      (provider) => _ProviderCard(
                        provider: provider,
                        onRequest: () => _showRequestForm(provider: provider),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRequests() {
    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'My requests',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ServiceRequest>>(
              stream: widget.repository.watchCustomerRequests(
                widget.customerUid,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _InlineMessage(
                    icon: Icons.cloud_off_outlined,
                    message: 'Could not load your requests.',
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final requests = snapshot.data ?? const <ServiceRequest>[];
                if (requests.isEmpty) {
                  return const _InlineMessage(
                    icon: Icons.receipt_long_outlined,
                    message: 'Your service requests will appear here.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: requests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _CustomerRequestCard(
                    request: requests[index],
                    quotes: widget.repository.watchQuotes(requests[index].id),
                    onAcceptQuote: (quote) => _runWithFeedback(
                      () => widget.repository.acceptQuote(
                        requests[index].id,
                        quote,
                      ),
                      failureMessage: 'Could not accept this quote.',
                      successMessage: 'Quote accepted.',
                    ),
                    onCancel: () => _cancelRequest(requests[index]),
                    onConfirmCompletion: () => _runWithFeedback(
                      () => widget.repository.confirmCompletion(
                        requests[index].id,
                        widget.customerUid,
                      ),
                      failureMessage: 'Could not confirm completion.',
                    ),
                    onOpenChat: requests[index].providerUid == null
                        ? null
                        : () => showJobChatSheet(
                            context: context,
                            requestId: requests[index].id,
                            currentUid: widget.customerUid,
                            currentName: widget.customerName,
                            repository: widget.repository,
                          ),
                    onPayCash: () => _runWithFeedback(
                      () => widget.repository.recordCashPayment(
                        requests[index].id,
                        widget.customerUid,
                      ),
                      failureMessage: 'Could not record cash payment.',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccount() {
    final profile = widget.profile;
    final canEdit =
        profile != null &&
        widget.imageUploader != null &&
        widget.onSaveProfile != null;
    final textTheme = Theme.of(context).textTheme;
    return ContentWidth(
      maxWidth: 480,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          Center(
            child: ProfileAvatar(
              name: widget.customerName,
              photoUrl: profile?.photoUrl,
              radius: 44,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.customerName,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text('Customer account', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          if (profile != null)
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Email'),
                    subtitle: Text(profile.email),
                  ),
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: const Text('Phone'),
                    subtitle: Text(profile.phone ?? 'Not added'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          if (canEdit)
            FilledButton.icon(
              onPressed: () => _openEditProfile(profile),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
          const SizedBox(height: 10),
          if (widget.onSignOut != null)
            OutlinedButton.icon(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
        ],
      ),
    );
  }

  void _openEditProfile(AppUser profile) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditProfileScreen(
          profile: profile,
          uploader: widget.imageUploader!,
          onSave: widget.onSaveProfile!,
          pickPhoto: widget.pickPhoto,
        ),
      ),
    );
  }

  Future<void> _showRequestForm({ProviderProfile? provider}) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _NewRequestSheet(
        initialCategory: provider?.category ?? _selectedCategory,
        provider: provider,
        onSubmit:
            (
              category,
              description,
              area,
              locationLabel,
              latitude,
              longitude,
              scheduledAt,
            ) => widget.repository.createRequest(
              customerUid: widget.customerUid,
              customerName: widget.customerName,
              category: category,
              description: description,
              serviceArea: area,
              locationLabel: locationLabel,
              latitude: latitude,
              longitude: longitude,
              provider: provider,
              scheduledAt: scheduledAt,
            ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Service request sent.')));
      setState(() => _selectedTab = 1);
    }
  }

  Future<void> _cancelRequest(ServiceRequest request) async {
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
    if (confirmed != true) return;
    await _runWithFeedback(
      () => widget.repository.cancelRequest(request.id),
      failureMessage: 'Could not cancel this request.',
      successMessage: 'Request cancelled.',
    );
  }

  Future<void> _runWithFeedback(
    Future<void> Function() action, {
    required String failureMessage,
    String? successMessage,
  }) async {
    try {
      await action();
      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error, failureMessage))),
      );
    }
  }

  IconData _categoryIcon(String? category) => switch (category) {
    'Electrical' => Icons.electrical_services_rounded,
    'Plumbing' => Icons.plumbing_rounded,
    'Cleaning' => Icons.cleaning_services_rounded,
    'Moving' => Icons.local_shipping_rounded,
    'Automotive' => Icons.directions_car_rounded,
    'Computer' => Icons.computer_rounded,
    'Repair' || 'Handyman' => Icons.build_rounded,
    _ => Icons.grid_view_rounded,
  };
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, required this.onRequest});

  final ProviderProfile provider;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(initialsFor(provider.name))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        provider.category,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.circle, size: 10, color: AppTheme.success),
                const SizedBox(width: 5),
                const Text('Available', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 17),
                const SizedBox(width: 4),
                Expanded(child: Text(provider.serviceArea)),
                Text(
                  'From ${formatPeso(provider.startingPrice)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onRequest,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Request service'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerRequestCard extends StatelessWidget {
  const _CustomerRequestCard({
    required this.request,
    required this.quotes,
    required this.onAcceptQuote,
    required this.onCancel,
    required this.onConfirmCompletion,
    required this.onOpenChat,
    required this.onPayCash,
  });

  final ServiceRequest request;
  final Stream<List<ProviderQuote>> quotes;
  final Future<void> Function(ProviderQuote quote) onAcceptQuote;
  final VoidCallback onCancel;
  final Future<void> Function() onConfirmCompletion;
  final VoidCallback? onOpenChat;
  final Future<void> Function() onPayCash;

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
            if (onOpenChat != null && request.status != RequestStatus.cancelled)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Chat'),
                ),
              ),
            if (request.status == RequestStatus.requested ||
                request.status == RequestStatus.quoted)
              StreamBuilder<List<ProviderQuote>>(
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
                  final availableQuotes =
                      snapshot.data ?? const <ProviderQuote>[];
                  if (availableQuotes.isEmpty) {
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
                      for (final quote in availableQuotes)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${quote.providerName} · ${formatPeso(quote.price)}',
                          ),
                          subtitle: Text(quote.note),
                          trailing: FilledButton(
                            onPressed: () => onAcceptQuote(quote),
                            child: const Text('Accept'),
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (request.status == RequestStatus.providerCompleted)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onConfirmCompletion,
                  child: const Text('Confirm completion'),
                ),
              ),
            if (request.status == RequestStatus.completed &&
                request.paymentStatus == 'unpaid')
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onPayCash,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Pay cash'),
                ),
              ),
            if (request.paymentStatus == 'pending_provider_confirmation')
              const Text('Cash payment awaiting provider confirmation.'),
            if (request.paymentStatus == 'paid')
              const Text('Payment confirmed.'),
            if (request.status == RequestStatus.requested ||
                request.status == RequestStatus.quoted)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel request'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NewRequestSheet extends StatefulWidget {
  const _NewRequestSheet({
    required this.initialCategory,
    required this.provider,
    required this.onSubmit,
  });

  final String? initialCategory;
  final ProviderProfile? provider;
  final Future<void> Function(
    String category,
    String description,
    String area,
    String locationLabel,
    double? latitude,
    double? longitude,
    DateTime scheduledAt,
  )
  onSubmit;

  @override
  State<_NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends State<_NewRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _areaController = TextEditingController();
  final _locationController = TextEditingController();
  late String _category;
  DateTime? _scheduledAt;
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? serviceCategories.first;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _areaController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Request a service',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.provider != null) ...[
              const SizedBox(height: 6),
              Text('Requesting ${widget.provider!.name}'),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              elevation: 0,
              dropdownColor: AppTheme.tint,
              borderRadius: BorderRadius.circular(12),
              decoration: const InputDecoration(labelText: 'Service category'),
              items: serviceCategories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: widget.provider == null
                  ? (category) {
                      if (category != null) {
                        setState(() => _category = category);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_rounded),
              title: Text(
                _scheduledAt == null
                    ? 'Choose date and time'
                    : formatDateTime(_scheduledAt!),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _chooseSchedule,
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Describe the work needed',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().length < 8
                  ? 'Add a little more detail'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Location label',
                hintText: 'Home, office, or landmark',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Use my current location'),
              ),
            ),
            if (_latitude != null && _longitude != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Pinned: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _areaController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Service area'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter the service area'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send request'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scheduledAt == null) {
      setState(() => _error = 'Choose a date and time for the service.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        _category,
        _descriptionController.text,
        _areaController.text,
        _locationController.text.trim().isEmpty
            ? _areaController.text.trim()
            : _locationController.text.trim(),
        _latitude,
        _longitude,
        _scheduledAt!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send your request. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      final status = permission == LocationPermission.denied
          ? await Geolocator.requestPermission()
          : permission;
      if (status == LocationPermission.denied ||
          status == LocationPermission.deniedForever) {
        throw StateError(
          'Allow location access to pin your location, or type it instead.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationController.text = _locationController.text.trim().isEmpty
            ? 'Current location'
            : _locationController.text.trim();
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(
          error,
          'Could not access your current location. Type it instead.',
        );
      });
    }
  }

  Future<void> _chooseSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledAt == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(_scheduledAt!),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _error = null;
    });
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppTheme.inkMuted),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// A small icon-and-text line inside a card, for inline empty and error
/// states.
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
