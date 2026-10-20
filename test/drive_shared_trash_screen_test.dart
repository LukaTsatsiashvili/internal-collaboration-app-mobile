import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/drive/data/drive_download.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/screens/drive_screen.dart';

Map<String, dynamic> _item(
  String id,
  String name, {
  bool folder = false,
  bool deleted = false,
  String? parentId,
}) => {
  'id': id,
  'name': name,
  'kind': folder ? 'FOLDER' : 'FILE',
  'parentId': parentId,
  'access': deleted ? 'OWNER' : 'VIEWER',
  'owner': {'displayName': deleted ? 'Me' : 'Luka'},
  'file': folder ? null : {
    'id': 'file-$id',
    'mimeType': 'application/pdf',
    'sizeBytes': 4,
  },
  'updatedAt': '2026-10-20T08:00:00.000Z',
  if (deleted) 'deletedAt': '2026-10-20T10:00:00.000Z',
};

class _DriveSectionsService extends DriveService {
  final calls = <String>[];
  final restores = <String>[];
  final downloads = <String>[];
  final trash = <Map<String, dynamic>>[
    _item('trashed-file', 'Deleted document.pdf', deleted: true),
    _item('trashed-folder', 'Old folder', folder: true, deleted: true),
  ];

  @override
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async {
    calls.add('personal:$parentId');
    return PersonalDriveListing(items: [
      _item('my-file', 'My document.pdf'),
    ], usedBytes: 4);
  }

  @override
  Future<PersonalDriveListing> getDriveView({
    required String view,
    String? parentId,
  }) async {
    calls.add('$view:$parentId');
    if (view == 'trash') {
      return PersonalDriveListing(
        items: List<Map<String, dynamic>>.from(trash),
        usedBytes: 0,
      );
    }
    return PersonalDriveListing(
      items: parentId == null
          ? [
              _item('shared-folder', 'Team folder', folder: true),
              _item('shared-file', 'Shared presentation.pdf'),
            ]
          : [_item('nested-file', 'Inside folder.pdf',
              parentId: 'shared-folder')],
      usedBytes: 0,
      breadcrumbs: parentId == null ? [] : [
        {'id': 'shared-folder', 'name': 'Team folder'},
      ],
    );
  }

  @override
  Future<DriveSpaces> getSpaces() async {
    calls.add('spaces');
    return const DriveSpaces(
      spaces: [
        {'id': 'global-id', 'name': 'Global', 'type': 'GLOBAL',
         'access': 'VIEWER'},
      ],
      canCreateGroups: false,
      canManageGlobal: false,
    );
  }

  @override
  Future<PersonalDriveListing> getSharedListing({
    required String spaceId,
    String? parentId,
    String? search,
  }) async {
    calls.add('shared:$spaceId:$parentId');
    return const PersonalDriveListing(items: [], usedBytes: 0);
  }

  @override
  Future<Uint8List> downloadFile(String id) async {
    downloads.add(id);
    return Uint8List.fromList([37, 80, 68, 70]);
  }

  @override
  Future<void> restoreItem(String id) async {
    restores.add(id);
    trash.removeWhere((item) => item['id'] == id);
  }
}

