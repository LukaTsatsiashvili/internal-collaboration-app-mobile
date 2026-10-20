import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/core/theme/app_dropdown_theme.dart';
import 'package:gtex_collab_app/core/widgets/app_modal_elements.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/screens/drive_move_dialog.dart';
import 'package:gtex_collab_app/screens/drive_permissions_dialog.dart';

class _VisualDriveService extends DriveService {
  final savedGrants = <Map<String, dynamic>>[];
  final moves = <String?>[];

  @override
  Future<List<Map<String, dynamic>>> getPeople() async => [
    {'id': 'owner-1', 'displayName': 'Owner', 'status': 'ACTIVE'},
    {'id': 'user-1', 'displayName': 'Luka', 'status': 'ACTIVE'},
    {'id': 'user-2', 'displayName': 'Nino', 'status': 'ACTIVE'},
  ];

  @override
  Future<List<Map<String, dynamic>>> getDepartments() async => [];

  @override
  Future<DriveShares> getShares(String itemId) async => const DriveShares(
    grants: [
      {'userId': 'user-1', 'access': 'VIEWER', 'scope': 'ITEM_ONLY'},
    ],
    permissionMode: 'CUSTOM',
  );

  @override
  Future<void> setShares(String itemId, {
    required List<Map<String, dynamic>> grants,
    String? permissionMode,
  }) async {
    savedGrants.clear();
    savedGrants.addAll(grants);
  }

  @override
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async {
    return PersonalDriveListing(
      usedBytes: 0,
      items: parentId == null
          ? [
              {'id': 'folder-1', 'name': 'Luka',
               'kind': 'FOLDER', 'access': 'OWNER'},
            ]
          : [],
      breadcrumbs: parentId == null
          ? []
          : [{'id': parentId, 'name': 'Luka'}],
    );
  }

  @override
  Future<void> moveItem(String itemId, String? parentId) async {
    moves.add(parentId);
  }
}

Map<String, dynamic> _item({bool folder = false}) => {
  'id': 'item-1',
  'name': folder ? 'Reports' : 'Untitled spreadsheet',
  'kind': folder ? 'FOLDER' : 'FILE',
  'ownerId': 'owner-1',
  'parentId': null,
};

Future<void> _openDialog(
  WidgetTester tester, {
  required Widget Function(_VisualDriveService) build,
  required _VisualDriveService service,
  bool dark = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => build(service),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Permissions matches task modal chrome and shared dropdown',
      (tester) async {
    final service = _VisualDriveService();
    await _openDialog(
      tester,
      service: service,
      dark: true,
      build: (service) =>
          DrivePermissionsDialog(item: _item(folder: true), service: service),
    );

    expect(find.byType(AppModalHeader), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byType(AppSelectDropdown<String>), findsNWidgets(2));
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Include current and future contents'), findsOneWidget);

    final trigger = find.byTooltip('Permission for Luka');
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    expect(find.text('No Access'), findsWidgets);
    expect(find.text('Editor'), findsWidgets);
    expect(find.text('Edit/Delete'), findsWidgets);
    await tester.tap(find.text('Edit/Delete').last);
    await tester.pumpAndSettle();

    // Merely selecting a permission must not send a write request.
    expect(service.savedGrants, isEmpty);

    await tester.tap(find.text('Save permissions'));
    await tester.pumpAndSettle();
    final luka = service.savedGrants.firstWhere(
      (grant) => grant['userId'] == 'user-1',
    );
    expect(luka['access'], 'EDITOR_DELETE');
    expect(luka['scope'], 'ITEM_ONLY');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Move buttons align and folder contents are vertically centered',
      (tester) async {
    final service = _VisualDriveService();
    await _openDialog(
      tester,
      service: service,
      build: (service) => DriveMoveDialog(item: _item(), service: service),
    );

    expect(find.byType(AppModalHeader), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    final primary = find.byType(AppModalPrimaryButton);
    expect(primary, findsOneWidget);
    expect(tester.widget<AppModalPrimaryButton>(primary).onPressed, isNull);

    final folderIcon = find.byIcon(Icons.folder_outlined);
    final folderTitle = find.text('Luka');
    final folderArrow = find.byIcon(Icons.chevron_right_rounded).last;
    expect(
      (tester.getCenter(folderIcon).dy -
          tester.getCenter(folderTitle).dy).abs(),
      lessThan(4),
    );
    expect(
      (tester.getCenter(folderArrow).dy -
          tester.getCenter(folderTitle).dy).abs(),
      lessThan(4),
    );
    expect(
      (tester.getCenter(find.text('Cancel')).dy -
          tester.getCenter(find.text('Move here')).dy).abs(),
      lessThan(4),
    );
    await tester.tap(folderTitle);
    await tester.pumpAndSettle();
    expect(tester.widget<AppModalPrimaryButton>(primary).onPressed, isNotNull);

    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();
    expect(service.moves, ['folder-1']);
    expect(tester.takeException(), isNull);
  });
}
