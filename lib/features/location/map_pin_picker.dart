import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/geo.dart';

/// Whether the map picker is available. Maps need a Google Maps API key on
/// each platform (see README), so the map UI is off unless the app is built
/// with `--dart-define=MAPS_ENABLED=true`. Without it, typed areas and "Use
/// my current location" still work.
const mapsEnabled = bool.fromEnvironment('MAPS_ENABLED');

/// Opens a full-screen map with a pin in the middle. Returns the chosen
/// point, or null if the user backs out.
///
/// Starts at [initial], else the device location when location permission
/// is already granted, else Davao City.
Future<LatLngPoint?> pickLocationOnMap(
  BuildContext context, {
  required LocationService location,
  LatLngPoint? initial,
  String title = 'Pick the location',
}) async {
  final start =
      initial ?? await location.currentIfPermitted() ?? davaoCityCenter;
  if (!context.mounted) return null;
  return Navigator.of(context).push<LatLngPoint>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _MapPinPicker(start: start, location: location, title: title),
    ),
  );
}

class _MapPinPicker extends StatefulWidget {
  const _MapPinPicker({
    required this.start,
    required this.location,
    required this.title,
  });

  final LatLngPoint start;
  final LocationService location;
  final String title;

  @override
  State<_MapPinPicker> createState() => _MapPinPickerState();
}

class _MapPinPickerState extends State<_MapPinPicker> {
  late LatLngPoint _center = widget.start;
  GoogleMapController? _controller;
  String? _error;

  Future<void> _goToMyLocation() async {
    try {
      final here = await widget.location.requestCurrent();
      await _controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(here.latitude, here.longitude)),
      );
      setState(() {
        _center = here;
        _error = null;
      });
    } on LocationUnavailable catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Go to my location',
            onPressed: _goToMyLocation,
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.start.latitude, widget.start.longitude),
              zoom: 15,
            ),
            onMapCreated: (controller) => _controller = controller,
            onCameraMove: (position) => _center = LatLngPoint(
              position.target.latitude,
              position.target.longitude,
            ),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          // The pin stays in the middle; the map moves under it.
          const IgnorePointer(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_on, size: 44, color: AppTheme.ink),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _error ?? 'Move the map to put the pin on the spot.',
                      style: TextStyle(
                        color: _error == null
                            ? AppTheme.inkMuted
                            : AppTheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _center),
                      child: const Text('Use this location'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
