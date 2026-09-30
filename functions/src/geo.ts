// Distance helpers shared by the notification rules.
// The app has matching Dart code in lib/core/utils/geo.dart.

export interface LatLng {
  latitude: number;
  longitude: number;
}

export const DEFAULT_RADIUS_KM = 10;
export const MIN_RADIUS_KM = 2;
export const MAX_RADIUS_KM = 50;

const EARTH_RADIUS_KM = 6371.0088;

/** Great-circle distance between two points, in kilometres. */
export function distanceKm(a: LatLng, b: LatLng): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude);
  const dLng = toRad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** A provider's service radius, defaulted and clamped to 2–50 km. */
export function serviceRadiusKm(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return DEFAULT_RADIUS_KM;
  return Math.min(MAX_RADIUS_KM, Math.max(MIN_RADIUS_KM, value));
}

/** Reads a coordinate pair, or null when either half is missing or invalid. */
export function readLatLng(latitude: unknown, longitude: unknown): LatLng | null {
  if (typeof latitude !== 'number' || typeof longitude !== 'number') return null;
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
  return { latitude, longitude };
}

function normalizeArea(text: unknown): string {
  return typeof text === 'string'
    ? text.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
    : '';
}

/**
 * Text fallback for jobs or providers without coordinates: the areas match
 * when one contains the other, e.g. "Poblacion, Davao City" and "Davao City".
 */
export function serviceAreasMatch(a: unknown, b: unknown): boolean {
  const left = normalizeArea(a);
  const right = normalizeArea(b);
  if (!left || !right) return false;
  return left.includes(right) || right.includes(left);
}
