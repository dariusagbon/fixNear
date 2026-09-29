import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> collection(String path) {
    return _firestore.collection(path);
  }

  Future<void> setDocument({
    required String path,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    final ref = _firestore.doc(path);
    await ref.set(data, SetOptions(merge: merge));
  }

  Future<Map<String, dynamic>?> getDocument(String path) async {
    final snapshot = await _firestore.doc(path).get();
    if (!snapshot.exists) {
      return null;
    }
    return snapshot.data();
  }

  Future<List<Map<String, dynamic>>> listDocuments(String collectionPath) async {
    final snapshot = await _firestore.collection(collectionPath).get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Stream<List<Map<String, dynamic>>> streamDocuments(String collectionPath) {
    return _firestore.collection(collectionPath).snapshots().map(
      (snapshot) => snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList(),
    );
  }
}
