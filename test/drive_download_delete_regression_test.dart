import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/network/api_client.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/features/drive/data/drive_download.dart';

void main() {
  test('Dio DELETE sends no JSON Content-Type and no request body',
      () async {
    final dio = Dio(ApiClient.defaultOptions());
    late RequestOptions captured;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      ApiClient.omitContentTypeForBodylessDelete(options);
      captured = options;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'success': true, 'data': null},
      ));
    }));

    final service = DriveService(dio: dio);
    await service.trashItem('drive-item-123');

    expect(captured.method, 'DELETE');
    expect(captured.path, '/drive/drive-item-123');
    expect(captured.data, isNull);
    expect(captured.contentType, isNull);
    expect(
      captured.headers.keys.any(
        (key) => key.toLowerCase() == Headers.contentTypeHeader,
      ),
      isFalse,
    );
  });

  test('Files and folders both delete by Drive item ID, not file ID',
      () async {
    final ids = <String>[];
    final dio = Dio(ApiClient.defaultOptions());
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      ids.add(options.path);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'success': true, 'data': null},
      ));
    }));

    final service = DriveService(dio: dio);
    await service.trashItem('file-drive-id');
    await service.trashItem('folder-drive-id');

    expect(ids, ['/drive/file-drive-id', '/drive/folder-drive-id']);
  });

  test('Delete reports server permission errors rather than fake success',
      () async {
    final dio = Dio(ApiClient.defaultOptions());
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: 403,
          data: {
            'success': false,
            'error': {
              'code': 'DRIVE_ACCESS_DENIED',
              'message': 'You do not have permission for this file or folder',
            },
          },
        ),
      ));
    }));
    final service = DriveService(dio: dio);

    await expectLater(
      service.trashItem('drive-id'),
      throwsA(
        predicate((error) =>
            error.toString().contains('You do not have permission') &&
            error.toString().contains('HTTP 403')),
      ),
    );
  });

  test('Empty DELETE no longer declares application/json', () {
    final request = RequestOptions(
      path: '/drive/some-id',
      method: 'DELETE',
      headers: {'content-type': 'application/json'},
    );

    ApiClient.omitContentTypeForBodylessDelete(request);
    expect(request.contentType, isNull);
    expect(
      request.headers.keys.any((key) => key.toLowerCase() == 'content-type'),
      isFalse,
    );
    expect(request.data, isNull);
  });

  test('DELETE with a body retains JSON content-type', () {
    final request = RequestOptions(
      path: '/example',
      method: 'DELETE',
      data: {'reason': 'test'},
      headers: {'content-type': 'application/json'},
    );
    ApiClient.omitContentTypeForBodylessDelete(request);
    expect(request.contentType, 'application/json');
    expect(request.data, {'reason': 'test'});
  });

  test('POST remains unaffected by DELETE-specific cleanup', () {
    final request = RequestOptions(
      path: '/drive',
      method: 'POST',
      data: {'name': 'Reports'},
      headers: {'content-type': 'application/json'},
    );
    ApiClient.omitContentTypeForBodylessDelete(request);
    expect(request.contentType, 'application/json');
  });

  test('download completion distinguishes saved from opened', () {
    final savedAndOpened =
        DriveDownloadResult.fromNative({'saved': true, 'opened': true});
    expect(savedAndOpened.saved, isTrue);
    expect(savedAndOpened.opened, isTrue);

    final savedNotOpened =
        DriveDownloadResult.fromNative({'saved': true, 'opened': false});
    expect(savedNotOpened.saved, isTrue);
    expect(savedNotOpened.opened, isFalse);

    final cancelled =
        DriveDownloadResult.fromNative({'saved': false, 'opened': false});
    expect(cancelled.saved, isFalse);
    expect(() => DriveDownloadResult.fromNative(null), throwsFormatException);
  });

  test('download filenames are sanitized but retain their extensions', () {
    expect(DriveDownload.safeFilename('Report 2026.xlsx'), 'Report 2026.xlsx');
    expect(DriveDownload.safeFilename('bad/name.pdf'), 'bad_name.pdf');
    expect(DriveDownload.safeFilename('   '), 'download');
  });
}
