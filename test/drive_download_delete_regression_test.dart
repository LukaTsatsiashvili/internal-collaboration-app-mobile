import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/network/api_client.dart';
import 'package:gtex_collab_app/features/drive/data/drive_download.dart';

void main() {
  test('Empty DELETE no longer declares application/json', () {
    final request = RequestOptions(
      path: '/drive/some-id',
      method: 'DELETE',
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
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
