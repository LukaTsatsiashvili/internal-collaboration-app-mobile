import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/screens/drive_screen.dart';

XFile selected(String name) => XFile.fromData(
  Uint8List.fromList([1, 2, 3]),
  name: name,
  mimeType: 'application/octet-stream',
  length: 3,
);

class _UploadService extends DriveService {
  _UploadService({this.failOn});
  final String? failOn;
  final uploads = <String>[];
  final destinations = <String?>[];
  final loadedFolders = <String?>[];
  final records = <Map<String, dynamic>>[
    {
      'id': 'folder-1',
      'name': 'Marketing',
      'kind': 'FOLDER',
      'parentId': null,
      'access': 'OWNER',
      'file': null,
      'owner': {'displayName': 'User'},
    },
  ];

  @override
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async {
    loadedFolders.add(parentId);
    return PersonalDriveListing(
      items: records.where((record) => record['parentId'] == parentId).toList(),
      usedBytes: records.length * 3,
      breadcrumbs: parentId == 'folder-1'
          ? [{'id': 'folder-1', 'name': 'Marketing'}]
          : [],
    );
  }

  @override
  Future<Map<String, dynamic>> uploadDriveFile(
    XFile file, {
    String? parentId,
    String? spaceId,
    void Function(int sent, int total)? onProgress,
  }) async {
    uploads.add(file.name);
    destinations.add(parentId);
    onProgress?.call(3, 3);
    if (file.name == failOn) throw Exception('Server upload rejected the file');
    final created = <String, dynamic>{
      'id': 'upload-${uploads.length}',
      'name': file.name,
      'parentId': parentId,
      'kind': 'FILE',
      'access': 'OWNER',
      'owner': {'displayName': 'User'},
      'file': {
        'id': 'binary-${uploads.length}',
        'mimeType': 'application/octet-stream',
        'sizeBytes': 3,
      },
    };
    records.add(created);
    return created;
  }
}

Future<void> openDrive(
  WidgetTester tester,
  _UploadService service,
  List<XFile> files,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: DriveScreen(
      service: service,
      filePicker: () async => files,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Upload files selects multiple, saves each and refreshes Personal',
      (tester) async {
    final service = _UploadService();
    await openDrive(tester, service, [
      selected('Invoice.pdf'),
      selected('Plan.xlsx'),
    ]);

    await tester.tap(find.text('Upload files'));
    await tester.pumpAndSettle();

    expect(service.uploads, ['Invoice.pdf', 'Plan.xlsx']);
    expect(service.destinations, [null, null]);
    expect(service.loadedFolders, [null, null]);
    expect(service.records.where((item) => item['kind'] == 'FILE').length, 2);
    expect(find.textContaining('2 files uploaded successfully'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Upload from nested Personal folder saves in that folder',
      (tester) async {
    final service = _UploadService();
    await openDrive(tester, service, [selected('From mobile.pdf')]);

    await tester.tap(find.text('Marketing'));
    await tester.pumpAndSettle();

    expect(service.loadedFolders, [null, 'folder-1']);
    await tester.tap(find.text('Upload files'));
    await tester.pumpAndSettle();

    expect(service.uploads, ['From mobile.pdf']);
    expect(service.destinations, ['folder-1']);
    expect(service.records.last['parentId'], 'folder-1');
    expect(service.loadedFolders.last, 'folder-1');
    expect(find.text('From mobile.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Partial success remains visible; first error stops the batch',
      (tester) async {
    final service = _UploadService(failOn: 'Rejected.exe');
    await openDrive(tester, service, [
      selected('Good.txt'),
      selected('Rejected.exe'),
      selected('NeverAttempted.txt'),
    ]);

    await tester.tap(find.text('Upload files'));
    await tester.pumpAndSettle();

    expect(service.uploads, ['Good.txt', 'Rejected.exe']);
    expect(service.records.any((record) => record['name'] == 'Good.txt'), true);
    expect(find.textContaining('1 of 3 files uploaded'), findsOneWidget);
    expect(find.textContaining('Server upload rejected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancelled picker leaves Drive unchanged', (tester) async {
    final service = _UploadService();
    await openDrive(tester, service, []);
    await tester.tap(find.text('Upload files'));
    await tester.pumpAndSettle();

    expect(service.uploads, isEmpty);
    expect(service.loadedFolders, [null]);
    expect(find.text('Upload files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
