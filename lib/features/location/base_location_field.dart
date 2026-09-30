import 'package:flutter/material.dart';

import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/geo.dart';
import 'map_pin_picker.dart';

/// A provider's base location and service radius: "Use my current
/// location", "Pick on map" (when maps are enabled), "Clear", and a radius
/// slider. Used at sign-up and on the Service tab.
class BaseLocationField extends StatefulWidget {
  const BaseLocationField({
    required this.base,
    required this.radiusKm,
    required this.onBaseChanged,
    required this.onRadiusChanged,
    required this.location,
    this.enabled = true,
    super.key,
  });

  final LatLngPoint? base;
  final double radiusKm;
  final ValueChanged<LatLngPoint?> onBaseChanged;
  final ValueChanged<double> onRadiusChanged;
  final LocationService location;
  final bool enabled;

  @override
  State<BaseLocationField> createState() => _BaseLocationFieldState();
}

class _BaseLocationFieldState extends State<BaseLocationField> {
  bool _locating = false;
  String? _error;

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final here = await widget.location.requestCurrent();
      if (mounted) widget.onBaseChanged(here);
    } on LocationUnavailable catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickOnMap() async {
    final point = await pickLocationOnMap(
      context,
      location: widget.location,
      initial: widget.base,
      title: 'Where do you start from?',
    );
    if (point != null && mounted) {
      setState(() => _error = null);
      widget.onBaseChanged(point);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final base = widget.base;
    final enabled = widget.enabled && !_locating;
    final radius = clampServiceRadiusKm(widget.radiusKm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              base == null ? Icons.location_off_outlined : Icons.home_work_outlined,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                base == null
                    ? 'No base location yet'
                    : 'Base location: ${base.latitude.toStringAsFixed(4)}, '
                          '${base.longitude.toStringAsFixed(4)}',
                style: textTheme.bodyMedium?.copyWith(color: AppTheme.ink),
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: AppTheme.error)),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: enabled ? _useCurrentLocation : null,
              icon: const Icon(Icons.my_location_rounded),
              label: Text(_locating ? 'Finding you…' : 'Use my current location'),
            ),
            if (mapsEnabled)
              TextButton.icon(
                onPressed: enabled ? _pickOnMap : null,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Pick on map'),
              ),
            if (base != null)
              TextButton(
                onPressed: enabled ? () => widget.onBaseChanged(null) : null,
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Service radius: ${radius.round()} km',
          style: textTheme.bodyMedium?.copyWith(color: AppTheme.ink),
        ),
        Slider(
          value: radius,
          min: minServiceRadiusKm,
          max: maxServiceRadiusKm,
          divisions: (maxServiceRadiusKm - minServiceRadiusKm).round(),
          label: '${radius.round()} km',
          semanticFormatterCallback: (value) => '${value.round()} kilometres',
          onChanged: widget.enabled
              ? (value) => widget.onRadiusChanged(value.roundToDouble())
              : null,
        ),
      ],
    );
  }
}
