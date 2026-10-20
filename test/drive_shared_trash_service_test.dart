import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';

void main() {
  test('Shared With Me uses view and parentId exactly like Web', () async {
    final requests = <Map<String, dynamic>>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add({
        'method': request.method,
        'path': request.path,
        'params': request.queryParameters,
      });
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'success': true,
          'data': [
            {
              'id': 'shared-item',
              'name': 'Shared file.pdf',
              'kind': 'FILE',
              'access': 'VIEWER',
            }
          ],
          'meta': {
            'breadcrumbs': [
              {'id': 'parent', 'name': 'Shared folder'},
            ],
          },
        },
      ));
    }));
    final api = DriveService(dio: dio);
    final listing = await api.getDriveView(
      view: 'shared-with-me',
      parentId: 'parent',
    );
    expect(requests.single, {
      'method': 'GET',
      'path': '/drive',
      'params': {'view': 'shared-with-me', 'parentId': 'parent'},
    });
    expect(listing.items.single['access'], 'VIEWER');
    expect(listing.breadcrumbs.single['name'], 'Shared folder');
  });

  test('Trash uses a flat view and restores without a request body', () async {
    final requests = <Map<String, dynamic>>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add({
        'method': request.method,
        'path': request.path,
        'params': request.queryParameters,
        'body': request.data,
      });
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: request.method == 'GET'
            ? {
                'success': true,
                'data': [
                  {
                    'id': 'deleted-id',
                    'kind': 'FILE',
                    'name': 'Old PDF',
                    'deletedAt': '2026-10-20T10:00:00Z',
                  }
                ],
                'meta': {'breadcrumbs': []},
              }
            : {'success': true, 'data': null},
      ));
    }));
    final api = DriveService(dio: dio);
    final listing = await api.getDriveView(view: 'trash');
    expect(listing.items.single['id'], 'deleted-id');
    await api.restoreItem('deleted-id');
    expect(requests, [
      {
        'method': 'GET',
        'path': '/drive',
        'params': {'view': 'trash'},
        'body': null,
      },
      {
        'method': 'POST',
        'path': '/drive/deleted-id/restore',
        'params': <String, dynamic>{},
        'body': null,
      }
    ]);
  });

  test('Restore surfaces parent-first and permission failures', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.reject(DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {
            'success': false,
            'error': {
              'code': 'RESTORE_PARENT_FIRST',
              'message': 'Restore the parent folder first',
            },
          },
        ),
      ));
    }));
    await expectLater(
      DriveService(dio: dio).restoreItem('nested-deleted'),
      throwsA(predicate((error) =>
          error.toString().contains('Restore the parent folder first') &&
          error.toString().contains('HTTP 409'))),
    );
  });

  test('Unsupported Drive views cannot be queried accidentally', () async {
    final service = DriveService();
    await expectLater(
      service.getDriveView(view: 'shared'),
      throwsArgumentError,
    );
    await expectLater(
      service.getDriveView(view: 'trash', parentId: 'a-folder'),
      throwsArgumentError,
    );
  });
}
