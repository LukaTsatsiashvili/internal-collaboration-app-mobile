import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gtex_collab_app/core/network/api_client.dart';
import 'package:gtex_collab_app/core/network/auth_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = AuthSession.instance;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await session.clear();
  });

  test('native credentials are persisted and removed together', () async {
    await session.saveLogin(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    expect(await session.getAccessToken(), 'access-1');
    expect(await session.getRefreshToken(), 'refresh-1');

    await session.clear();
    expect(await session.getAccessToken(), isNull);
    expect(await session.getRefreshToken(), isNull);
  });

  test('rotating tokens requires the current refresh token and generation',
      () async {
    await session.saveLogin(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    final generation = session.generation;
    expect(
      await session.saveRotation(
        previousRefreshToken: 'refresh-1',
        generation: generation,
        accessToken: 'access-2',
        refreshToken: 'refresh-2',
      ),
      isTrue,
    );
    expect(await session.getAccessToken(), 'access-2');
    expect(await session.getRefreshToken(), 'refresh-2');

    expect(
      await session.saveRotation(
        previousRefreshToken: 'refresh-1',
        generation: generation,
        accessToken: 'stale-access',
        refreshToken: 'stale-refresh',
      ),
      isFalse,
    );
    expect(await session.getRefreshToken(), 'refresh-2');
  });

  test('late refresh cannot restore credentials after logout', () async {
    await session.saveLogin(
      accessToken: 'access-old',
      refreshToken: 'refresh-old',
    );
    final oldGeneration = session.generation;
    await session.clear();
    expect(
      await session.saveRotation(
        previousRefreshToken: 'refresh-old',
        generation: oldGeneration,
        accessToken: 'access-resurrected',
        refreshToken: 'refresh-resurrected',
      ),
      isFalse,
    );
    expect(await session.getAccessToken(), isNull);
    expect(await session.getRefreshToken(), isNull);
  });

  test('session expiry is notified once and only for current credentials',
      () async {
    await session.saveLogin(
      accessToken: 'access-current',
      refreshToken: 'refresh-current',
    );
    final baseline = session.expiredRevision.value;
    await session.expireIfCurrent('access-stale');
    expect(session.expiredRevision.value, baseline);
    expect(await session.getAccessToken(), 'access-current');

    await session.expireIfCurrent('access-current');
    expect(session.expiredRevision.value, baseline + 1);
    expect(await session.getAccessToken(), isNull);
    expect(await session.getRefreshToken(), isNull);
    await session.expireIfCurrent('access-current');
    expect(session.expiredRevision.value, baseline + 1);
  });

  test('production login extracts only the rotating auth cookie', () {
    final headers = Headers.fromMap({
      'set-cookie': [
        'theme=dark; Path=/',
        'collab_refresh_token=opaque-rotation-123; Path=/api/v1/auth; '
            'HttpOnly; Secure; SameSite=Strict',
      ],
    });
    expect(ApiClient.refreshTokenFromHeaders(headers), 'opaque-rotation-123');
    expect(
      ApiClient.refreshTokenFromHeaders(
        Headers.fromMap({'set-cookie': ['theme=dark; Path=/']}),
      ),
      isNull,
    );
    expect(
      ApiClient.cookieHeader('opaque-rotation-123'),
      'collab_refresh_token=opaque-rotation-123',
    );
    expect(ApiClient.baseUrl, 'https://collaboration.gtexshop.ge/api/v1');
  });

  test('bodyless DELETE never carries a misleading JSON content type', () {
    final options = RequestOptions(
      path: '/drive/123',
      method: 'DELETE',
      headers: {'content-type': 'application/json'},
    );
    ApiClient.omitContentTypeForBodylessDelete(options);
    expect(
      options.headers.keys.any((key) => key.toLowerCase() == 'content-type'),
      isFalse,
    );
    expect(options.contentType, isNull);
  });
}
