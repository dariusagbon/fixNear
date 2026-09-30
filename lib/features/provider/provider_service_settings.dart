import 'package:flutter/material.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/services/location_service.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/geo.dart';
import '../../core/widgets/status_chip.dart';
import '../location/base_location_field.dart';

/// The provider's "Service" tab: what they offer, where they start from and
/// how far they travel. The job board and new-job notifications use the
/// base location and radius.
class ProviderServiceSettings extends StatelessWidget {
  const ProviderServiceSettings({
    required this.providerUid,
    required this.repository,
    required this.location,
    this.header,
    super.key,
  });

  final String providerUid;
  final MarketplaceRepository repository;
  final LocationService location;

  /// Shown above the settings (the provider's photo card).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProviderProfile?>(
      stream: repository.watchProviderProfile(providerUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Message(
            icon: Icons.cloud_off_outlined,
            text:
                'Could not load your service settings. Check your connection.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final profile = snapshot.data;
        if (profile == null) {
          return const _Message(
            icon: Icons.person_off_outlined,
            text: 'Your provider listing is missing. Please contact support.',
          );
        }
        return _SettingsForm(
          // Keyed by provider so unsaved edits survive other profile
          // updates (like going online).
          key: ValueKey(profile.id),
          profile: profile,
          repository: repository,
          location: location,
          header: header,
        );
      },
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({
    required this.profile,
    required this.repository,
    required this.location,
    this.header,
    super.key,
  });

  final ProviderProfile profile;
  final MarketplaceRepository repository;
  final LocationService location;
  final Widget? header;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _areaController = TextEditingController(
    text: widget.profile.serviceArea,
  );
  late final _priceController = TextEditingController(
    text: '${widget.profile.startingPrice}',
  );
  late String _category = serviceCategories.contains(widget.profile.category)
      ? widget.profile.category
      : serviceCategories.first;
  late LatLngPoint? _base = widget.profile.baseLocation;
  late double _radius = widget.profile.serviceRadiusKm;
  bool _saving = false;

  @override
  void dispose() {
    _areaController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await runWithFeedback(
      context,
      () => widget.repository.updateProviderServiceSettings(
        providerUid: widget.profile.id,
        category: _category,
        serviceArea: _areaController.text,
        startingPrice: int.parse(_priceController.text.trim()),
        baseLocation: _base,
        serviceRadiusKm: _radius,
      ),
      failureMessage: 'Could not save your settings. Try again.',
      successMessage: 'Service settings saved.',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ContentWidth(
      maxWidth: 560,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.header != null) ...[
              widget.header!,
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('What you offer', style: textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      elevation: 0,
                      dropdownColor: AppTheme.tint,
                      borderRadius: BorderRadius.circular(12),
                      decoration: const InputDecoration(
                        labelText: 'Main service',
                      ),
                      items: [
                        for (final category in serviceCategories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _category = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _areaController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Service area',
                        hintText: 'City or neighborhood',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter your service area'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Starting price (PHP)',
                      ),
                      validator: (value) {
                        final price = int.tryParse(value?.trim() ?? '');
                        return price == null || price < 0
                            ? 'Enter a valid starting price'
                            : null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Where you work', style: textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'You see jobs, and get notified about them, within '
                      'your radius of your base location.',
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    BaseLocationField(
                      base: _base,
                      radiusKm: _radius,
                      location: widget.location,
                      enabled: !_saving,
                      onBaseChanged: (point) => setState(() => _base = point),
                      onRadiusChanged: (km) => setState(() => _radius = km),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save settings'),
            ),
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
