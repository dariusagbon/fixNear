import 'package:cloud_firestore/cloud_firestore.dart';

const serviceCategories = [
  'Electrical',
  'Plumbing',
  'Cleaning',
  'Repair',
  'Moving',
  'Automotive',
  'Computer',
  'Handyman',
];

abstract final class RequestStatus {
  static const requested = 'requested';
  static const quoted = 'quoted';
  static const accepted = 'accepted';
  static const onTheWay = 'on_the_way';
  static const arrived = 'arrived';
  static const inProgress = 'in_progress';
  static const providerCompleted = 'provider_completed';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
}

class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.name,
    required this.category,
    required this.serviceArea,
    required this.startingPrice,
    required this.isAvailable,
  });

  factory ProviderProfile.fromMap(Map<String, dynamic> data, String id) {
    return ProviderProfile(
      id: id,
      name: data['name'] as String? ?? 'Service provider',
      category: data['category'] as String? ?? 'Handyman',
      serviceArea: data['serviceArea'] as String? ?? '',
      startingPrice: (data['startingPrice'] as num?)?.toInt() ?? 0,
      isAvailable: data['isAvailable'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String category;
  final String serviceArea;
  final int startingPrice;
  final bool isAvailable;

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    'serviceArea': serviceArea,
    'startingPrice': startingPrice,
    'isAvailable': isAvailable,
  };
}

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.customerUid,
    required this.customerName,
    required this.category,
    required this.description,
    required this.serviceArea,
    required this.status,
    required this.createdAt,
    this.providerUid,
    this.providerName,
    this.scheduledAt,
    this.photoUrls = const [],
    this.quotedPrice,
    this.quoteNote,
    this.paymentStatus = 'unpaid',
    this.declinedProviderUids = const [],
    this.locationLabel,
    this.latitude,
    this.longitude,
  });

  factory ServiceRequest.fromMap(Map<String, dynamic> data, String id) {
    final timestamp = data['createdAt'];
    final scheduledTimestamp = data['scheduledAt'];
    final location = data['location'];
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    return ServiceRequest(
      id: id,
      customerUid: data['customerUid'] as String? ?? '',
      customerName: data['customerName'] as String? ?? 'Customer',
      category: data['category'] as String? ?? 'Service',
      description: data['description'] as String? ?? '',
      serviceArea: data['serviceArea'] as String? ?? '',
      status: data['status'] as String? ?? RequestStatus.requested,
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      providerUid: data['providerUid'] as String?,
      providerName: data['providerName'] as String?,
      scheduledAt: scheduledTimestamp is Timestamp
          ? scheduledTimestamp.toDate()
          : scheduledTimestamp is DateTime
          ? scheduledTimestamp
          : null,
      photoUrls: (data['photoUrls'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      quotedPrice: (data['quotedPrice'] as num?)?.toInt(),
      quoteNote: data['quoteNote'] as String?,
      paymentStatus: data['paymentStatus'] as String? ?? 'unpaid',
      declinedProviderUids:
          (data['declinedProviderUids'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      locationLabel: (data['locationLabel'] as String?) ??
          (location is Map ? location['label'] as String? : null) ??
          data['serviceArea'] as String? ??
          '',
      latitude: latitude is num ? latitude.toDouble() : null,
      longitude: longitude is num ? longitude.toDouble() : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'customerUid': customerUid,
    'customerName': customerName,
    'category': category,
    'description': description,
    'serviceArea': serviceArea,
    'status': status,
    'providerUid': providerUid,
    'providerName': providerName,
    'scheduledAt': scheduledAt,
    'photoUrls': photoUrls,
    'quotedPrice': quotedPrice,
    'quoteNote': quoteNote,
    'paymentStatus': paymentStatus,
    'declinedProviderUids': declinedProviderUids,
    'locationLabel': locationLabel ?? serviceArea,
    'latitude': latitude,
    'longitude': longitude,
  };

  final String id;
  final String customerUid;
  final String customerName;
  final String category;
  final String description;
  final String serviceArea;
  final String status;
  final DateTime createdAt;
  final String? providerUid;
  final String? providerName;
  final DateTime? scheduledAt;
  final List<String> photoUrls;
  final int? quotedPrice;
  final String? quoteNote;
  final String paymentStatus;
  final List<String> declinedProviderUids;
  final String? locationLabel;
  final double? latitude;
  final double? longitude;
}

class ProviderQuote {
  const ProviderQuote({
    required this.providerUid,
    required this.providerName,
    required this.price,
    required this.note,
    required this.createdAt,
    this.status = 'sent',
  });

  factory ProviderQuote.fromMap(Map<String, dynamic> data, String providerUid) {
    final timestamp = data['createdAt'];
    return ProviderQuote(
      providerUid: providerUid,
      providerName: data['providerName'] as String? ?? 'Provider',
      price: (data['price'] as num?)?.toInt() ?? 0,
      note: data['note'] as String? ?? '',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      status: data['status'] as String? ?? 'sent',
    );
  }

  final String providerUid;
  final String providerName;
  final int price;
  final String note;
  final DateTime createdAt;
  final String status;
}

class JobMessage {
  const JobMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  factory JobMessage.fromMap(Map<String, dynamic> data, String id) {
    final timestamp = data['createdAt'];
    return JobMessage(
      id: id,
      senderUid: data['senderUid'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'User',
      text: data['text'] as String? ?? '',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
    );
  }

  final String id;
  final String senderUid;
  final String senderName;
  final String text;
  final DateTime createdAt;
}
  