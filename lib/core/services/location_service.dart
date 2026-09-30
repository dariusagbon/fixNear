import 'package:geolocator/geolocator.dart';

import '../utils/geo.dart';

/// Thrown when the device location can't be used; [message] is shown to the
/// user as-is.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Device location, behind an interface so screens can be tested.
abstract interface class LocationService {
  /// The current location if permission was already granted. Never prompts;
  /// returns null otherwise.
  Future<LatLngPoint?> currentIfPermitted();

  /// The current location, asking for permission if needed. Throws
  /// [LocationUnavailable] with a plain-language reason on failure.
  Future<LatLngPoint> requestCurrent();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  static const _settings = LocationSettings(accuracy: LocationAccuracy.medium);

  bool _granted(LocationPermission permission) =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;

  Future<LatLngPoint> _position() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: _settings,
    ).timeout(const Duration(seconds: 15));
    return LatLngPoint(position.latitude, position.longitude);
  }

  @override
  Future<LatLngPoint?> currentIfPermitted() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      if (!_granted(await Geolocator.checkPermission())) return null;
      return await _position();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LatLngPoint> requestCurrent() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationUnavailable(
          'Turn on location services, or type the area instead.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!_granted(permission)) {
        throw const LocationUnavailable(
          'Allow location access to use your current location, or type the area instead.',
        );
      }
      return await _position();
    } on LocationUnavailable {
      rethrow;
    } catch (_) {
      throw const LocationUnavailable(
        'Could not get your location. Try again, or type the area instead.',
      );
    }
  }
}
