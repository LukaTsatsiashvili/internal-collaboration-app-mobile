import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme_extensions.dart';
import 'package:gtex_collab_app/features/approvals/data/approval_service.dart';
import 'package:gtex_collab_app/screens/approvals_screen.dart';

class FakeApprovalService extends ApprovalService {
  final List<String> createdGroups = [];

  @override
  Future<Map<String, dynamic>> createApprovalGroup({required String name}) async {
    createdGroups.add(name);
    return {'id': 'new-${createdGroups.length}', 'name': name,
      'position': 3000};
  }

  @override
  Future<List<dynamic>> getApprovalRequests({String? status}) async => [
        {
          'id': 'request-1',
          'title': 'Purchase laptop',
          'status': 'PENDING',
          'approvalTypeId': 'type-1',
          'requesterId': 'user-2',
          'requester': {'displayName': 'Employee A'},
          'approvalType': {'name': 'Purchase request'},
          'createdAt': '2026-10-01T10:00:00Z',
          'personalLayout': {'groupId': 'group-1', 'position': 1000},
          'steps': [
            {'stepNumber': 1, 'approverId': 'user-1', 'status': 'PENDING'},
            {'stepNumber': 2, 'approverId': 'user-3', 'status': 'PENDING'},
          ],
        },
        {
          'id': 'request-2',
          'title': 'Vacation request',
          'status': 'APPROVED',
          'approvalTypeId': 'type-2',
          'requesterId': 'user-1',
          'requester': {'displayName': 'Employee B'},
          'approvalType': {'name': 'Vacation'},
          'createdAt': '2026-10-02T10:00:00Z',
          'personalLayout': null,
          'steps': [
            {'stepNumber': 1, 'approverId': 'user-2', 'status': 'APPROVED'},
          ],
        },
      ];

  @override
  Future<List<dynamic>> getApprovalGroups() async => [
        {'id': 'group-1', 'name': 'My reviews', 'position': 1000},
        {'id': 'group-2', 'name': 'Archive', 'position': 2000},
        for (var i = 0; i < createdGroups.length; i++)
          {'id': 'new-${i + 1}', 'name': createdGroups[i],
            'position': 3000 + i},
      ];

  @override
  Future<List<dynamic>> getApprovalTypes() async => [
        {'id': 'type-1', 'name': 'Purchase request'},
        {'id': 'type-2', 'name': 'Vacation'},
      ];

  @override
  Future<String> getCurrentUserId() async => 'user-1';
}

void main() {
  testWidgets('renders existing approval data in Tasks-styled groups',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppPalette.light]),
      home: ApprovalsScreen(service: FakeApprovalService()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Approvals'), findsOneWidget);
    expect(find.text('2 Total'), findsOneWidget);
    expect(find.text('New request'), findsOneWidget);
    expect(find.text('My reviews'), findsOneWidget);
    expect(find.text('Ungrouped'), findsOneWidget);
    expect(find.text('Purchase laptop'), findsOneWidget);
    expect(find.text('Vacation request'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
  });

  testWidgets('quick filters and search are local, without write requests',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppPalette.light]),
      home: ApprovalsScreen(service: FakeApprovalService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Needs my review'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase laptop'), findsOneWidget);
    expect(find.text('Vacation request'), findsNothing);

    await tester.tap(find.text('My requests'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase laptop'), findsNothing);
    expect(find.text('Vacation request'), findsOneWidget);

    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'purchase');
    await tester.pumpAndSettle();
    expect(find.text('Purchase laptop'), findsOneWidget);
    expect(find.text('Vacation request'), findsNothing);
  });
  testWidgets('advanced filter applies status selection and can clear it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppPalette.light]),
      home: ApprovalsScreen(service: FakeApprovalService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter approvals'));
    await tester.pumpAndSettle();
    expect(find.text('Filter approvals'), findsOneWidget);
    expect(find.text('SUBMITTED'), findsOneWidget);
    expect(find.text('Request type'), findsOneWidget);
    expect(find.text('Requester'), findsOneWidget);
    expect(find.text('Personal group'), findsOneWidget);

    await tester.tap(find.text('PENDING'));
    await tester.tap(find.text('Done  ✓'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase laptop'), findsOneWidget);
    expect(find.text('Vacation request'), findsNothing);

    await tester.tap(find.byTooltip('Filter approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.tap(find.text('Done  ✓'));
    await tester.pumpAndSettle();
    expect(find.text('Vacation request'), findsOneWidget);
  });

  testWidgets('sorting includes request type in both directions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppPalette.light]),
      home: ApprovalsScreen(service: FakeApprovalService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sort approvals'));
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsWidgets);
    expect(find.text('Request type · A to Z'), findsOneWidget);
    expect(find.text('Request type · Z to A'), findsOneWidget);
    await tester.tap(find.text('Request type · A to Z'));
    await tester.pumpAndSettle();
    expect(find.text('Type A-Z'), findsOneWidget);
  });

  testWidgets('New group reuses Tasks modal and creates approval group',
      (tester) async {
    final service = FakeApprovalService();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppPalette.light]),
      home: ApprovalsScreen(service: service),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Approval bases'), findsNothing);

    await tester.ensureVisible(find.text('New group'));
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(find.text('Group name'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Team reviews');
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    expect(service.createdGroups, ['Team reviews']);
    expect(find.text('Team reviews'), findsOneWidget);
  });

}
