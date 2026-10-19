import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme_extensions.dart';
import 'package:gtex_collab_app/features/approvals/data/approval_service.dart';
import 'package:gtex_collab_app/screens/request_types_sheet.dart';

class FakeRequestTypeService extends ApprovalService {
  int loads = 0;

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

Future<void> showTypes(WidgetTester tester, FakeRequestTypeService service) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [AppPalette.light]),
    home: Scaffold(body: Builder(
      builder: (context) => Center(child: ElevatedButton(
        onPressed: () => showDialog<void>(
          context: context,
          useSafeArea: true,
          builder: (_) => RequestTypesSheet(service: service),
        ),
        child: const Text('Open types'),
      )),
    )),
  ));
  await tester.tap(find.text('Open types'));
  await tester.pumpAndSettle();
  // Regression: showDialog previously lacked the required Material ancestor.
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
    expect((allPanel.center.dy - screenHeight / 2).abs(), lessThan(40));
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

  testWidgets('compact dialog stays in bounds on a short phone viewport',
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

}
