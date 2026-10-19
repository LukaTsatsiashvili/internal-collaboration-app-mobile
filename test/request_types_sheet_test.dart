import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme_extensions.dart';
import 'package:gtex_collab_app/features/approvals/data/approval_service.dart';
import 'package:gtex_collab_app/screens/request_types_sheet.dart';

class FakeRequestTypeService extends ApprovalService {
  int loads = 0;
  final List<Map<String, dynamic>> created = [];

  @override
  Future<List<dynamic>> getUsersForApprovalSteps() async => [
        {'id': 'user-1', 'displayName': 'Admin', 'status': 'ACTIVE'},
      ];

  @override
  Future<Map<String, dynamic>> createApprovalType(
      Map<String, dynamic> payload) async {
    created.add(payload);
    return {'id': 'created-1', ...payload};
  }

  @override
  Future<List<dynamic>> getManagedApprovalTypes() async {
    loads++;
    return [
      {
        'id': '1', 'name': 'Active request', 'code': 'TST1',
        'status': 'ACTIVE', 'version': 2,
        '_count': {'requests': 3},
        'createdBy': {'displayName': 'System Admin'},
      },
      {
        'id': '2', 'name': 'Inactive request', 'code': 'TST2',
        'status': 'INACTIVE', 'version': 1,
        '_count': {'requests': 1},
        'createdBy': {'displayName': 'System Admin'},
      },
      {
        'id': '3', 'name': 'Draft request', 'code': 'DRFT3',
        'status': 'DRAFT', 'version': 1,
        '_count': {'requests': 0},
        'createdBy': {'displayName': 'System Admin'},
      },
    ];
  }
}

class FakeEditableRequestTypes extends FakeRequestTypeService {
  final changes = <Map<String, dynamic>>[];
  final statuses = <String>[];
  String currentStatus = 'ACTIVE';
  int version = 4;

  @override
  Future<List<dynamic>> getManagedApprovalTypes() async {
    loads++;
    return [
      {
        'id': '1',
        'name': 'Purchase review',
        'code': 'PURCHASE',
        'description': 'Original',
        'status': currentStatus,
        'version': version,
        '_count': {'requests': 2},
        'formSchema': {
          'field1': {
            'label': 'Reason', 'type': 'textarea', 'required': true,
          },
        },
        'steps': [
          {
            'stepNumber': 1, 'name': 'Manager review',
            'approverRule': 'REQUESTER_MANAGER',
            'approverValue': null,
          },
        ],
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> updateApprovalType(
      String id, Map<String, dynamic> payload) async {
    changes.add({'id': id, ...payload});
    version++;
    return {'id': id, 'version': version, ...payload};
  }

  @override
  Future<Map<String, dynamic>> changeApprovalTypeStatus(
      String id, String status) async {
    statuses.add(status);
    currentStatus = status;
    return {'id': id, 'status': status};
  }
}

Future<void> showTypes(WidgetTester tester, FakeRequestTypeService service) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [AppPalette.light]),
    home: Scaffold(body: Builder(
      builder: (context) => Center(child: ElevatedButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => RequestTypesSheet(service: service),
        ),
        child: const Text('Open types'),
      )),
    )),
  ));
  await tester.tap(find.text('Open types'));
  await tester.pumpAndSettle();
  // Regression: Input widgets still need a Material ancestor in bottom sheets.
  expect(tester.takeException(), isNull);
  expect(
    find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(Material),
    ),
    findsWidgets,
  );
}

