import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/marketplace_models.dart';

abstract interface class MarketplaceRepository {
  Stream<List<ProviderProfile>> watchProviders();

  /// A provider's own listing, whether or not they are online.
  Stream<ProviderProfile?> watchProviderProfile(String providerUid);

  /// Takes a provider online (shown to customers) or offline.
  Future<void> setProviderAvailability(String providerUid, bool isAvailable);
  Stream<List<ServiceRequest>> watchCustomerRequests(String customerUid);

  /// A single job, or null if it doesn't exist or can't be read.
  Stream<ServiceRequest?> watchRequest(String requestId);
  Stream<List<ServiceRequest>> watchOpenRequests(String providerUid);
  Stream<List<ServiceRequest>> watchProviderJobs(String providerUid);
  Stream<List<ProviderQuote>> watchQuotes(String requestId);
  Stream<List<JobMessage>> watchMessages(String requestId);
  Future<void> createRequest({
    required String customerUid,
    required String customerName,
    required String category,
    required String description,
    required String serviceArea,
    String? locationLabel,
    double? latitude,
    double? longitude,
    ProviderProfile? provider,
    DateTime? scheduledAt,
    List<String> photoUrls = const [],
  });
  Future<void> cancelRequest(String requestId);
  Future<void> declineRequest(String requestId, String providerUid);
  Future<void> sendQuote({
    required String requestId,
    required String providerUid,
    required String providerName,
    required int price,
    required String note,
  });
  Future<void> acceptQuote(String requestId, ProviderQuote quote);
  Future<void> advanceRequest(String requestId, String status);
  Future<void> confirmCompletion(String requestId, String customerUid);
  Future<void> sendMessage({
    required String requestId,
    required String senderUid,
    required String senderName,
    required String text,
  });
  Future<void> recordCashPayment(String requestId, String customerUid);
  Future<void> confirmCashPayment(String requestId, String providerUid);
}

class FirestoreMarketplaceRepository implements MarketplaceRepository {
  FirestoreMarketplaceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('serviceRequests');

  @override
  Stream<List<ProviderProfile>> watchProviders() {
    return _firestore
        .collection('providerProfiles')
        .where('isAvailable', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProviderProfile.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  @override
  Stream<List<ServiceRequest>> watchCustomerRequests(String customerUid) {
    return _requests
        .where('customerUid', isEqualTo: customerUid)
        .snapshots()
        .map(_mapRequests);
  }

  @override
  Stream<ProviderProfile?> watchProviderProfile(String providerUid) {
    return _firestore
        .collection('providerProfiles')
        .doc(providerUid)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return data == null
              ? null
              : ProviderProfile.fromMap(data, snapshot.id);
        });
  }

  @override
  Future<void> setProviderAvailability(
    String providerUid,
    bool isAvailable,
  ) async {
    await _firestore.collection('providerProfiles').doc(providerUid).update({
      'isAvailable': isAvailable,
    });
  }

