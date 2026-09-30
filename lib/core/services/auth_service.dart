import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import 'cloudinary_service.dart';

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

  Future<String> updateProfilePhoto({
    required String uid,
    required Uint8List bytes,
    required String fileName,
    String? folder,
  }) async {
    final cloudinary = CloudinaryService();
    final photoUrl = await cloudinary.uploadImage(
      bytes: bytes,
      fileName: fileName,
      folder: folder ?? 'fixnear/profile-photos',
    );

    await _firestore.collection('users').doc(uid).update({'photoUrl': photoUrl});

    final providerRef = _firestore.collection('providerProfiles').doc(uid);
    final providerDoc = await providerRef.get();
    if (providerDoc.exists) {
      await providerRef.update({'photoUrl': photoUrl});
    }

    return photoUrl;
  }

  Future<AppUser?> ensureUserProfileExists(User user) async {
    final existing = await getUserProfile(user.uid);
    if (existing != null) {
      return existing;
    }

    final providerSnapshot = await _firestore
        .collection('providerProfiles')
        .doc(user.uid)
        .get();
    final providerData = providerSnapshot.data();
    final fallbackName =
        (providerData?['name'] as String?) ??
        user.displayName?.trim() ??
        'FixNear User';
    final role = providerData != null ? UserRole.provider : UserRole.customer;

    final profile = AppUser(
      id: user.uid,
      email: user.email ?? '',
      name: fallbackName,
      role: role,
      createdAt: DateTime.now(),
    );

    await _firestore.collection('users').doc(user.uid).set(
      profile.toMap(),
      SetOptions(merge: true),
    );

    if (providerData != null) {
      await _firestore.collection('providerProfiles').doc(user.uid).set(
        {
          'name': fallbackName,
          'photoUrl': profile.photoUrl,
        },
        SetOptions(merge: true),
      );
    }

    return profile;
  }

  Future<void> updateProfile({
    required String uid,
    required String name,
    String? phone,
    String? photoUrl,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Name is required.');
    }

    final updates = {
      'name': trimmedName,
      'phone': phone?.trim().isEmpty ?? true ? null : phone?.trim(),
      'photoUrl': photoUrl,
    }..removeWhere((_, value) => value == null);

    await _firestore.collection('users').doc(uid).update(updates);

    final providerRef = _firestore.collection('providerProfiles').doc(uid);
    final providerDoc = await providerRef.get();
    if (providerDoc.exists) {
      await providerRef.update({
        'name': trimmedName,
        if (photoUrl != null) 'photoUrl': photoUrl,
      });
    }
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

  Stream<AppUser?> userProfileChanges(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? null : AppUser.fromMap(data, snapshot.id);
    });
  }
}
