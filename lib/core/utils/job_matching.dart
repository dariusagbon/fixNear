import '../models/marketplace_models.dart';
import 'geo.dart';

/// One job on a provider's board, with its distance when both the job and
/// the provider have a location.
class BoardEntry {
  const BoardEntry({
    required this.request,
    required this.distanceKm,
    required this.sentToMe,
  });

  final ServiceRequest request;
  final double? distanceKm;
  final bool sentToMe;
}

/// Builds a provider's job board from the open jobs they can see.
///
/// 1. Jobs sent directly to them, always, nearest first.
/// 2. Jobs within their service radius, nearest first.
/// 3. Located jobs, unfiltered, while the provider has no base location.
/// 4. Older jobs without coordinates, always shown; ones whose text area
///    matches the provider's come first.
///
/// Unless [allCategories] is true, broadcast jobs outside the provider's
/// main service are left out.
List<BoardEntry> buildJobBoard({
  required List<ServiceRequest> jobs,
  required String providerUid,
  required ProviderProfile? profile,
  bool allCategories = false,
}) {
  final base = profile?.baseLocation;
  final radius = profile?.serviceRadiusKm ?? defaultServiceRadiusKm;
  final area = profile?.serviceArea ?? '';

  final direct = <BoardEntry>[];
  final nearby = <BoardEntry>[];
  final unfiltered = <BoardEntry>[];
  final legacy = <BoardEntry>[];

  for (final job in jobs) {
    final location = job.location;
    final distance = location != null && base != null
        ? distanceKm(base, location)
        : null;
    final sentToMe = job.providerUid == providerUid;
    final entry = BoardEntry(
      request: job,
      distanceKm: distance,
      sentToMe: sentToMe,
    );
    if (sentToMe) {
      direct.add(entry);
    } else if (!allCategories &&
        profile != null &&
        !sameCategory(job.category, profile.category)) {
      continue;
    } else if (location == null) {
      legacy.add(entry);
    } else if (distance == null) {
      unfiltered.add(entry);
    } else if (distance <= radius) {
      nearby.add(entry);
    }
  }

  int byDistanceThenNewest(BoardEntry a, BoardEntry b) {
    final da = a.distanceKm, db = b.distanceKm;
    if (da != null && db != null && da != db) return da.compareTo(db);
    if (da != null && db == null) return -1;
    if (da == null && db != null) return 1;
    return b.request.createdAt.compareTo(a.request.createdAt);
  }

  int newestFirst(BoardEntry a, BoardEntry b) =>
      b.request.createdAt.compareTo(a.request.createdAt);

  bool areaMatches(BoardEntry e) =>
      serviceAreasMatch(e.request.serviceArea, area);

  direct.sort(byDistanceThenNewest);
  nearby.sort(byDistanceThenNewest);
  unfiltered.sort(newestFirst);
  legacy.sort((a, b) {
    final ma = areaMatches(a), mb = areaMatches(b);
    if (ma != mb) return ma ? -1 : 1;
    return newestFirst(a, b);
  });
  return [...direct, ...nearby, ...unfiltered, ...legacy];
}

bool sameCategory(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// A provider for customers, with distance from the customer when known.
class NearbyProvider {
  const NearbyProvider(this.profile, this.distanceKm);

  final ProviderProfile profile;
  final double? distanceKm;
}

/// Adds distances from [from] and sorts nearest first; providers without a
/// base location keep their order after the located ones.
List<NearbyProvider> withDistances(
  List<ProviderProfile> providers,
  LatLngPoint? from,
) {
  final entries = [
    for (final provider in providers)
      NearbyProvider(
        provider,
        from == null || provider.baseLocation == null
            ? null
            : distanceKm(from, provider.baseLocation!),
      ),
  ];
  if (from == null) return entries;
  final indexed = entries.indexed.toList()
    ..sort((a, b) {
      final da = a.$2.distanceKm, db = b.$2.distanceKm;
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.$1.compareTo(b.$1);
    });
  return [for (final (_, entry) in indexed) entry];
}
