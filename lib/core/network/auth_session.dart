import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Native credentials are stored in the platform's protected credential store.
/// No refresh token is ever placed in a URL, log, WebView or plain preferences.
class AuthSession {
  AuthSession._();

  static final AuthSession instance = AuthSession._();
  static const _storage = FlutterSecureStorage();

  static const accessTokenKey = 'access_token';
  static const refreshTokenKey = 'mobile_refresh_token';

  /// Incremented only for an authenticated screen whose session was revoked.
  /// The application root owns the single expiration dialog and navigation.
  final ValueNotifier<int> expiredRevision = ValueNotifier<int>(0);
  bool _authenticatedScreenActive = false;
  int _generation = 0;

  Future<String?> getAccessToken() => _storage.read(key: accessTokenKey);
  Future<String?> getRefreshToken() => _storage.read(key: refreshTokenKey);

  void markAuthenticated() => _authenticatedScreenActive = true;

  /// Store the refresh credential first. A process interruption can then be
  /// recovered by refreshing on next launch rather than losing the session.
  Future<void> saveLogin({
    required String accessToken,
    required String refreshToken,
  }) async {
    _generation++;
    await _storage.write(key: refreshTokenKey, value: refreshToken);
    await _storage.write(key: accessTokenKey, value: accessToken);
    _authenticatedScreenActive = true;
  }

  /// Guard against a late refresh reviving a session after logout/new login.
  Future<bool> saveRotation({
    required String previousRefreshToken,
    required int generation,
    required String accessToken,
    required String refreshToken,
  }) async {
    if (_generation != generation ||
        await getRefreshToken() != previousRefreshToken) {
      return false;
    }
    await _storage.write(key: refreshTokenKey, value: refreshToken);
    await _storage.write(key: accessTokenKey, value: accessToken);
    return _generation == generation;
  }

  int get generation => _generation;

  Future<void> clear() async {
    _generation++;
    _authenticatedScreenActive = false;
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
  }

  /// Only invalidate the credentials belonging to the failed request.
  /// Older in-flight requests must never sign out a newly logged-in user.
  Future<void> expireIfCurrent(String? requestAccessToken) async {
    if (requestAccessToken == null ||
        requestAccessToken != await getAccessToken()) {
      return;
    }
    final notify = _authenticatedScreenActive;
    await clear();
    if (notify) expiredRevision.value++;
  }
}
