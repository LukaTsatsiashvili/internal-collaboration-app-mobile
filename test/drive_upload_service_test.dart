import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';

XFile fakeFile(String name, List<int> bytes, {String? mime}) =>
    XFile.fromData(
      Uint8List.fromList(bytes),
      name: name,
      mimeType: mime,
      length: bytes.length,
    );

void main() {
  test('Upload sends original multipart file and links it into Personal',
      () async {
    final requests = <String>[];
    final payloads = <Object?>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add('${options.method} ${options.path}');
        payloads.add(options.data);
        if (options.path == '/files') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: {
              'success': true,
              'data': {
                'id': 'file-object-1',
                'originalName': 'Report.pdf',
              },
            },
          ));
        } else if (options.path == '/drive') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: {
              'success': true,
              'data': {
                'id': 'drive-item-1',
                'kind': 'FILE',
                'name': 'Report.pdf',
                'fileId': 'file-object-1',
              },
            },
          ));
        } else {
          handler.reject(DioException(
            requestOptions: options,
            error: 'Unexpected endpoint',
          ));
        }
      },
    ));

    final service = DriveService(dio: dio);
    final created = await service.uploadDriveFile(
      fakeFile('Report.pdf', [37, 80, 68, 70],
          mime: 'application/pdf'),
      parentId: 'existing-folder-id',
    );

    expect(requests, ['POST /files', 'POST /drive']);
    final multipart = payloads.first as FormData;
    expect(multipart.files.length, 1);
    expect(multipart.files.single.key, 'file');
    expect(multipart.files.single.value.filename, 'Report.pdf');
    expect(multipart.files.single.value.length, 4);
    expect(multipart.files.single.value.contentType.toString(),
        'application/pdf');
    // Verify the actual stream, not just metadata or the requested filename.
    final pieces = await multipart.files.single.value.finalize().toList();
    expect(pieces.expand((part) => part).toList(), [37, 80, 68, 70]);
    expect(payloads.last, {
      'name': 'Report.pdf',
      'fileId': 'file-object-1',
      'parentId': 'existing-folder-id',
    });
    expect(created['id'], 'drive-item-1');
    expect(created['kind'], 'FILE');
  });

  test('Uploads to Personal root without an explicit spaceId', () async {
    final payloads = <Object?>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      payloads.add(options.data);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: options.path == '/files'
            ? {'success': true, 'data': {'id': 'raw-id'}}
            : {
                'success': true,
                'data': {'id': 'drive-id', 'kind': 'FILE'},
              },
      ));
    }));

    await DriveService(dio: dio).uploadDriveFile(
      fakeFile('note.txt', [72, 105], mime: 'text/plain'),
    );
    expect(payloads.last, {
      'name': 'note.txt',
      'fileId': 'raw-id',
      'parentId': null,
    });
  });

  test('Failed Drive link cleans up the unlinked FileObject', () async {
    final requests = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add('${options.method} ${options.path}');
      if (options.path == '/files' && options.method == 'POST') {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 201,
          data: {'success': true, 'data': {'id': 'unlinked-file-id'}},
        ));
      } else if (options.path == '/drive' && options.method == 'POST') {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 409,
            data: {
              'success': false,
              'error': {'message': 'Cannot link this upload'},
            },
          ),
        ));
      } else if (options.path == '/files/unlinked-file-id' &&
          options.method == 'DELETE') {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'success': true, 'data': null},
        ));
      } else {
        handler.reject(DioException(requestOptions: options));
      }
    }));

    await expectLater(
      DriveService(dio: dio).uploadDriveFile(
        fakeFile('hello.txt', [72, 105]),
      ),
      throwsA(predicate((error) =>
          error.toString().contains('Cannot link this upload') &&
          error.toString().contains('HTTP 409'))),
    );
    expect(requests, [
      'POST /files',
      'POST /drive',
      'DELETE /files/unlinked-file-id',
    ]);
  });

  test('Backend upload errors are shown and never create Drive items',
      () async {
    final requests = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.path);
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: 413,
          data: {
            'success': false,
            'error': {
              'code': 'FILE_TOO_LARGE',
              'message': 'Files must be smaller than the server limit',
            },
          },
        ),
      ));
    }));

    await expectLater(
      DriveService(dio: dio).uploadDriveFile(
        fakeFile('large.zip', [1, 2, 3]),
      ),
      throwsA(predicate((error) =>
          error.toString().contains('server limit') &&
          error.toString().contains('HTTP 413'))),
    );
    expect(requests, ['/files']);
  });

  test('Invalid filenames or empty file are rejected before POST', () async {
    final requests = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.path);
      handler.next(options);
    }));
    final service = DriveService(dio: dio);
    await expectLater(
      service.uploadDriveFile(fakeFile('not/allowed.txt', [1])),
      throwsFormatException,
    );
    await expectLater(
      service.uploadDriveFile(fakeFile('empty.txt', [])),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
}