  @override
  Stream<ServiceRequest?> watchRequest(String requestId) {
    return _requests.doc(requestId).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? null : ServiceRequest.fromMap(data, snapshot.id);
    });
  }

  @override
  Stream<List<ServiceRequest>> watchOpenRequests(String providerUid) {
    return Stream<List<ServiceRequest>>.multi((controller) {
      List<ServiceRequest>? broadcast;
      List<ServiceRequest>? targeted;

      void emitIfReady() {
        if (broadcast == null || targeted == null) return;
        final combined = <String, ServiceRequest>{
          for (final request in [...broadcast!, ...targeted!])
            if (!request.declinedProviderUids.contains(providerUid))
              request.id: request,
        }.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(combined);
      }

      final broadcastSubscription = _requests
          .where(
            'status',
            whereIn: [RequestStatus.requested, RequestStatus.quoted],
          )
          .where('providerUid', isNull: true)
          .snapshots()
          .listen((snapshot) {
            broadcast = _mapRequests(snapshot);
            emitIfReady();
          }, onError: controller.addError);
      final targetedSubscription = _requests
          .where(
            'status',
            whereIn: [RequestStatus.requested, RequestStatus.quoted],
          )
          .where('providerUid', isEqualTo: providerUid)
          .snapshots()
          .listen((snapshot) {
            targeted = _mapRequests(snapshot);
            emitIfReady();
          }, onError: controller.addError);

      controller.onCancel = () async {
        await broadcastSubscription.cancel();
        await targetedSubscription.cancel();
      };
    });
  }

  @override
  Stream<List<ProviderQuote>> watchQuotes(String requestId) {
    return _requests
        .doc(requestId)
        .collection('quotes')
        .where('status', isEqualTo: 'sent')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProviderQuote.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  @override
  Stream<List<JobMessage>> watchMessages(String requestId) {
    return _requests
        .doc(requestId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => JobMessage.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  @override
  Stream<List<ServiceRequest>> watchProviderJobs(String providerUid) {
    return _requests
        .where('providerUid', isEqualTo: providerUid)
        .snapshots()
        .map(_mapRequests);
  }

  @override
  Future<void> createRequest({
    required String customerUid,
    required String customerName,
    required String category,
    required String description,
    required String serviceArea,
    String? locationLabel,
    double? latitude,
    double? longitude,
    ProviderProfile? provider,
    DateTime? scheduledAt,
    List<String> photoUrls = const [],
  }) async {
    final request = _requests.doc();
    await request.set({
      'customerUid': customerUid,
      'customerName': customerName,
      'category': category,
      'description': description.trim(),
      'serviceArea': serviceArea.trim(),
      'locationLabel': (locationLabel ?? serviceArea).trim(),
      'latitude': latitude,
      'longitude': longitude,
      'providerUid': provider?.id,
      'providerName': provider?.name,
      'status': RequestStatus.requested,
      'scheduledAt': scheduledAt == null
          ? null
          : Timestamp.fromDate(scheduledAt),
      'photoUrls': photoUrls,
      'declinedProviderUids': <String>[],
      'paymentStatus': 'unpaid',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    await _requests.doc(requestId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> declineRequest(String requestId, String providerUid) async {
    await _requests.doc(requestId).update({
      'declinedProviderUids': FieldValue.arrayUnion([providerUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> sendQuote({
    required String requestId,
    required String providerUid,
    required String providerName,
    required int price,
    required String note,
  }) async {
    if (price <= 0) throw ArgumentError.value(price, 'price');
    await _firestore.runTransaction((transaction) async {
      final requestRef = _requests.doc(requestId);
      final snapshot = await transaction.get(requestRef);
      final data = snapshot.data();
      if (!snapshot.exists ||
          ![
            RequestStatus.requested,
            RequestStatus.quoted,
          ].contains(data?['status']) ||
          (data?['providerUid'] != null &&
              data?['providerUid'] != providerUid) ||
          ((data?['declinedProviderUids'] as List<dynamic>? ?? const [])
              .contains(providerUid))) {
        throw StateError('This request is no longer available for a quote.');
      }

      final quoteRef = requestRef.collection('quotes').doc(providerUid);
      transaction.set(quoteRef, {
        'providerUid': providerUid,
        'providerName': providerName,
        'price': price,
        'note': note.trim(),
        'status': 'sent',
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(requestRef, {
        'status': RequestStatus.quoted,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> acceptQuote(String requestId, ProviderQuote quote) async {
    await _firestore.runTransaction((transaction) async {
      final requestRef = _requests.doc(requestId);
      final quoteRef = requestRef.collection('quotes').doc(quote.providerUid);
      final requestSnapshot = await transaction.get(requestRef);
      final quoteSnapshot = await transaction.get(quoteRef);
      final request = requestSnapshot.data();
      final savedQuote = quoteSnapshot.data();
      if (!requestSnapshot.exists ||
          !quoteSnapshot.exists ||
          ![
            RequestStatus.requested,
            RequestStatus.quoted,
          ].contains(request?['status']) ||
          savedQuote?['status'] != 'sent') {
        throw StateError('This quote is no longer available.');
      }

      transaction.update(requestRef, {
        'providerUid': quote.providerUid,
        'providerName': quote.providerName,
        'quotedPrice': quote.price,
        'quoteNote': quote.note,
        'status': RequestStatus.accepted,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(quoteRef, {'status': 'accepted'});
    });
  }

  @override
  Future<void> advanceRequest(String requestId, String status) async {
    const transitions = {
      RequestStatus.accepted: RequestStatus.onTheWay,
      RequestStatus.onTheWay: RequestStatus.arrived,
      RequestStatus.arrived: RequestStatus.inProgress,
      RequestStatus.inProgress: RequestStatus.providerCompleted,
    };
    await _firestore.runTransaction((transaction) async {
      final requestRef = _requests.doc(requestId);
      final snapshot = await transaction.get(requestRef);
      final currentStatus = snapshot.data()?['status'];
      if (!snapshot.exists || transitions[currentStatus] != status) {
        throw StateError('This job cannot move to that status yet.');
      }
      transaction.update(requestRef, {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> confirmCompletion(String requestId, String customerUid) async {
    await _firestore.runTransaction((transaction) async {
      final requestRef = _requests.doc(requestId);
      final snapshot = await transaction.get(requestRef);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data?['customerUid'] != customerUid ||
          data?['status'] != RequestStatus.providerCompleted) {
        throw StateError('This job is not ready for customer confirmation.');
      }
      transaction.update(requestRef, {
        'status': RequestStatus.completed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> sendMessage({
    required String requestId,
    required String senderUid,
    required String senderName,
    required String text,
  }) async {
    final message = text.trim();
    if (message.isEmpty || message.length > 1000) {
      throw ArgumentError.value(
        text,
        'text',
        'Message must be 1 to 1000 characters.',
      );
    }
    await _requests.doc(requestId).collection('messages').add({
      'senderUid': senderUid,
      'senderName': senderName,
      'text': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> recordCashPayment(String requestId, String customerUid) async {
    await _firestore.runTransaction((transaction) async {
      final requestRef = _requests.doc(requestId);
      final snapshot = await transaction.get(requestRef);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data?['customerUid'] != customerUid ||
          data?['status'] != RequestStatus.completed ||
          data?['paymentStatus'] != 'unpaid') {
        throw StateError(
          'This job is not ready for cash payment confirmation.',
        );
      }
      transaction.update(requestRef, {
        'paymentMethod': 'cash',
        'paymentStatus': 'pending_provider_confirmation',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> confirmCashPayment(String requestId, String providerUid) async {
    await _firestore.runTransaction((transaction) async {
      final requestRef = _requests.doc(requestId);
      final snapshot = await transaction.get(requestRef);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data?['providerUid'] != providerUid ||
          data?['status'] != RequestStatus.completed ||
          data?['paymentStatus'] != 'pending_provider_confirmation') {
        throw StateError('Cash payment is not awaiting provider confirmation.');
      }
      transaction.update(requestRef, {
        'paymentStatus': 'paid',
        'paidAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  List<ServiceRequest> _mapRequests(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final requests = snapshot.docs
        .map((doc) => ServiceRequest.fromMap(doc.data(), doc.id))
        .toList();
    requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return requests;
  }
}