Future<void> _pumpDrive(
  WidgetTester tester,
  _DriveSectionsService service, {
  bool dark = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: DriveScreen(
      service: service,
      downloadSaver: (bytes, filename) async =>
          const DriveDownloadResult(saved: true, opened: true),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Read-only tabs hide file tools and reclaim header space',
      (tester) async {
    final service = _DriveSectionsService();
    await _pumpDrive(tester, service);

    const headerKey = ValueKey('drive-persistent-header');
    const listKey = ValueKey('drive-tab-content');
    const sharedMeKey = ValueKey('drive-tab-shared-with-me');
    const trashKey = ValueKey('drive-tab-trash');
    const personalKey = ValueKey('drive-tab-personal');

    final header = find.byKey(headerKey);
    expect(header, findsOneWidget);
    expect(find.byKey(listKey), findsOneWidget);
    expect(find.text('Upload files'), findsOneWidget);
    expect(find.text('Import Excel'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    final fullHeight = tester.getSize(header).height;
    final fullTop = tester.getTopLeft(header);
    final tabs = find.byKey(personalKey);
    final fullTabY = tester.getTopLeft(tabs).dy;
    final initialSearchController =
        tester.widget<TextField>(find.byType(TextField)).controller;

    for (final tab in [sharedMeKey, trashKey]) {
      await tester.tap(find.byKey(tab));
      await tester.pumpAndSettle();

      expect(header, findsOneWidget);
      expect(find.byKey(listKey), findsOneWidget);
      expect(find.text('Drive'), findsOneWidget);
      expect(find.text('Upload files'), findsNothing);
      expect(find.text('Import Excel'), findsNothing);
      expect(find.text('New Spreadsheet'), findsNothing);
      expect(find.text('New Folder'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.getTopLeft(header), fullTop);
      expect(tester.getSize(header).height, lessThan(fullHeight));
      expect(tester.getTopLeft(tabs).dy, lessThan(fullTabY));
    }

    await tester.tap(find.byKey(personalKey));
    await tester.pumpAndSettle();

    expect(tester.getSize(header).height, fullHeight);
    expect(tester.getTopLeft(header), fullTop);
    expect(find.text('Upload files'), findsOneWidget);
    expect(find.text('Import Excel'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller,
        same(initialSearchController));
    expect(service.calls.last, 'personal:null');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shared With Me reads server view and exposes Download only',
      (tester) async {
    final service = _DriveSectionsService();
    await _pumpDrive(tester, service);

    expect(find.text('Upload files'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drive-tab-shared-with-me')));
    await tester.pumpAndSettle();

    expect(service.calls, contains('shared-with-me:null'));
    expect(find.text('Shared presentation.pdf'), findsOneWidget);
    expect(find.text('Team folder'), findsOneWidget);
    expect(find.text('Upload files'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Download'), findsOneWidget);
    // Download is the sole Shared With Me action and must stay at the
    // trailing (right) edge of its card, not near the middle of the row.
    final screenRight = tester.getRect(find.byType(Scaffold)).right;
    final downloadRight = tester.getRect(find.byTooltip('Download')).right;
    expect(screenRight - downloadRight, lessThan(48));
    expect(find.byTooltip('Rename'), findsNothing);
    expect(find.byTooltip('Permissions'), findsNothing);
    expect(find.byTooltip('Move'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Download'));
    await tester.pump();
    expect(service.downloads, ['file-shared-file']);

    await tester.tap(find.text('Team folder'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'shared-with-me:shared-folder');
    expect(find.text('Inside folder.pdf'), findsOneWidget);
  });

  testWidgets('Trash matches screenshot and restores real Drive items',
      (tester) async {
    final service = _DriveSectionsService();
    await _pumpDrive(tester, service, dark: true);

    await tester.tap(find.byKey(const ValueKey('drive-tab-trash')));
    await tester.pumpAndSettle();

    expect(service.calls.last, 'trash:null');
    expect(find.text('Upload files'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Empty Trash'), findsOneWidget);
    final clearButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('drive-empty-trash')),
    );
    expect(clearButton.onPressed, isNull);

    expect(find.textContaining('permanently deleted after 30 days'),
        findsOneWidget);
    expect(find.text('Deleted document.pdf'), findsOneWidget);
    expect(find.text('Old folder'), findsOneWidget);
    expect(find.byTooltip('Restore'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('drive-permanent-delete')),
        findsNWidgets(2));
    expect(find.byTooltip('Download'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.text('2 items in Trash'), findsOneWidget);

    await tester.tap(find.byTooltip('Restore').first);
    await tester.pumpAndSettle();
    expect(service.restores, ['trashed-file']);
    expect(find.text('Deleted document.pdf'), findsNothing);
    expect(find.text('1 item in Trash'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Trash keeps sorting and restores Personal toolbar on return',
      (tester) async {
    final service = _DriveSectionsService();
    await _pumpDrive(tester, service);
    await tester.tap(find.byKey(const ValueKey('drive-tab-trash')));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Old folder'), findsOneWidget);
    expect(find.text('Deleted document.pdf'), findsOneWidget);
    expect(find.text('2 items in Trash'), findsOneWidget);
    await tester.tap(find.text('Sort by date'));
    await tester.pump();
    expect(find.text('Old folder'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('drive-tab-personal')));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'personal:null');
    expect(find.text('My document.pdf'), findsOneWidget);
    expect(find.text('Old folder'), findsNothing);
    expect(find.text('Upload files'), findsOneWidget);
    expect(find.text('Search files and folders'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shared tab loads Global space with Viewer access',
      (tester) async {
    final service = _DriveSectionsService();
    await _pumpDrive(tester, service);
    await tester.tap(find.byKey(const ValueKey('drive-tab-shared')));
    await tester.pumpAndSettle();
    expect(service.calls, ['personal:null', 'spaces',
      'shared:global-id:null']);
    expect(find.text('Company-wide shared space'), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-space-global-id')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('shared-members')), findsNothing);
    expect(find.text('Upload files'), findsOneWidget);
    expect(find.text('No files or folders in this shared space'),
        findsOneWidget);
  });
}
