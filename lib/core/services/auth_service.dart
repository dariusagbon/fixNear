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

    await batch.commit();

    return credential;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<AppUser?> getUserProfile(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }

    return AppUser.fromMap(snapshot.data()!, snapshot.id);
  }

  /// Updates the editable fields of a user's profile. Firestore rules only
  /// allow a user to change their own name, phone and photo.
  Future<void> updateProfile({
    required String uid,
    required String name,
    String? phone,
    String? photoUrl,
  }) async {
    final trimmedPhone = phone?.trim();
    await _firestore.collection('users').doc(uid).update({
      'name': name.trim(),
      'phone': trimmedPhone == null || trimmedPhone.isEmpty
          ? null
          : trimmedPhone,
      'photoUrl': photoUrl,
    });
  }

  Stream<AppUser?> userProfileChanges(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? null : AppUser.fromMap(data, snapshot.id);
    });
  }
}
