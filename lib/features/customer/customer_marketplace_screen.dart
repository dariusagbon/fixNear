import 'package:flutter/material.dart';

import '../../core/models/app_user.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/services/cloudinary_service.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/push_notifications.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/job_matching.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/status_chip.dart';
import '../jobs/customer_job_card.dart';
import '../jobs/job_detail_screen.dart';
import '../location/map_pin_picker.dart';
import '../notifications/notification_permission.dart';
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
    this.push,
    this.location = const GeolocatorLocationService(),
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

  /// Used to ask for notification permission after the first job is posted.
  final PushNotifications? push;

  /// Device location, for pinning jobs and showing provider distances.
  final LocationService location;

  @override
  State<CustomerMarketplaceScreen> createState() =>
      _CustomerMarketplaceScreenState();
}

class _CustomerMarketplaceScreenState extends State<CustomerMarketplaceScreen> {
  final _searchController = TextEditingController();
  String? _selectedCategory;
  int _selectedTab = 0;

  /// The customer's location for provider distances; only read without a
  /// prompt, or after they tap "Show distances".
  LatLngPoint? _here;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    widget.location.currentIfPermitted().then((here) {
      if (here != null && mounted) setState(() => _here = here);
    });
  }

  Future<void> _showDistances() async {
    setState(() => _locating = true);
    try {
      final here = await widget.location.requestCurrent();
      if (mounted) setState(() => _here = here);
    } on LocationUnavailable catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_here == null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _locating ? null : _showDistances,
                        icon: const Icon(Icons.near_me_outlined),
                        label: Text(
                          _locating ? 'Finding you…' : 'Show distances',
                        ),
                      ),
                    ),
                  for (final entry in withDistances(providers, _here))
                    _ProviderCard(
                      provider: entry.profile,
                      distanceKm: entry.distanceKm,
                      onRequest: () =>
                          _showRequestForm(provider: entry.profile),
                    ),
                ],
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
                  itemBuilder: (context, index) => CustomerRequestCard(
                    request: requests[index],
                    actions: _jobActions,
                    onOpenDetails: () => _openJob(requests[index].id),
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
        location: widget.location,
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
      final push = widget.push;
      if (push != null) {
        await askForNotificationsIfUseful(
          context: context,
          push: push,
          uid: widget.customerUid,
          title: 'Get updates on your job?',
          reason:
              'Turn on notifications to hear when providers send quotes, '
              'when your provider is on the way, and when they message you.',
        );
      }
    }
  }

  CustomerJobActions get _jobActions => CustomerJobActions(
    repository: widget.repository,
    customerUid: widget.customerUid,
    customerName: widget.customerName,
  );

  void _openJob(String requestId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobDetailScreen(
          requestId: requestId,
          viewerUid: widget.customerUid,
          viewerName: widget.customerName,
          viewerRole: UserRole.customer,
          repository: widget.repository,
        ),
      ),
    );
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
  const _ProviderCard({
    required this.provider,
    required this.onRequest,
    this.distanceKm,
  });

  final ProviderProfile provider;
  final VoidCallback onRequest;
  final double? distanceKm;

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
                Expanded(
                  child: Text(
                    distanceKm == null
                        ? provider.serviceArea
                        : '${provider.serviceArea} · ${formatDistance(distanceKm!)}',
                  ),
                ),
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

class _NewRequestSheet extends StatefulWidget {
  const _NewRequestSheet({
    required this.initialCategory,
    required this.provider,
    required this.location,
    required this.onSubmit,
  });

  final String? initialCategory;
  final ProviderProfile? provider;
  final LocationService location;
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
  LatLngPoint? _pin;
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
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _useCurrentLocation,
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Use my current location'),
                ),
                if (mapsEnabled)
                  TextButton.icon(
                    onPressed: _pickOnMap,
                    icon: const Icon(Icons.map_outlined),
                    label: Text(_pin == null ? 'Pick on map' : 'Move pin'),
                  ),
              ],
            ),
            if (_pin != null)
              Row(
                children: [
                  const Icon(Icons.place_rounded, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Pinned at ${_pin!.latitude.toStringAsFixed(4)}, ${_pin!.longitude.toStringAsFixed(4)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _pin = null),
                    child: const Text('Remove pin'),
                  ),
                ],
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
        _pin?.latitude,
        _pin?.longitude,
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

  void _setPin(LatLngPoint point, String defaultLabel) {
    setState(() {
      _pin = point;
      if (_locationController.text.trim().isEmpty) {
        _locationController.text = defaultLabel;
      }
      _error = null;
    });
  }

  Future<void> _useCurrentLocation() async {
    try {
      final here = await widget.location.requestCurrent();
      if (mounted) _setPin(here, 'Current location');
    } on LocationUnavailable catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _pickOnMap() async {
    final point = await pickLocationOnMap(
      context,
      location: widget.location,
      initial: _pin,
      title: 'Where is the job?',
    );
    if (point != null && mounted) _setPin(point, 'Pinned location');
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
