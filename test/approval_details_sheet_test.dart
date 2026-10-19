import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme_extensions.dart';
import 'package:gtex_collab_app/features/approvals/data/approval_service.dart';
import 'package:gtex_collab_app/screens/approval_details_sheet.dart';

class FakeDetailService extends ApprovalService {
  FakeDetailService({this.userId = 'manager', this.status = 'PENDING'});
  final String userId;
  String status;
  int revision = 2;
  String? groupId;
  int readNotifications = 0;
  final decisions = <Map<String, dynamic>>[];
  final submittedComments = <String>[];
  bool cancelled = false;

  @override
  Future<Map<String, dynamic>> getApprovalRequest(String id) async => {
    'id': id, 'title': 'Laptop approval',
    'requesterId': 'employee',
    'requester': {'displayName': 'Employee A'},
    'status': status,
    'revision': revision,
    'currentStepNumber': 1,
    'approvalTypeVersion': 1,
    'approvalType': {'name': 'Purchase', 'formSchema': {}},
    'workflowSnapshot': {
      'type': {'name': 'Purchase', 'version': 2},
      'formSchema': {
        'reason': {'label': 'Reason', 'type': 'text'},
      },
    },
    'data': {'reason': 'For testing'},
    'personalLayout': {'groupId': groupId},
    'steps': [
      {'id': 'step-1', 'stepNumber': 1, 'stepName': 'Manager review',
        'status': status == 'APPROVED' ? 'APPROVED' : 'PENDING',
        'approverId': 'manager',
        'approver': {'displayName': 'Manager A'}},
    ],
    'comments': [
      {'id': 'comment-1', 'content': 'Previous comment',
        'author': {'displayName': 'Employee A'}},
      for (final comment in submittedComments)
        {'id': 'comment-${submittedComments.indexOf(comment)}',
          'content': comment, 'author': {'displayName': userId}},
    ],
    'attachments': [
      {'file': {'id':'file-1',
        'originalName':'screenshot.png', 'sizeBytes': 1024}},
    ],
    'createdAt': '2026-10-19T10:00:00Z',
  };

  @override
  Future<Map<String, dynamic>> getCurrentApprovalUser() async => {
    'id': userId, 'roles': <String>[],
  };

  @override
  Future<List<dynamic>> getApprovalGroups() async => [
    {'id':'group-1','name':'Finance'},
  ];

  @override
  Future<void> markApprovalNotificationsRead(String id) async {
    readNotifications++;
  }

  @override
  Future<void> setApprovalRequestGroup(String id, String? newGroup) async {
    groupId = newGroup;
  }

  @override
  Future<void> decideApproval({
    required String id,
    required int revision,
    required String action,
    String comment = '',
  }) async {
    decisions.add({
      'id': id, 'revision': revision, 'action': action, 'comment': comment,
    });
    status = action == 'APPROVE' ? 'APPROVED'
        : action == 'REJECT' ? 'REJECTED' : 'CHANGES_REQUESTED';
    this.revision++;
  }

  @override
  Future<void> commentOnApproval({
    required String id,
    required String content,
  }) async {
    submittedComments.add(content);
  }

  @override
  Future<void> cancelApproval({
    required String id,
    required int revision,
  }) async {
    cancelled = true;
    status = 'CANCELLED';
    this.revision++;
  }

  @override
  Future<List<int>> downloadApprovalAttachment(String fileId) async =>
      [65,66,67];
}

Future<void> openDetails(WidgetTester tester, FakeDetailService service) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [AppPalette.light]),
    home: Scaffold(body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => showModalBottomSheet<bool>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ApprovalDetailsSheet(
              requestId: 'approval-1',
              service: service,
            ),
          ),
          child: const Text('Open details'),
        ),
      ),
    )),
  ));
  await tester.tap(find.text('Open details'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows backend details and current reviewer controls',
      (tester) async {
    final service = FakeDetailService();
    await openDetails(tester, service);
    expect(find.text('Laptop approval'), findsOneWidget);
    expect(find.text('For testing'), findsOneWidget);
    expect(find.text('Manager review'), findsOneWidget);
    expect(find.text('screenshot.png'), findsOneWidget);
    expect(find.byTooltip('Change personal group'), findsOneWidget);
    expect(find.text('Confirm decision'), findsOneWidget);
    expect(service.readNotifications, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group selection updates only personal layout',
      (tester) async {
    final service = FakeDetailService();
    await openDetails(tester, service);
    await tester.tap(find.byTooltip('Change personal group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finance').last);
    await tester.pumpAndSettle();
    expect(service.groupId, 'group-1');
    expect(find.text('Finance'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approve sends revision and refreshes progress',
      (tester) async {
    final service = FakeDetailService();
    await openDetails(tester, service);
    await tester.ensureVisible(find.text('Confirm decision'));
    await tester.tap(find.text('Confirm decision'));
    await tester.pumpAndSettle();
    expect(service.decisions, [
      {'id': 'approval-1', 'revision': 2,
        'action': 'APPROVE', 'comment': ''},
    ]);
    expect(service.status, 'APPROVED');
    expect(find.text('Confirm decision'), findsNothing);
    expect(find.text('Approved'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requester sees cancel but not review action',
      (tester) async {
    final service = FakeDetailService(userId: 'employee');
    await openDetails(tester, service);
    expect(find.text('Confirm decision'), findsNothing);
    expect(find.text('Cancel request'), findsOneWidget);
    expect(find.text('Add a comment…'), findsOneWidget);
  });
}
