import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_session.dart';

enum StartupSessionStatus {
  authenticated,
  signedOut,
  expired,
  unavailable,
  updateRequired,
}

/// Native login/refresh/logout: web HttpOnly-cookie authentication is unchanged.
class AuthService {
  AuthService({ApiClient? apiClient, AuthSession? session})
      : _apiClient = apiClient ?? ApiClient(),
        _session = session ?? AuthSession.instance;

  final ApiClient _apiClient;
  final AuthSession _session;

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
      final user = data['user'];
      if (user is! Map) {
        throw const FormatException('Missing authenticated user');
      }
      await _session.saveLogin(accessToken: access, refreshToken: refresh);
      return Map<String, dynamic>.from(user);
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
      if (status == AuthRefreshResult.unsupported) {
        return StartupSessionStatus.updateRequired;
      }
      if (status == AuthRefreshResult.expired) {
        await _session.clear();
        return StartupSessionStatus.expired;
      }
      if (status == AuthRefreshResult.unavailable) {
        return StartupSessionStatus.unavailable;
      }
    }

    try {
      final response = await _loadProfileWithNetworkRetry();
      if (response.statusCode == 200 &&
          response.data is Map &&
          response.data['success'] == true) {
        _session.markAuthenticated();
        return StartupSessionStatus.authenticated;
      }
      return StartupSessionStatus.unavailable;
    } on DioException catch (error) {
      if (error.error is MobileAuthBackendOutdated) {
        return StartupSessionStatus.updateRequired;
      }
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

  /// Only the idempotent session-check GET is repeated after a connection
  /// failure. A login or refresh POST must not be blindly retransmitted.
  Future<Response<dynamic>> _loadProfileWithNetworkRetry() async {
    try {
      return await _apiClient.dio.get<dynamic>('/auth/me');
    } on DioException catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return _apiClient.dio.get<dynamic>('/auth/me');
    }
  }

  static bool _isTransientNetworkError(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => true,
      _ => false,
    };
  }

  /// Logout invalidates the server's *native* session if reachable. Local
  /// credentials are always cleared, even with no network connectivity.
  Future<void> logout() async {
    // Local sign-out must not wait for DNS/HTTP timeouts after network loss.
    // Revoke the captured credential on the server as a bounded best effort.
    final refresh = await _session.getRefreshToken();
    await _session.clear();
    if (refresh == null || refresh.isEmpty) return;
    try {
      await _apiClient.dio.post(
        '/auth/mobile/logout',
        data: {'refreshToken': refresh},
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Offline logout is always local; remote session expires naturally
      // if the best-effort revocation could not reach the backend.
    }
  }

  String _readError(DioException error, String fallback) {
    final status = error.response?.statusCode;
    final apiPath = error.requestOptions.path;
    if (status == 404 && apiPath == '/auth/mobile/login') {
      return 'მობილური ავტორიზაცია ამ სერვერზე ჯერ არ არის განახლებული. '
          'გთხოვთ დაუკავშირდეთ სისტემის ადმინისტრატორს.';
    }
    if (status == 401) {
      return 'ელ-ფოსტა ან პაროლი არასწორია.';
    }
    if (status == 429) {
      return 'შესვლის მცდელობები დროებით შეზღუდულია. '
          'გთხოვთ მოგვიანებით სცადოთ.';
    }
    if (status != null && status >= 500) {
      return 'სერვერზე დროებითი პრობლემა წარმოიშვა. სცადეთ ხელახლა.';
    }
    if (_isTransientNetworkError(error)) {
      final target = Uri.tryParse(ApiClient.baseUrl);
      final isLocal = target?.host == '127.0.0.1' ||
          target?.host == 'localhost';
      if (isLocal) {
        return 'ლოკალურ სერვერთან დაკავშირება ვერ მოხერხდა. '
            'შეამოწმეთ WSL სერვერი და USB/ADB reverse კავშირი.';
      }
      return 'სერვერთან დაკავშირება ვერ მოხერხდა. '
          'შეამოწმეთ ინტერნეტი და სცადეთ ხელახლა.';
    }
    if (error.type == DioExceptionType.badCertificate) {
      return 'სერვერთან უსაფრთხო კავშირის დამყარება ვერ მოხერხდა.';
    }
    final body = error.response?.data;
    final issue = body is Map ? body['error'] : null;
    if (issue is Map && issue['message'] is String) {
      return issue['message'] as String;
    }
    return fallback;
  }
}
