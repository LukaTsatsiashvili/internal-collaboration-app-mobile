import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/drive/data/drive_download.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/screens/drive_screen.dart';

class _DriveWithOnePdf extends DriveService {
  @override
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async =>
      PersonalDriveListing(items: [
        {
          'id': 'item-1',
          'name': 'report.pdf',
          'kind': 'FILE',
          'access': 'OWNER',
          'owner': {'displayName': 'Nino'},
          'file': {
            'id': 'file-1',
            'mimeType': 'application/pdf',
            'sizeBytes': 4,
          },
        },
      ], usedBytes: 4);

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    expect(fileId, 'file-1');
    return Uint8List.fromList([37, 80, 68, 70]);
  }
}

void main() {
  testWidgets('Download opens immediately without a filesystem path snackbar',
      (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DriveScreen(
        service: _DriveWithOnePdf(),
        downloadSaver: (bytes, name) async {
          saves++;
          expect(name, 'report.pdf');
          expect(bytes, [37, 80, 68, 70]);
          return const DriveDownloadResult(saved: true, opened: true);
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(saves, 1);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.textContaining('Saved:'), findsNothing);
    expect(find.textContaining('Downloads/'), findsNothing);
    expect(tester.takeException(), isNull);

    // The success checkmark is transient and reverts to the download icon.
    await tester.pump(const Duration(seconds: 4));
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });

  testWidgets('When a viewer is unavailable, download still succeeds',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DriveScreen(
        service: _DriveWithOnePdf(),
        downloadSaver: (bytes, name) async =>
            const DriveDownloadResult(saved: true, opened: false),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.textContaining('no compatible app'), findsOneWidget);
    expect(find.textContaining('Saved:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
