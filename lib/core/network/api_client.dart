import 'package:dio/dio.dart';

import 'auth_session.dart';

enum AuthRefreshResult { refreshed, expired, unavailable }

/// A shared HTTP client and a single refresh transaction for all modules.
/// Browser cookie sessions are intentionally NOT used by the native app.
class ApiClient {
  ApiClient._internal() {
    dio = Dio(defaultOptions());
    final refreshDio = Dio(defaultOptions());

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        omitContentTypeForBodylessDelete(options);
        if (!_isMobileAuthPath(options.path)) {
          final token = await AuthSession.instance.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode != 401 ||
            _isMobileAuthPath(error.requestOptions.path)) {
          handler.next(error);
          return;
        }

        final options = error.requestOptions;
        final failedToken = _bearerToken(options.headers['Authorization']);
        if (failedToken == null) {
          handler.next(error);
          return;
        }

        try {
          if (options.extra['authRetried'] == true) {
            await AuthSession.instance.expireIfCurrent(failedToken);
            handler.next(error);
            return;
          }

          // Another request may already have rotated the token. Retry with
          // its replacement rather than consuming the rotating refresh twice.
          final current = await AuthSession.instance.getAccessToken();
          if (current != null && current != failedToken) {
            handler.resolve(await _retry(options));
            return;
          }

          final result = await _refreshSingleFlight(refreshDio);
          if (result == AuthRefreshResult.refreshed) {
            handler.resolve(await _retry(options));
            return;
          }
          if (result == AuthRefreshResult.expired) {
            await AuthSession.instance.expireIfCurrent(failedToken);
          }
          // Network/server failures are NOT proof of an expired session.
          handler.next(error);
        } on DioException catch (retryError) {
          handler.reject(retryError);
        } catch (_) {
          // Keep the original typed HTTP failure if secure storage fails.
          handler.next(error);
        }
      },
    ));
    _refreshClient = refreshDio;
  }

  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  late final Dio _refreshClient;
  static Future<AuthRefreshResult>? _pendingRefresh;

  static const String baseUrl = String.fromEnvironment(
    'COLLAB_API_BASE_URL',
    defaultValue: 'https://collaboration.gtexshop.ge/api/v1',
  );

  static bool _isMobileAuthPath(String path) =>
      path.startsWith('/auth/mobile/');

  static String? _bearerToken(dynamic header) {
    if (header is! String || !header.startsWith('Bearer ')) return null;
    return header.substring(7);
  }

  static void omitContentTypeForBodylessDelete(RequestOptions options) {
    if (options.method.toUpperCase() != 'DELETE' || options.data != null) {
      return;
    }
    options.headers.removeWhere(
      (key, _) => key.toLowerCase() == Headers.contentTypeHeader,
    );
    options.contentType = null;
  }

  static BaseOptions defaultOptions() => BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      );

  /// Also used at startup when an access token is absent but a refresh token
  /// is stored. Only a definitive invalid credential ends the session.
  Future<AuthRefreshResult> refreshSession() =>
      _refreshSingleFlight(_refreshClient);

  Future<AuthRefreshResult> _refreshSingleFlight(Dio client) {
    final pending = _pendingRefresh;
    if (pending != null) return pending;
    final running = _performRefresh(client);
    _pendingRefresh = running;
    // _performRefresh catches its own failures; this completion cannot throw.
    running.then((_) {
      if (identical(_pendingRefresh, running)) _pendingRefresh = null;
    });
    return running;
  }

  Future<AuthRefreshResult> _performRefresh(Dio client) async {
    try {
      final session = AuthSession.instance;
      final priorRefresh = await session.getRefreshToken();
      if (priorRefresh == null || priorRefresh.isEmpty) {
        return AuthRefreshResult.expired;
      }
      final generation = session.generation;

      final response = await client.post<dynamic>(
        '/auth/mobile/refresh',
        data: {'refreshToken': priorRefresh},
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        return AuthRefreshResult.unavailable;
      }
      final data = body['data'] as Map;
      final newAccess = data['accessToken'];
      final newRefresh = data['refreshToken'];
      if (newAccess is! String || newRefresh is! String ||
          newAccess.isEmpty || newRefresh.isEmpty) {
        return AuthRefreshResult.unavailable;
      }
      final saved = await session.saveRotation(
        previousRefreshToken: priorRefresh,
        generation: generation,
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      return saved ? AuthRefreshResult.refreshed : AuthRefreshResult.expired;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // Invalid/consumed credentials are final. Server overload, 5xx,
      // connection loss and timeouts are transient, never forced logout.
      if (status == 400 || status == 401 || status == 403) {
        return AuthRefreshResult.expired;
      }
      return AuthRefreshResult.unavailable;
    } catch (_) {
      return AuthRefreshResult.unavailable;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions previous) async {
    final data = previous.data is FormData
        ? (previous.data as FormData).clone()
        : previous.data;
    final headers = Map<String, dynamic>.from(previous.headers);
    headers.removeWhere((key, _) =>
        key.toLowerCase() == 'authorization' ||
        (data is FormData && key.toLowerCase() == Headers.contentTypeHeader));

    final retry = previous.copyWith(
      data: data,
      headers: headers,
      extra: {...previous.extra, 'authRetried': true},
    );
    if (data is FormData) retry.contentType = null;
    return dio.fetch<dynamic>(retry);
  }
}
