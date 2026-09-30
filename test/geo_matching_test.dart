import 'package:flutter_test/flutter_test.dart';

import 'package:fixnear/core/models/marketplace_models.dart';
import 'package:fixnear/core/utils/geo.dart';
import 'package:fixnear/core/utils/job_matching.dart';

const downtown = LatLngPoint(7.0654, 125.6076); // San Pedro Cathedral
const lanang = LatLngPoint(7.0996, 125.6317); // ~4.6 km away
const toril = LatLngPoint(7.0187, 125.4966); // ~13 km away

ServiceRequest job(
  String id, {
  LatLngPoint? at,
  String? providerUid,
  String area = 'Davao City',
  int day = 1,
}) => ServiceRequest(
  id: id,
  customerUid: 'customer-1',
  customerName: 'Casey',
  category: 'Plumbing',
  description: 'Fix a faucet',
  serviceArea: area,
  status: RequestStatus.requested,
  providerUid: providerUid,
  createdAt: DateTime(2026, 9, day),
  latitude: at?.latitude,
  longitude: at?.longitude,
);

ProviderProfile provider({
  LatLngPoint? base,
  double radius = 10,
  String area = 'Davao City',
}) => ProviderProfile(
  id: 'me',
  name: 'Pat',
  category: 'Plumbing',
  serviceArea: area,
  startingPrice: 500,
  isAvailable: true,
  baseLocation: base,
  serviceRadiusKm: radius,
);

void main() {
  group('geo', () {
    test('distances match known points', () {
      expect(distanceKm(downtown, lanang), closeTo(4.6, 0.2));
      expect(distanceKm(downtown, toril), closeTo(13.3, 0.5));
      expect(distanceKm(downtown, downtown), 0);
    });

    test('geohash matches the reference encoding', () {
      expect(
        encodeGeohash(const LatLngPoint(57.64911, 10.40744), precision: 11),
        'u4pruydqqvj',
      );
      final hash = encodeGeohash(downtown);
      expect(hash, hasLength(9));
      // Nearby points share a prefix; far ones don't.
      expect(
        encodeGeohash(const LatLngPoint(7.0655, 125.6077)).substring(0, 6),
        hash.substring(0, 6),
      );
      expect(encodeGeohash(toril).substring(0, 5), isNot(hash.substring(0, 5)));
    });

    test('distance labels read naturally', () {
      expect(formatDistance(0.01), '50 m away');
      expect(formatDistance(0.84), '850 m away');
      expect(formatDistance(2.34), '2.3 km away');
      expect(formatDistance(17.6), '18 km away');
    });

    test('radius defaults and clamps to 2–50 km', () {
      expect(clampServiceRadiusKm(null), 10);
      expect(clampServiceRadiusKm('7'), 10);
      expect(clampServiceRadiusKm(1), 2);
      expect(clampServiceRadiusKm(75), 50);
      expect(clampServiceRadiusKm(12.5), 12.5);
    });

    test('reads old documents without coordinates safely', () {
      final old = ProviderProfile.fromMap({
        'name': 'Old',
        'isAvailable': true,
      }, 'p');
      expect(old.baseLocation, isNull);
      expect(old.serviceRadiusKm, 10);
      final oldJob = ServiceRequest.fromMap({
        'serviceArea': 'Davao City',
        'latitude': 7.1,
      }, 'r');
      expect(oldJob.location, isNull);
      expect(oldJob.geohash, isNull);
    });
  });

  group('job board', () {
    test('direct jobs first, then nearby by distance; far jobs hidden', () {
      final board = buildJobBoard(
        providerUid: 'me',
        profile: provider(base: downtown),
        jobs: [
          job('far', at: toril),
          job('lanang', at: lanang),
          job('here', at: downtown),
          job('direct-far', at: toril, providerUid: 'me'),
        ],
      );
      expect(board.map((e) => e.request.id), ['direct-far', 'here', 'lanang']);
      expect(board.first.sentToMe, isTrue);
      expect(board[2].distanceKm, closeTo(4.6, 0.2));
    });

    test('a bigger radius brings farther jobs in', () {
      final board = buildJobBoard(
        providerUid: 'me',
        profile: provider(base: downtown, radius: 20),
        jobs: [
          job('far', at: toril),
          job('lanang', at: lanang),
        ],
      );
      expect(board.map((e) => e.request.id), ['lanang', 'far']);
    });

    test('jobs without coordinates still appear, matching area first', () {
      final board = buildJobBoard(
        providerUid: 'me',
        profile: provider(base: downtown),
        jobs: [
          job('old-tagum', area: 'Tagum City', day: 5),
          job('old-davao', area: 'Buhangin, Davao City', day: 2),
          job('near', at: lanang),
        ],
      );
      expect(board.map((e) => e.request.id), [
        'near',
        'old-davao',
        'old-tagum',
      ]);
      expect(board[1].distanceKm, isNull);
    });

    test('without a base location nothing is filtered by distance', () {
      final board = buildJobBoard(
        providerUid: 'me',
        profile: provider(),
        jobs: [
          job('far', at: toril, day: 3),
          job('near', at: lanang, day: 1),
          job('old', day: 2),
        ],
      );
      expect(board.map((e) => e.request.id), ['far', 'near', 'old']);
      expect(board.every((e) => e.distanceKm == null), isTrue);
    });
  });

  group('providers for customers', () {
    test('sorted nearest first with unknown distances last', () {
      final providers = [
        provider(base: toril),
        provider(),
        provider(base: lanang),
      ];
      final sorted = withDistances(providers, downtown);
      expect(sorted.map((e) => e.profile.baseLocation), [lanang, toril, null]);
      expect(withDistances(providers, null).map((e) => e.distanceKm), [
        null,
        null,
        null,
      ]);
    });
  });
}
