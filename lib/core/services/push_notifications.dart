import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// A notification that arrived while the app was open.
class ForegroundNotice {
  const ForegroundNotice({
    required this.title,
    required this.body,
    this.requestId,
  });

  final String title;
  final String body;
  final String? requestId;
}

/// Push-notification plumbing, behind an interface so screens can be tested
/// without Firebase.
abstract interface class PushNotifications {
  /// True when this device has never been asked for notification permission,
  /// so it's worth showing our explanation first.
  Future<bool> canAskPermission();

  /// Shows the system permission prompt. Returns whether it was granted.
  Future<bool> requestPermission();

  /// Saves this device's token under users/{uid}/tokens if permission has
  /// been granted, and keeps it up to date. Never prompts.
  Future<void> registerDevice(String uid);

  /// Removes this device's token. Call before signing out.
  Future<void> unregisterDevice(String uid);

  /// Job IDs from notifications tapped while the app is running.
  Stream<String> get openedJobIds;

  /// The job ID of the notification (or web link) that launched the app.
  /// Returns it once, then null.
  Future<String?> takeInitialJobId();

  /// Notifications that arrive while the app is in the foreground.
  Stream<ForegroundNotice> get foregroundNotices;
}

/// Firebase Cloud Messaging implementation.
///
/// On the web, a VAPID key is required. Pass it at build time with
/// `--dart-define=FCM_VAPID_KEY=...`; without it, web push is skipped.
class FirebasePushNotifications implements PushNotifications {
  FirebasePushNotifications({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  static const _vapidKey = String.fromEnvironment('FCM_VAPID_KEY');

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  StreamSubscription<String>? _refreshSubscription;
  String? _token;
  bool _initialTaken = false;

  bool get _webWithoutKey => kIsWeb && _vapidKey.isEmpty;

  Future<bool> _supported() async {
    if (_webWithoutKey) return false;
    try {
      return await _messaging.isSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> canAskPermission() async {
    if (!await _supported()) return false;
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.notDetermined;
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _supported()) return false;
    final settings = await _messaging.requestPermission();
    return _granted(settings.authorizationStatus);
  }

  bool _granted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  CollectionReference<Map<String, dynamic>> _tokens(String uid) =>
      _firestore.collection('users').doc(uid).collection('tokens');

  String get _platform => kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          _ => 'other',
        };

  Future<void> _saveToken(String uid, String token) async {
    await _tokens(uid).doc(token).set({
      'token': token,
      'platform': _platform,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _token = token;
  }

  @override
  Future<void> registerDevice(String uid) async {
    try {
      if (!await _supported()) return;
      final settings = await _messaging.getNotificationSettings();
      if (!_granted(settings.authorizationStatus)) return;

      // Show foreground messages in-app instead of as system banners on iOS.
      await _messaging.setForegroundNotificationPresentationOptions();

      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? _vapidKey : null,
      );
      if (token == null) return;
      await _saveToken(uid, token);

      await _refreshSubscription?.cancel();
      _refreshSubscription = _messaging.onTokenRefresh.listen((fresh) async {
        final previous = _token;
        await _saveToken(uid, fresh);
        if (previous != null && previous != fresh) {
          await _tokens(uid).doc(previous).delete();
        }
      });
    } catch (error) {
      // Notifications are a convenience; never block the app on them.
      debugPrint('Push registration failed: $error');
    }
  }

  @override
  Future<void> unregisterDevice(String uid) async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    try {
      if (!await _supported()) return;
      final token =
          _token ??
          await _messaging
              .getToken(vapidKey: kIsWeb ? _vapidKey : null)
              .timeout(const Duration(seconds: 5));
      if (token != null) {
        await _tokens(uid)
            .doc(token)
            .delete()
            .timeout(const Duration(seconds: 5));
      }
      await _messaging.deleteToken().timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Push unregistration failed: $error');
    } finally {
      _token = null;
    }
  }

  static String? _jobId(RemoteMessage message) {
    final id = message.data['requestId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  @override
  Stream<String> get openedJobIds => FirebaseMessaging.onMessageOpenedApp
      .map(_jobId)
      .where((id) => id != null)
      .cast<String>();

  @override
  Future<String?> takeInitialJobId() async {
    if (_initialTaken) return null;
    _initialTaken = true;
    if (kIsWeb) {
      // Web notifications open the app at ?job=<id>.
      final id = Uri.base.queryParameters['job'];
      return id != null && id.isNotEmpty ? id : null;
    }
    try {
      final message = await _messaging.getInitialMessage();
      return message == null ? null : _jobId(message);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<ForegroundNotice> get foregroundNotices =>
      FirebaseMessaging.onMessage.map(
        (message) => ForegroundNotice(
          title: message.notification?.title ?? 'FixNear',
          body: message.notification?.body ?? '',
          requestId: _jobId(message),
        ),
      );
}
