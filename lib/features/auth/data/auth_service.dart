import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_session.dart';

enum StartupSessionStatus { authenticated, signedOut, expired, unavailable }

/// Native login/refresh/logout: web HttpOnly-cookie authentication is unchanged.
class AuthService {
  final ApiClient _apiClient = ApiClient();
  final AuthSession _session = AuthSession.instance;

  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await _apiClient.dio.post(
        '/auth/mobile/login',
        data: {'email': email, 'password': password},
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw StateError('Invalid login response');
      }
      final data = body['data'] as Map;
      final access = data['accessToken'];
      final refresh = data['refreshToken'];
      if (access is! String || refresh is! String ||
          access.isEmpty || refresh.isEmpty) {
        throw StateError('Missing native session credentials');
      }
      await _session.saveLogin(accessToken: access, refreshToken: refresh);
      final user = data['user'];
      return user is Map ? Map<String, dynamic>.from(user) : null;
    } on DioException catch (error) {
      throw Exception(_readError(error, 'ავტორიზაცია ვერ მოხერხდა'));
    }
  }

  /// Network outages never turn into an unexplained sign-out. The previous
  /// checkSession() bool conflated server outages with revoked credentials.
  Future<StartupSessionStatus> checkSession() async {
    final access = await _session.getAccessToken();
    final refresh = await _session.getRefreshToken();
    if ((access == null || access.isEmpty) &&
        (refresh == null || refresh.isEmpty)) {
      return StartupSessionStatus.signedOut;
    }

    // One-time migration from the old Flutter version which only saved a
    // short-lived access token and could not possibly refresh it.
    if (refresh == null || refresh.isEmpty) {
      await _session.clear();
      return StartupSessionStatus.signedOut;
    }

    if (access == null || access.isEmpty) {
      final status = await _apiClient.refreshSession();
      if (status == AuthRefreshResult.expired) {
        await _session.clear();
        return StartupSessionStatus.expired;
      }
      if (status == AuthRefreshResult.unavailable) {
        return StartupSessionStatus.unavailable;
      }
    }

    try {
      final response = await _apiClient.dio.get('/auth/me');
      if (response.statusCode == 200 &&
          response.data is Map &&
          response.data['success'] == true) {
        _session.markAuthenticated();
        return StartupSessionStatus.authenticated;
      }
      return StartupSessionStatus.unavailable;
    } on DioException catch (error) {
      // On 401, ApiClient has already attempted the single-flight refresh.
      final remaining = await _session.getRefreshToken();
      if (remaining == null || remaining.isEmpty) {
        return StartupSessionStatus.expired;
      }
      // A retained refresh token after a 401 means that its refresh attempt
      // failed transiently (e.g. no Internet). ApiClient only clears tokens
      // after the backend definitively rejects the refresh credential.
      return StartupSessionStatus.unavailable;
    } catch (_) {
      return StartupSessionStatus.unavailable;
    }
  }

  /// Logout invalidates the server's *native* session if reachable. Local
  /// credentials are always cleared, even with no network connectivity.
  Future<void> logout() async {
    try {
      final refresh = await _session.getRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        await _apiClient.dio.post(
          '/auth/mobile/logout',
          data: {'refreshToken': refresh},
        );
      }
    } catch (_) {
      // No network: protected credentials are still removed immediately.
    } finally {
      await _session.clear();
    }
  }

  String _readError(DioException error, String fallback) {
    final body = error.response?.data;
    final issue = body is Map ? body['error'] : null;
    if (issue is Map && issue['message'] is String) {
      return issue['message'] as String;
    }
    return fallback;
  }
}
