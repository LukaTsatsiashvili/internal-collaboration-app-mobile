import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/notifications/data/notification_service.dart';

void main() {
  test('read, unread, and read-all POST a valid empty JSON object', () async {
    final captured = <RequestOptions>[];
    final dio = Dio(BaseOptions(
      baseUrl: 'https://example.com/api/v1',
      headers: {Headers.contentTypeHeader: Headers.jsonContentType},
    ));
    // Intercept requests without contacting a real server.
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        captured.add(options);
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: {'success': true},
        ));
      },
    ));
    final service = NotificationService(dio: dio);

    await service.markRead('notification-1');
    await service.markUnread('notification-2');
    await service.markAllRead();

    expect(captured.map((request) => request.path).toList(), [
      '/notifications/notification-1/read',
      '/notifications/notification-2/unread',
      '/notifications/read-all',
    ]);
    for (final request in captured) {
      expect(request.method, 'POST');
      expect(request.contentType, Headers.jsonContentType);
      // With a JSON Content-Type, Fastify rejects an absent body (400).
      // An empty map is serialized as '{}' and is accepted.
      expect(request.data, isA<Map>());
      expect((request.data as Map).isEmpty, isTrue);
    }
  });
}
