import 'package:flutter/material.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/services/location_service.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/geo.dart';
import '../../core/widgets/status_chip.dart';
import '../location/map_pin_picker.dart';

/// The provider's "Service" tab: what they offer, where they start from and
/// how far they travel. The job board and new-job notifications use the
/// base location and radius.
class ProviderServiceSettings extends StatelessWidget {
  const ProviderServiceSettings({
    required this.providerUid,
    required this.repository,
    required this.location,
    super.key,
  });

  final String providerUid;
  final MarketplaceRepository repository;
  final LocationService location;

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
    super.key,
  });

  final ProviderProfile profile;
  final MarketplaceRepository repository;
  final LocationService location;

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
  bool _locating = false;
  bool _saving = false;
  String? _locationError;

  @override
  void dispose() {
    _areaController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final here = await widget.location.requestCurrent();
      if (mounted) setState(() => _base = here);
    } on LocationUnavailable catch (error) {
      if (mounted) setState(() => _locationError = error.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickOnMap() async {
    final point = await pickLocationOnMap(
      context,
      location: widget.location,
      initial: _base,
      title: 'Where do you start from?',
    );
    if (point != null && mounted) {
      setState(() {
        _base = point;
        _locationError = null;
      });
    }
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
                    Row(
                      children: [
                        const Icon(Icons.home_work_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _base == null
                                ? 'No base location yet'
                                : 'Base location: ${_base!.latitude.toStringAsFixed(4)}, ${_base!.longitude.toStringAsFixed(4)}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_locationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _locationError!,
                          style: const TextStyle(color: AppTheme.error),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: _locating ? null : _useCurrentLocation,
                          icon: const Icon(Icons.my_location_rounded),
                          label: Text(
                            _locating
                                ? 'Finding you…'
                                : 'Use my current location',
                          ),
                        ),
                        if (mapsEnabled)
                          TextButton.icon(
                            onPressed: _pickOnMap,
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Pick on map'),
                          ),
                        if (_base != null)
                          TextButton(
                            onPressed: () => setState(() => _base = null),
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Service radius: ${_radius.round()} km',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppTheme.ink,
                      ),
                    ),
                    Slider(
                      value: _radius,
                      min: minServiceRadiusKm,
                      max: maxServiceRadiusKm,
                      divisions: (maxServiceRadiusKm - minServiceRadiusKm)
                          .round(),
                      label: '${_radius.round()} km',
                      semanticFormatterCallback: (value) =>
                          '${value.round()} kilometres',
                      onChanged: (value) =>
                          setState(() => _radius = value.roundToDouble()),
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
