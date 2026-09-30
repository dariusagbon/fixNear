import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixnear/core/models/app_user.dart';
import 'package:fixnear/core/services/auth_service.dart';

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

    test('customers only update their own profile', () async {
      await auth.updateProfile(uid: 'p1', name: 'Pat', photoUrl: null);
      final listing = (await firestore.doc('providerProfiles/p1').get())
          .data()!;
      expect(listing.containsKey('photoUrl'), isFalse);
    });
  });
}

class _NoAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
