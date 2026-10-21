import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/network/api_client.dart';
import 'package:gtex_collab_app/core/network/auth_session.dart';
import 'package:gtex_collab_app/features/auth/data/auth_service.dart';

/// Fake Dio transports model an offline -> online transition without requiring
/// a server, an emulator, or any production credentials.
class _ConnectivityBackend {
  bool online = false;
  bool mobileRoutesInstalled = true;
  int refreshRequests = 0;
  int loginRequests = 0;
  String validAccess = 'access-updated';
  String validRefresh = 'refresh-original';

  void attach(Dio api, Dio refresh) {
    api.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) {
        if (!online) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'Simulated disconnection',
          ));
          return;
        }

        if (options.path == '/auth/mobile/login') {
          loginRequests++;
          if (!mobileRoutesInstalled) {
            _error(options, handler, 404);
            return;
          }
          validAccess = 'access-from-login';
          validRefresh = 'refresh-from-login';
          _ok(options, handler, {
            'accessToken': validAccess,
            'refreshToken': validRefresh,
            'user': {'id': 'employee-1'},
          });
          return;
        }
        if (options.path == '/auth/mobile/logout') {
          _ok(options, handler, null);
          return;
        }
        if (options.path == '/auth/me') {
          final authorization = options.headers['Authorization'];
          if (authorization != 'Bearer $validAccess') {
            _error(options, handler, 401);
            return;
          }
          _ok(options, handler, {'id': 'employee-1'});
          return;
        }
        _error(options, handler, 404);
      }),
    );

    refresh.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (!online) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'Simulated disconnection',
        ));
        return;
      }
      refreshRequests++;
      if (!mobileRoutesInstalled) {
        _error(options, handler, 404);
        return;
      }
      final body = options.data;
      if (options.path != '/auth/mobile/refresh' ||
          body is! Map || body['refreshToken'] != validRefresh) {
        _error(options, handler, 401);
        return;
      }
      validRefresh = 'refresh-rotated-$refreshRequests';
      validAccess = 'access-refreshed-$refreshRequests';
      _ok(options, handler, {
        'accessToken': validAccess,
        'refreshToken': validRefresh,
        'user': {'id': 'employee-1'},
      });
    }));
  }

  static void _ok(
    RequestOptions options,
    RequestInterceptorHandler handler,
    Object? data,
  ) {
    handler.resolve(Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: {'success': true, 'data': data},
    ));
  }

  static void _error(
    RequestOptions options,
    RequestInterceptorHandler handler,
    int status,
  ) {
    handler.reject(DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: status,
        data: {
          'success': false,
          'error': {'code': 'TEST_$status', 'message': 'Test error'},
        },
      ),
    ));
  }
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

  test('offline startup keeps session, and Retry succeeds after connectivity returns',
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

  test('a simultaneous auth refresh remains single-flight', () async {
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
}
