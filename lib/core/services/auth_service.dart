import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _auth = firebaseAuth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? serviceCategory,
    String? serviceArea,
    int? startingPrice,
  }) async {
    if (role == UserRole.provider &&
        (serviceCategory == null ||
            serviceArea == null ||
            startingPrice == null)) {
      throw ArgumentError('Provider service details are required.');
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final profile = AppUser(
      id: credential.user!.uid,
      email: email,
      name: name,
      role: role,
      createdAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    final userRef = _firestore.collection('users').doc(credential.user!.uid);
    batch.set(userRef, profile.toMap());

    if (role == UserRole.provider) {
      final providerRef = _firestore
          .collection('providerProfiles')
          .doc(credential.user!.uid);
      batch.set(providerRef, {
        'name': name,
        'category': serviceCategory,
        'serviceArea': serviceArea!.trim(),
        'startingPrice': startingPrice,
        'isAvailable': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    try {
      await batch.commit();
    } catch (_) {
      // Without a profile the account can't be used. Remove the login so
      // the person can simply try again, instead of being stuck signed in.
      try {
        await credential.user!.delete();
      } catch (_) {
        // If this fails too, ensureUserProfileExists repairs it at sign-in.
      }
      rethrow;
    }

    return credential;
  }

  /// Repairs an account that has a login but no profile, which happened
  /// when sign-up failed after the login was created. Returns the profile,
  /// creating a minimal one if needed: a provider when their provider
  /// listing exists, otherwise a customer.
  Future<AppUser> ensureUserProfileExists(User user) async {
    final existing = await getUserProfile(user.uid);
    if (existing != null) return existing;

    final providerListing = await _firestore
        .collection('providerProfiles')
        .doc(user.uid)
        .get();
    final displayName = user.displayName?.trim() ?? '';
    final listingName = providerListing.data()?['name'];
    final profile = AppUser(
      id: user.uid,
      email: user.email ?? '',
      name: displayName.isNotEmpty
          ? displayName
          : listingName is String && listingName.trim().isNotEmpty
          ? listingName.trim()
          : 'FixNear User',
      role: providerListing.exists ? UserRole.provider : UserRole.customer,
      createdAt: DateTime.now(),
    );
    await _firestore.collection('users').doc(user.uid).set(profile.toMap());
    return profile;
  }

  /// Updates the editable fields of a user's profile. Firestore rules only
  /// allow a user to change their own name, phone and photo. For providers
  /// the public listing gets the same name and photo, so customers see them.
  Future<void> updateProfile({
    required String uid,
    required String name,
    String? phone,
    String? photoUrl,
    bool isProvider = false,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Name is required.');
    final trimmedPhone = phone?.trim();
    final batch = _firestore.batch()
      ..update(_firestore.collection('users').doc(uid), {
        'name': trimmedName,
        'phone': trimmedPhone == null || trimmedPhone.isEmpty
            ? null
            : trimmedPhone,
        'photoUrl': photoUrl,
      });
    if (isProvider) {
      batch.update(_firestore.collection('providerProfiles').doc(uid), {
        'name': trimmedName,
        'photoUrl': photoUrl,
      });
    }
    await batch.commit();
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Emails a password reset link. Succeeds whether or not an account
  /// exists, so the app never reveals which emails are registered.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-not-found') return;
      rethrow;
    }
  }

  /// Emails a verification link to the signed-in user.
  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Refreshes and returns whether the signed-in user's email is verified.
  Future<bool> reloadEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? true;

  /// Permanently deletes the signed-in account after confirming [password].
  ///
  /// Refuses while the user has an active job. Otherwise cancels their open
  /// requests, removes their provider listing and profile, then the login.
  /// A Cloud Function (cleanUpDeletedUser) removes what the app can't:
  /// tokens on other devices, open quotes and names on past jobs.
  Future<void> deleteAccount({
    required AppUser profile,
    required String password,
    Future<void> Function()? beforeDelete,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != profile.id) {
      throw StateError('Sign in again to delete your account.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email ?? profile.email,
          password: password,
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (const [
        'wrong-password',
        'invalid-credential',
        'user-mismatch',
      ].contains(error.code)) {
        throw StateError('That password is incorrect.');
      }
      rethrow;
    }
    await beforeDelete?.call();
    await deleteUserData(profile);
    await user.delete();
  }

  static const _activeStatuses = [
    'accepted',
    'on_the_way',
    'arrived',
    'in_progress',
    'provider_completed',
  ];

  /// The Firestore part of [deleteAccount], separate so it can be tested.
  Future<void> deleteUserData(AppUser profile) async {
    final requests = _firestore.collection('serviceRequests');
    final mine = await requests
        .where(
          profile.role == UserRole.provider ? 'providerUid' : 'customerUid',
          isEqualTo: profile.id,
        )
        .get();
    final active = mine.docs.where((doc) {
      final data = doc.data();
      return _activeStatuses.contains(data['status']) ||
          (data['status'] == 'completed' && data['paymentStatus'] != 'paid');
    });
    if (active.isNotEmpty) {
      throw StateError(
        'Finish or cancel your active jobs before deleting your account.',
      );
    }

    if (profile.role == UserRole.customer) {
      for (final doc in mine.docs) {
        if (const ['requested', 'quoted'].contains(doc.data()['status'])) {
          await doc.reference.update({
            'status': 'cancelled',
            'cancelledBy': 'customer',
            'cancelReason': 'The customer deleted their account.',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } else {
      await _firestore.collection('providerProfiles').doc(profile.id).delete();
    }
    await _firestore.collection('users').doc(profile.id).delete();
  }

  Future<AppUser?> getUserProfile(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }

    return AppUser.fromMap(snapshot.data()!, snapshot.id);
  }

  Stream<AppUser?> userProfileChanges(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? null : AppUser.fromMap(data, snapshot.id);
    });
  }
}
