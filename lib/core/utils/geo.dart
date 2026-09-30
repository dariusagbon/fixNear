import 'dart:math' as math;

/// Distance and geohash helpers. Cloud Functions use the same rules in
/// functions/src/geo.ts.

class LatLngPoint {
  const LatLngPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Reads a coordinate pair, or null when either half is missing or out of
  /// range (older documents have neither).
  static LatLngPoint? tryFrom(Object? latitude, Object? longitude) {
    if (latitude is! num || longitude is! num) return null;
    final lat = latitude.toDouble();
    final lng = longitude.toDouble();
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return LatLngPoint(lat, lng);
  }

  @override
  bool operator ==(Object other) =>
      other is LatLngPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLngPoint($latitude, $longitude)';
}

/// Davao City center, used when no better starting point is known.
const davaoCityCenter = LatLngPoint(7.0731, 125.6128);

const defaultServiceRadiusKm = 10.0;
const minServiceRadiusKm = 2.0;
const maxServiceRadiusKm = 50.0;

/// A provider's service radius, defaulted and clamped to 2–50 km.
double clampServiceRadiusKm(Object? value) {
  if (value is! num || !value.toDouble().isFinite) {
    return defaultServiceRadiusKm;
  }
  return value.toDouble().clamp(minServiceRadiusKm, maxServiceRadiusKm);
}

const _earthRadiusKm = 6371.0088;

/// Great-circle distance in kilometres.
double distanceKm(LatLngPoint a, LatLngPoint b) {
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
}

/// "850 m away", "2.3 km away", "18 km away".
String formatDistance(double km) {
  if (km < 1) {
    final metres = (km * 1000 / 50).round() * 50;
    return '${math.max(50, metres)} m away';
  }
  if (km < 10) return '${km.toStringAsFixed(1)} km away';
  return '${km.round()} km away';
}

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Standard geohash of [point]. 9 characters is about 5 m.
String encodeGeohash(LatLngPoint point, {int precision = 9}) {
  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;
  final hash = StringBuffer();
  var bit = 0, ch = 0;
  var evenBit = true;
  while (hash.length < precision) {
    if (evenBit) {
      final mid = (lngMin + lngMax) / 2;
      if (point.longitude >= mid) {
        ch = (ch << 1) | 1;
        lngMin = mid;
      } else {
        ch = ch << 1;
        lngMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (point.latitude >= mid) {
        ch = (ch << 1) | 1;
        latMin = mid;
      } else {
        ch = ch << 1;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (++bit == 5) {
      hash.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return hash.toString();
}

String _normalizeArea(String text) =>
    text.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();

/// Text fallback when coordinates are missing: one area contains the other,
/// e.g. "Poblacion, Davao City" and "Davao City".
bool serviceAreasMatch(String a, String b) {
  final left = _normalizeArea(a);
  final right = _normalizeArea(b);
  if (left.isEmpty || right.isEmpty) return false;
  return left.contains(right) || right.contains(left);
}
