import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/screens/drive_screen.dart';
import 'package:gtex_collab_app/screens/drive_members_dialog.dart';

class _SharedFake extends DriveService {
  _SharedFake({this.globalAccess = 'MANAGER', this.canCreate = true});
  final String globalAccess;
  final bool canCreate;
  final calls = <String>[];
  final saved = <Map<String, dynamic>>[];
  final groups = <Map<String, dynamic>>[
    {'id': 'shops-id', 'type': 'GROUP', 'name': 'Shops',
     'access': 'MANAGER'},
  ];

  @override
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async {
    calls.add('personal');
    return const PersonalDriveListing(items: [], usedBytes: 0);
  }

  @override
  Future<DriveSpaces> getSpaces() async {
    calls.add('spaces');
    return DriveSpaces(spaces: [
      {'id': 'global-id', 'type': 'GLOBAL', 'name': 'Global',
       'access': globalAccess},
      ...groups,
    ], canCreateGroups: canCreate, canManageGlobal: globalAccess == 'MANAGER');
  }

  @override
  Future<PersonalDriveListing> getSharedListing({
    required String spaceId, String? parentId, String? search,
  }) async {
    calls.add('listing:$spaceId:$parentId');
    if (parentId != null) {
      return PersonalDriveListing(
        items: [{
          'id': 'nested-id', 'name': 'Q4.xlsx',
          'kind': 'FILE', 'access': 'EDITOR',
          'spaceId': spaceId,
          'owner': {'displayName': 'Luka'},
          'file': {'id': 'binary-id',
            'mimeType': 'application/pdf', 'sizeBytes': 20},
        }],
        usedBytes: 20,
        breadcrumbs: [{'id': parentId, 'name': 'Reports'}],
      );
    }
    if (spaceId == 'global-id') {
      return PersonalDriveListing(
        items: [
          {
            'id': 'folder-id', 'name': 'Reports',
            'kind': 'FOLDER', 'access': globalAccess,
            'spaceId': spaceId,
            'owner': {'displayName': 'Luka'},
            'file': null,
          },
          {
            'id': 'file-id', 'name': 'Financials.pdf',
            'kind': 'FILE', 'access': globalAccess,
            'spaceId': spaceId,
            'owner': {'displayName': 'Luka'},
            'file': {'id': 'raw-id',
              'mimeType': 'application/pdf', 'sizeBytes': 20},
          },
        ],
        usedBytes: 20,
      );
    }
    return const PersonalDriveListing(items: [], usedBytes: 0);
  }

  @override
  Future<Map<String, dynamic>> createSharedGroup(String name) async {
    final group = <String, dynamic>{
      'id': 'new-group', 'type': 'GROUP',
      'name': name, 'access': 'MANAGER',
    };
    groups.add(group);
    return group;
  }

  @override
  Future<List<Map<String, dynamic>>> getPeople() async => [
    {'id': 'admin', 'displayName': 'Administrator', 'status': 'ACTIVE',
     'roles': ['SYSTEM_ADMIN']},
    {'id': 'luka', 'displayName': 'Luka', 'status': 'ACTIVE',
     'roles': ['EMPLOYEE']},
    {'id': 'nino', 'displayName': 'Nino', 'status': 'ACTIVE',
     'roles': ['EMPLOYEE']},
  ];

  @override
  Future<DriveSpaceMembers> getSpaceMembers(String spaceId) async {
    calls.add('members:$spaceId');
    return const DriveSpaceMembers(
      members: [
        {'userId': 'admin', 'role': 'MANAGER'},
        {'userId': 'luka', 'role': 'MANAGER'},
      ],
      type: 'GLOBAL', name: 'Global',
    );
  }

  @override
  Future<void> saveSpaceMembers(
    String spaceId, List<Map<String, dynamic>> members,
  ) async {
    saved.clear();
    saved.addAll(members);
    calls.add('save:$spaceId');
  }
}

Future<void> _load(WidgetTester tester, _SharedFake fake,
    {bool dark = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: DriveScreen(service: fake),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('drive-tab-shared')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Global and groups switch listings; Members is below chips',
      (tester) async {
    final fake = _SharedFake();
    await _load(tester, fake, dark: true);

    expect(fake.calls, containsAll(['spaces', 'listing:global-id:null']));
    expect(find.text('Company-wide shared space'), findsOneWidget);
    expect(find.text('FILES & FOLDERS'), findsOneWidget);
    expect(find.text('Financials.pdf'), findsOneWidget);

    final groupChip = find.byKey(const ValueKey('shared-space-shops-id'));
    final membersButton = find.byKey(const ValueKey('shared-members'));
    expect(groupChip, findsOneWidget);
    expect(membersButton, findsOneWidget);
    expect(tester.getRect(membersButton).top,
        greaterThan(tester.getRect(groupChip).bottom));

    await tester.tap(groupChip);
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'listing:shops-id:null');
    expect(find.text('Group workspace'), findsOneWidget);
    expect(find.text('Financials.pdf'), findsNothing);
  });

  testWidgets('Viewer cannot mutate shared data or manage members',
      (tester) async {
    final fake = _SharedFake(globalAccess: 'VIEWER', canCreate: false);
    await _load(tester, fake);
    expect(find.byKey(const ValueKey('shared-members')), findsNothing);
    expect(find.byKey(const ValueKey('shared-add-group')), findsNothing);
    expect(find.text('Upload files'), findsNothing);
    expect(find.byTooltip('Download'), findsOneWidget);
    expect(find.byTooltip('Rename'), findsOneWidget);
    final rename = tester.widget<IconButton>(find.byTooltip('Rename').first);
    expect(rename.onPressed, isNull);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(tester.widget<IconButton>(
        find.byTooltip('Delete').first).onPressed, isNull);
  });

  testWidgets('Shared folder can be browsed and returns breadcrumbs',
      (tester) async {
    final fake = _SharedFake();
    await _load(tester, fake);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'listing:global-id:folder-id');
    expect(find.text('Q4.xlsx'), findsOneWidget);
  });

  testWidgets('Add shared group selects newly created group',
      (tester) async {
    final fake = _SharedFake();
    await _load(tester, fake);
    await tester.tap(find.byKey(const ValueKey('shared-add-group')));
    await tester.pumpAndSettle();
    expect(find.text('New shared group'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Marketing');
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();
    expect(fake.groups.last['name'], 'Marketing');
    expect(fake.calls.last, 'listing:new-group:null');
    expect(find.byKey(const ValueKey('shared-space-new-group')),
        findsOneWidget);
  });

  testWidgets('Members modal searches, saves roles, locks system admin',
      (tester) async {
    final fake = _SharedFake();
    await _load(tester, fake);
    await tester.tap(find.byKey(const ValueKey('shared-members')));
    await tester.pumpAndSettle();
    expect(find.byType(DriveMembersDialog), findsOneWidget);
    expect(find.text('Members · Global'), findsOneWidget);
    expect(find.text('System administrator · Always manager'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Nino');
    await tester.pumpAndSettle();
    expect(find.text('Nino'), findsOneWidget);
    expect(find.text('Luka'), findsNothing);

    await tester.tap(find.byTooltip('Role for Nino'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editor').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save members'));
    await tester.pumpAndSettle();
    expect(fake.saved, contains(
        {'userId': 'nino', 'role': 'EDITOR'}));
    expect(fake.saved, contains(
        {'userId': 'admin', 'role': 'MANAGER'}));
    expect(fake.calls, contains('save:global-id'));
    expect(tester.takeException(), isNull);
  });
}
