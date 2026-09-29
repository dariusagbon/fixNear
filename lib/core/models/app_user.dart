import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { customer, provider }

class AppUser {
  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.phone,
    this.photoUrl,
    this.createdAt,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String id) {
    return AppUser(
      id: id,
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? 'FixNear User',
      role: _parseRole(map['role']),
      phone: map['phone'] as String?,
      photoUrl: map['photoUrl'] as String?,
      createdAt: _parseCreatedAt(map['createdAt']),
    );
  }

  final String id;
  final String email;
  final String name;
  final UserRole role;
  final String? phone;
  final String? photoUrl;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role.name,
      'phone': phone,
      'photoUrl': photoUrl,
      'createdAt': createdAt ?? DateTime.now(),
    };
  }

  static UserRole _parseRole(Object? value) {
    switch (value) {
      case 'provider':
        return UserRole.provider;
      default:
        return UserRole.customer;
    }
  }

  static DateTime? _parseCreatedAt(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
