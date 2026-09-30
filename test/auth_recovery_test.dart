import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixnear/core/models/app_user.dart';
import 'package:fixnear/core/services/auth_service.dart';
import 'package:fixnear/core/utils/geo.dart';

/// Just enough of a Firebase [User] for AuthService.
class _FakeUser implements User {
  _FakeUser(this.uid, {this.email, this.displayName});

  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeFirebaseFirestore firestore;
  late AuthService auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    // FirebaseAuth isn't used by the methods under test.
    auth = AuthService(firestore: firestore, firebaseAuth: _NoAuth());
  });

  group('ensureUserProfileExists', () {
    test('returns an existing profile untouched', () async {
      await firestore.doc('users/u1').set({
        'email': 'casey@example.com',
        'name': 'Casey',
        'role': 'customer',
        'phone': '0917',
        'photoUrl': null,
        'createdAt': DateTime(2026),
      });
      final profile = await auth.ensureUserProfileExists(_FakeUser('u1'));
      expect(profile.name, 'Casey');
      expect(profile.phone, '0917');
    });

    test('rebuilds a missing customer profile', () async {
      final profile = await auth.ensureUserProfileExists(
        _FakeUser('u2', email: 'new@example.com'),
      );
      expect(profile.role, UserRole.customer);
      expect(profile.name, 'FixNear User');
      final saved = (await firestore.doc('users/u2').get()).data()!;
      expect(saved['email'], 'new@example.com');
      expect(saved['role'], 'customer');
      // Only the fields the users rules allow on create.
      expect(saved.keys.toSet(), {
        'email',
        'name',
        'role',
        'phone',
        'photoUrl',
        'createdAt',
      });
    });

    test('restores a provider when their listing exists', () async {
      await firestore.doc('providerProfiles/u3').set({
        'name': 'Pat Plumbing',
        'isAvailable': true,
      });
      final profile = await auth.ensureUserProfileExists(
        _FakeUser('u3', email: 'pat@example.com'),
      );
      expect(profile.role, UserRole.provider);
      expect(profile.name, 'Pat Plumbing');
    });

    test('prefers the account display name when there is one', () async {
      final profile = await auth.ensureUserProfileExists(
        _FakeUser('u4', email: 'd@example.com', displayName: 'Dana'),
      );
      expect(profile.name, 'Dana');
    });
  });

  group('registerWithEmailAndPassword', () {
    late AuthService signUp;
    setUp(() {
      signUp = AuthService(firestore: firestore, firebaseAuth: _SignUpAuth());
    });

    test('saves a provider base location and radius', () async {
      await signUp.registerWithEmailAndPassword(
        email: 'pat@example.com',
        password: 'secret123',
        name: 'Pat',
        role: UserRole.provider,
        serviceCategory: 'Plumbing',
        serviceArea: 'Lanang',
        startingPrice: 500,
        baseLocation: const LatLngPoint(7.0996, 125.6317),
        serviceRadiusKm: 80,
      );
      final listing = (await firestore.doc('providerProfiles/new-pro').get())
          .data()!;
      expect(listing['baseLatitude'], 7.0996);
      expect(listing['baseLongitude'], 125.6317);
      expect(
        listing['baseGeohash'],
        encodeGeohash(const LatLngPoint(7.0996, 125.6317)),
      );
      // Clamped to the allowed range.
      expect(listing['serviceRadiusKm'], 50);
    });

    test('leaves location fields out when none was given', () async {
      await signUp.registerWithEmailAndPassword(
        email: 'pat@example.com',
        password: 'secret123',
        name: 'Pat',
        role: UserRole.provider,
        serviceCategory: 'Plumbing',
        serviceArea: 'Lanang',
        startingPrice: 500,
      );
      final listing = (await firestore.doc('providerProfiles/new-pro').get())
          .data()!;
      expect(listing.containsKey('baseLatitude'), isFalse);
      expect(listing.containsKey('serviceRadiusKm'), isFalse);
      expect(listing['serviceArea'], 'Lanang');
    });
  });

  group('updateProfile', () {
    setUp(() async {
      await firestore.doc('users/p1').set({
        'email': 'pat@example.com',
        'name': 'Pat',
        'role': 'provider',
        'createdAt': DateTime(2026),
      });
      await firestore.doc('providerProfiles/p1').set({
        'name': 'Pat',
        'isAvailable': true,
      });
    });

    test('providers get the same name and photo on their listing', () async {
      const photo = 'https://res.cloudinary.com/demo/image/upload/v1/p.jpg';
      await auth.updateProfile(
        uid: 'p1',
        name: ' Pat Plumbing ',
        phone: '  ',
        photoUrl: photo,
        isProvider: true,
      );
      final user = (await firestore.doc('users/p1').get()).data()!;
      final listing = (await firestore.doc('providerProfiles/p1').get())
          .data()!;
      expect(user['name'], 'Pat Plumbing');
      expect(user['phone'], isNull);
      expect(user['photoUrl'], photo);
      expect(listing['name'], 'Pat Plumbing');
      expect(listing['photoUrl'], photo);
    });

    test('rejects an empty name', () async {
      await expectLater(
        () => auth.updateProfile(uid: 'p1', name: '   '),
        throwsArgumentError,
      );
    });

    test('clears a removed photo and phone', () async {
      await auth.updateProfile(
        uid: 'p1',
        name: 'Pat',
        phone: '0917',
        photoUrl: 'https://res.cloudinary.com/demo/image/upload/v1/p.jpg',
        isProvider: true,
      );
      await auth.updateProfile(uid: 'p1', name: 'Pat', isProvider: true);
      final user = (await firestore.doc('users/p1').get()).data()!;
      final listing = (await firestore.doc('providerProfiles/p1').get())
          .data()!;
      expect(user['photoUrl'], isNull);
      expect(user['phone'], isNull);
      expect(listing['photoUrl'], isNull);
    });

    test('customers only update their own profile', () async {
      await auth.updateProfile(uid: 'p1', name: 'Pat', photoUrl: null);
      final listing = (await firestore.doc('providerProfiles/p1').get())
          .data()!;
      expect(listing.containsKey('photoUrl'), isFalse);
    });
  });

  group('deleteUserData', () {
    AppUser person(String id, UserRole role) =>
        AppUser(id: id, email: '$id@example.com', name: id, role: role);

    Future<void> job(String id, Map<String, dynamic> data) =>
        firestore.doc('serviceRequests/$id').set({
          'customerUid': 'c1',
          'status': 'requested',
          'paymentStatus': 'unpaid',
          ...data,
        });

    setUp(() async {
      await firestore.doc('users/c1').set({'name': 'c1', 'role': 'customer'});
      await firestore.doc('users/p1').set({'name': 'p1', 'role': 'provider'});
      await firestore.doc('providerProfiles/p1').set({'name': 'p1'});
    });

    test('refuses while a job is active or unpaid', () async {
      await job('active', {'status': 'on_the_way', 'providerUid': 'p1'});
      await expectLater(
        () => auth.deleteUserData(person('c1', UserRole.customer)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('active jobs'),
          ),
        ),
      );
      await expectLater(
        () => auth.deleteUserData(person('p1', UserRole.provider)),
        throwsStateError,
      );
      expect((await firestore.doc('users/c1').get()).exists, isTrue);

      await job('active', {
        'status': 'completed',
        'providerUid': 'p1',
        'paymentStatus': 'pending_provider_confirmation',
      });
      await expectLater(
        () => auth.deleteUserData(person('c1', UserRole.customer)),
        throwsStateError,
      );
    });

    test('a customer: open jobs cancelled, profile removed', () async {
      await job('open', {'status': 'quoted'});
      await job('done', {
        'status': 'completed',
        'providerUid': 'p1',
        'paymentStatus': 'paid',
      });
      await auth.deleteUserData(person('c1', UserRole.customer));
      final open = (await firestore.doc('serviceRequests/open').get()).data()!;
      expect(open['status'], 'cancelled');
      expect(open['cancelReason'], 'The customer deleted their account.');
      expect(
        (await firestore.doc('serviceRequests/done').get()).data()!['status'],
        'completed',
      );
      expect((await firestore.doc('users/c1').get()).exists, isFalse);
    });

    test('a provider: listing and profile removed', () async {
      await auth.deleteUserData(person('p1', UserRole.provider));
      expect(
        (await firestore.doc('providerProfiles/p1').get()).exists,
        isFalse,
      );
      expect((await firestore.doc('users/p1').get()).exists, isFalse);
    });
  });
}

/// Creates logins with a fixed uid.
class _SignUpAuth implements FirebaseAuth {
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async => _Credential(_FakeUser('new-pro', email: email));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credential implements UserCredential {
  _Credential(this.user);

  @override
  final User user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
