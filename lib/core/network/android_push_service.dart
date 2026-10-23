import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_session.dart';

/// Android FCM is notification transport only. The authoritative inbox and
/// access checks remain on the existing production REST API.
class AndroidPushService {
  AndroidPushService._();
  static final AndroidPushService instance = AndroidPushService._();

  final ValueNotifier<String?> tappedNotificationId = ValueNotifier(null);
  StreamSubscription<String>? _tokenUpdates;
  StreamSubscription<RemoteMessage>? _tapUpdates;
  bool _initialized = false;
  bool _active = false;
  Future<void>? _pendingRegistration;

  String? get pendingNotificationId => tappedNotificationId.value;

  String? takePendingNotificationId() {
    final value = tappedNotificationId.value;
    tappedNotificationId.value = null;
    return value;
  }

  /// Called once after Firebase.initializeApp in main(), before runApp.
  Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    _initialized = true;
    _tapUpdates = FirebaseMessaging.onMessageOpenedApp.listen(_onTapped);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _onTapped(initial);
    // While in the foreground the existing Socket.IO subscription refreshes
    // the inbox and chat; no duplicate native notification is displayed.
  }

  void _onTapped(RemoteMessage message) {
    final id = message.data['notificationId'];
    if (id != null && id.isNotEmpty) tappedNotificationId.value = id;
  }

  /// Best-effort registration. Never blocks login or other app screens.
  Future<void> activate() async {
    if (!Platform.isAndroid || !_initialized) return;
    _active = true;
    _tokenUpdates ??= FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (_active) unawaited(_register(token));
    });
    try {
      final permission = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (!_active || permission.authorizationStatus ==
          AuthorizationStatus.denied) return;
      await refreshRegistration();
    } catch (e) {
      debugPrint('Android push permission/registration unavailable: $e');
    }
  }

  Future<void> refreshRegistration() async {
    if (!_active || !Platform.isAndroid) return;
    if (_pendingRegistration != null) return _pendingRegistration!;
    final running = _refresh();
    _pendingRegistration = running;
    try {
      await running;
    } finally {
      if (identical(_pendingRegistration, running)) _pendingRegistration = null;
    }
  }

  Future<void> _refresh() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty && _active) await _register(token);
    } catch (e) {
      debugPrint('Android push token unavailable: $e');
    }
  }

  Future<void> _register(String token) async {
    if (!_active || await AuthSession.instance.getAccessToken() == null) return;
    try {
      await ApiClient().dio.post('/mobile-push/devices', data: {
        'token': token, 'platform': 'ANDROID',
      });
    } on DioException catch (e) {
      // On reconnection the shell calls refreshRegistration again.
      debugPrint('Android push registration failed: ${e.response?.statusCode ?? e.type}');
    } catch (e) {
      debugPrint('Android push registration failed: $e');
    }
  }

  /// Invoked before local credentials are erased on sign-out.
  Future<void> signOut() async {
    if (!Platform.isAndroid || !_initialized) return;
    _active = false;
    await _tokenUpdates?.cancel();
    _tokenUpdates = null;
    tappedNotificationId.value = null;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        // Online: revoke this user's registration. Offline: the server session
        // is revoked/expired and will be excluded from delivery by backend.
        await ApiClient().dio.delete('/mobile-push/devices',
          data: {'token': token}).timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      // Local logout must always succeed even when disconnected.
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<void> androidPushBackgroundHandler(RemoteMessage message) async {
  // The OS displays notification+data messages while in the background.
  // Do not call the protected business API from a background isolate.
}
