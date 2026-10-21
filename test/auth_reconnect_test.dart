import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/network/api_client.dart';
import 'package:gtex_collab_app/core/network/auth_session.dart';
import 'package:gtex_collab_app/features/auth/data/auth_service.dart';

/// A fake transport, not an interceptor. Dio's real request/response/error
/// pipeline therefore handles HTTP 401/404 exactly as it does on a device.
class _ConnectivityBackend implements HttpClientAdapter {
  bool online = false;
  bool mobileRoutesInstalled = true;
  bool credentialsAccepted = true;
  int refreshRequests = 0;
  int loginRequests = 0;
  String validAccess = 'access-updated';
  String validRefresh = 'refresh-original';

  void attach(Dio api, Dio refresh) {
    api.httpClientAdapter = this;
    refresh.httpClientAdapter = this;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!online) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Simulated disconnection',
      );
    }

    if (options.path == '/auth/mobile/login') {
      loginRequests++;
      if (!mobileRoutesInstalled) return _error(404);
      if (!credentialsAccepted) return _error(401);
      validAccess = 'access-from-login';
      validRefresh = 'refresh-from-login';
      return _ok({
        'accessToken': validAccess,
        'refreshToken': validRefresh,
        'user': {'id': 'employee-1'},
      });
    }
    if (options.path == '/auth/mobile/logout') {
      return _ok(null);
    }
    if (options.path == '/auth/me') {
      final authorization = options.headers['Authorization'];
      if (authorization != 'Bearer $validAccess') return _error(401);
      return _ok({'id': 'employee-1'});
    }
    if (options.path == '/auth/mobile/refresh') {
      refreshRequests++;
      if (!mobileRoutesInstalled) return _error(404);
      final body = options.data;
      if (body is! Map || body['refreshToken'] != validRefresh) {
        return _error(401);
      }
      validRefresh = 'refresh-rotated-$refreshRequests';
      validAccess = 'access-refreshed-$refreshRequests';
      return _ok({
        'accessToken': validAccess,
        'refreshToken': validRefresh,
        'user': {'id': 'employee-1'},
      });
    }
    return _error(404);
  }

  static ResponseBody _ok(Object? data) => _response(
        200,
        {'success': true, 'data': data},
      );

  static ResponseBody _error(int status) => _response(
        status,
        {
          'success': false,
          'error': {'code': 'TEST_$status', 'message': 'Test error'},
        },
      );

  static ResponseBody _response(int status, Map<String, dynamic> data) =>
      ResponseBody.fromString(
        jsonEncode(data),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final session = AuthSession.instance;
  late _ConnectivityBackend backend;
  late AuthService auth;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await session.clear();
    backend = _ConnectivityBackend();

    final apiDio = Dio(ApiClient.defaultOptions());
    final refreshDio = Dio(ApiClient.defaultOptions());
    final api = ApiClient.testing(client: apiDio, refreshClient: refreshDio);
    backend.attach(apiDio, refreshDio);
    auth = AuthService(apiClient: api);
  });

  test('offline startup keeps session, and Retry succeeds when online',
      () async {
    await session.saveLogin(
      accessToken: 'expired-access',
      refreshToken: 'refresh-original',
    );
    backend.online = false;
    expect(await auth.checkSession(), StartupSessionStatus.unavailable);
    expect(await session.getRefreshToken(), 'refresh-original');

    backend.online = true;
    expect(await auth.checkSession(), StartupSessionStatus.authenticated);
    expect(backend.refreshRequests, 1);
    expect(await session.getAccessToken(), 'access-refreshed-1');
    expect(await session.getRefreshToken(), 'refresh-rotated-1');
  });

  test('switch account after offline and sign in again with valid credentials',
      () async {
    await session.saveLogin(
      accessToken: 'expired-access',
      refreshToken: 'refresh-original',
    );
    backend.online = false;
    expect(await auth.checkSession(), StartupSessionStatus.unavailable);
    await auth.logout();
    expect(await session.getRefreshToken(), isNull);

    backend.online = true;
    final user = await auth.login('employee@example.com', 'CorrectPassword!');
    expect(user?['id'], 'employee-1');
    expect(backend.loginRequests, 1);
    expect(await session.getRefreshToken(), 'refresh-from-login');
    expect(await auth.checkSession(), StartupSessionStatus.authenticated);
  });

  test('an outdated backend is not incorrectly reported as lost Internet',
      () async {
    await session.saveLogin(
      accessToken: 'expired-access',
      refreshToken: 'refresh-original',
    );
    backend.online = true;
    backend.mobileRoutesInstalled = false;

    expect(await auth.checkSession(), StartupSessionStatus.updateRequired);
    expect(await session.getRefreshToken(), 'refresh-original');
  });

  test('login distinguishes offline, outdated API and invalid credentials',
      () async {
    backend.online = false;
    await expectLater(
      auth.login('employee@example.com', 'CorrectPassword!'),
      throwsA(predicate((e) =>
          e.toString().contains('დაკავშირება ვერ მოხერხდა'))),
    );
    expect(await session.getRefreshToken(), isNull);

    backend.online = true;
    backend.mobileRoutesInstalled = false;
    await expectLater(
      auth.login('employee@example.com', 'CorrectPassword!'),
      throwsA(predicate((e) => e.toString().contains('განახლებული'))),
    );

    backend.mobileRoutesInstalled = true;
    backend.credentialsAccepted = false;
    await expectLater(
      auth.login('employee@example.com', 'WrongPassword!'),
      throwsA(predicate((e) => e.toString().contains('პაროლი არასწორია'))),
    );
  });

  test('concurrent expired requests consume only one rotating refresh token',
      () async {
    await session.saveLogin(
      accessToken: 'expired-access',
      refreshToken: 'refresh-original',
    );
    backend.online = true;
    final outcomes = await Future.wait([
      auth.checkSession(),
      auth.checkSession(),
      auth.checkSession(),
    ]);
    expect(outcomes, everyElement(StartupSessionStatus.authenticated));
    expect(backend.refreshRequests, 1);
  });

  test('another Retry works after a transient failure without restart',
      () async {
    await session.saveLogin(
      accessToken: 'expired-access',
      refreshToken: 'refresh-original',
    );
    backend.online = false;
    expect(await auth.checkSession(), StartupSessionStatus.unavailable);
    expect(await auth.checkSession(), StartupSessionStatus.unavailable);

    backend.online = true;
    expect(await auth.checkSession(), StartupSessionStatus.authenticated);
    expect(backend.refreshRequests, 1);
  });
}