void main() {
  testWidgets('Request Types shows server records and static action labels',
      (tester) async {
    final service = FakeRequestTypeService();
    await showTypes(tester, service);
    expect(service.loads, 1);
    expect(find.text('Request Types'), findsOneWidget);
    expect(find.text('All Statuses'), findsOneWidget);
    expect(find.text('New type'), findsOneWidget);
    expect(find.text('Active request'), findsOneWidget);
    expect(find.text('Edit'), findsWidgets);
    expect(find.text('Deactivate'), findsWidgets);
    expect(find.textContaining('TST1 · v2 · 3 requests'), findsOneWidget);
  });

  testWidgets('status options include All, Active, Inactive and Draft',
      (tester) async {
    final service = FakeRequestTypeService();
    await showTypes(tester, service);
    await tester.tap(find.byTooltip('Request type status'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(PopupMenuItem<String>, 'All Statuses'),
        findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'Active'),
        findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'Inactive'),
        findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'Draft'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Draft'));
    await tester.pumpAndSettle();
    expect(find.text('Draft request'), findsOneWidget);
    expect(find.text('Active request'), findsNothing);
    expect(find.text('Inactive request'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'DRFT3');
    await tester.pumpAndSettle();
    expect(find.text('Draft request'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'no-such-code');
    await tester.pumpAndSettle();
    expect(find.text('No request types found'), findsOneWidget);
    expect(service.loads, 1); // Search and status filtering are local.
  });
  testWidgets('sheet is inset, adapts height and scrolls after two cards',
      (tester) async {
    final service = FakeRequestTypeService();
    await showTypes(tester, service);
    final panelFinder = find.byKey(
      const ValueKey('request-types-sheet-panel'),
    );
    final listFinder = find.byKey(
      const ValueKey('request-types-cards-list'),
    );

    final screenWidth = tester.view.physicalSize.width /
        tester.view.devicePixelRatio;
    final screenHeight = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;
    final allPanel = tester.getRect(panelFinder);
    final list = tester.getRect(listFinder);
    expect(allPanel.left, greaterThanOrEqualTo(13));
    expect(allPanel.right, lessThanOrEqualTo(screenWidth - 13));
    expect(allPanel.bottom, lessThan(screenHeight));
    expect(screenHeight - allPanel.bottom, lessThan(40));
    expect(list.height, lessThanOrEqualTo(285.1));

    // Cards beyond the initial two remain accessible inside the list.
    await tester.drag(listFinder, const Offset(0, -280));
    await tester.pumpAndSettle();
    expect(find.text('Draft request'), findsOneWidget);

    // Selecting one matching status reduces the sheet's overall height.
    await tester.tap(find.byTooltip('Request type status'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Draft'));
    await tester.pumpAndSettle();
    final oneCardPanel = tester.getRect(panelFinder);
    expect(oneCardPanel.height, lessThan(allPanel.height));
  });

  testWidgets('compact bottom sheet stays in bounds on a short phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeRequestTypeService();
    await showTypes(tester, service);
    final panel = tester.getRect(
        find.byKey(const ValueKey('request-types-sheet-panel')));
    expect(panel.left, greaterThanOrEqualTo(13));
    expect(panel.right, lessThanOrEqualTo(347));
    expect(panel.top, greaterThanOrEqualTo(12));
    expect(panel.bottom, lessThanOrEqualTo(548));
    expect(tester.takeException(), isNull);
  });

  testWidgets('New Type creates backend-compatible data and reloads listing',
      (tester) async {
    final service = FakeRequestTypeService();
    await showTypes(tester, service);
    await tester.tap(find.text('New type'));
    await tester.pumpAndSettle();

    expect(find.text('New approval type'), findsOneWidget);
    expect(find.text('Request form'), findsOneWidget);
    // The approval steps section is further down the scrollable form;
    // its data is also asserted through the submitted payload below.
    await tester.enterText(
      find.byKey(const ValueKey('approval-type-name')),
      'Test Approval',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approval-type-code')),
      'test_approval',
    );
    await tester.tap(find.text('Create approval type'));
    await tester.pumpAndSettle();

    expect(service.created, hasLength(1));
    final payload = service.created.single;
    expect(payload['name'], 'Test Approval');
    expect(payload['code'], 'TEST_APPROVAL');
    expect(payload['formSchema']['field1']['type'], 'textarea');
    expect(payload['formSchema']['field1']['required'], isTrue);
    expect(payload['steps'][0]['approverRule'], 'REQUESTER_MANAGER');
    expect(service.loads, 2);
    expect(find.text('New approval type'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deactivate and activate update the backend status and listing',
      (tester) async {
    final service = FakeEditableRequestTypes();
    await showTypes(tester, service);

    await tester.tap(find.byKey(const ValueKey('toggle-type-1')));
    await tester.pumpAndSettle();
    expect(service.statuses, ['INACTIVE']);
    expect(service.currentStatus, 'INACTIVE');

    await tester.tap(find.byKey(const ValueKey('toggle-type-1')));
    await tester.pumpAndSettle();
    expect(service.statuses, ['INACTIVE', 'ACTIVE']);
    expect(service.loads, 3);
  });

  testWidgets('editing used type keeps code locked and saves a new version',
      (tester) async {
    final service = FakeEditableRequestTypes();
    await showTypes(tester, service);
    await tester.tap(find.byKey(const ValueKey('edit-type-1')));
    await tester.pumpAndSettle();

    expect(find.text('Save new version'), findsOneWidget);
    final code = tester.widget<TextFormField>(
        find.byKey(const ValueKey('approval-type-code')));
    expect(code.enabled, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('approval-type-name')),
      'Updated purchase review',
    );
    await tester.tap(find.text('Save new version'));
    await tester.pumpAndSettle();
    expect(service.changes, hasLength(1));
    expect(service.changes.single['id'], '1');
    expect(service.changes.single['code'], 'PURCHASE');
    expect(service.changes.single['name'], 'Updated purchase review');
    expect(service.changes.single['steps'][0]['stepNumber'], 1);
    expect(service.version, 5);
    expect(service.loads, 2);
    expect(tester.takeException(), isNull);
  });

}
