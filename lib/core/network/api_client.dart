import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_session.dart';

enum AuthRefreshResult { refreshed, expired, unavailable, unsupported }

/// Mobile auth endpoints have not been deployed to the chosen API server.
class MobileAuthBackendOutdated implements Exception {
  const MobileAuthBackendOutdated();
}

/// A shared HTTP client and a single refresh transaction for all modules.
/// Browser cookie sessions are intentionally NOT used by the native app.
class ApiClient {
  ApiClient._internal({Dio? client, Dio? refreshClient}) {
    dio = client ?? Dio(defaultOptions());
    final refreshDio = refreshClient ?? Dio(defaultOptions());

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
          if (result == AuthRefreshResult.unsupported) {
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              error: const MobileAuthBackendOutdated(),
            ));
            return;
          }
          if (result == AuthRefreshResult.expired) {
            await AuthSession.instance.expireIfCurrent(failedToken);
            handler.next(error);
            return;
          }
          // The original 401 is only due to an expired *access* token.
          // If refresh is unavailable, report a temporary connection failure
          // rather than confusing modules with an apparent forced sign-out.
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'სესიასთან დაკავშირება დროებით ვერ მოხერხდა. სცადეთ ხელახლა.',
          ));
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

  /// Inject deterministic transports for offline/reconnect regression tests.
  @visibleForTesting
  ApiClient.testing({required Dio client, required Dio refreshClient})
      : this._internal(client: client, refreshClient: refreshClient);

  late final Dio dio;
  late final Dio _refreshClient;
  Future<AuthRefreshResult>? _pendingRefresh;

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
    // Dio stores Content-Type inside headers. Deleting the header is enough.
    // Setting RequestOptions.contentType = null afterwards can trigger a
    // type error inside Dio's case-insensitive header map (5.x).
    options.headers.removeWhere(
      (key, _) => key.toLowerCase() == Headers.contentTypeHeader,
    );
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
      if (status == 404) return AuthRefreshResult.unsupported;
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
    // The cloned multipart body will supply its own boundary. Do not call
    // retry.contentType = null: Dio's header setter is unsafe here.
    return dio.fetch<dynamic>(retry);
  }
}
