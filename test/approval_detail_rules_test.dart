import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/approvals/data/approval_detail_rules.dart';

Map<String, dynamic> approval({
  String status = 'PENDING',
  String requester = 'employee',
  String approver = 'manager',
  int revision = 2,
}) => {
  'id': 'request-1',
  'status': status,
  'requesterId': requester,
  'currentStepNumber': 1,
  'revision': revision,
  'approvalTypeVersion': 1,
  'approvalType': {
    'name': 'Live type', 'formSchema': {'current': {'label': 'Current'}},
  },
  'workflowSnapshot': {
    'type': {'name': 'Original type', 'version': 3},
    'formSchema': {'reason': {'type': 'textarea', 'label': 'Reason'}},
  },
  'steps': [
    {'stepNumber': 1, 'status': 'PENDING', 'approverId': approver},
    {'stepNumber': 2, 'status': 'WAITING', 'approverId': 'finance'},
  ],
};

void main() {
  test('only current approver can act, not requester or later approver', () {
    final request = approval();
    expect(ApprovalDetailRules(request: request,
      user: {'id': 'manager'}).canAct, isTrue);
    expect(ApprovalDetailRules(request: request,
      user: {'id': 'employee'}).canAct, isFalse);
    expect(ApprovalDetailRules(request: request,
      user: {'id': 'finance'}).canAct, isFalse);
    request['status'] = 'APPROVED';
    expect(ApprovalDetailRules(request: request,
      user: {'id': 'manager'}).canAct, isFalse);
  });

  test('requester can edit only draft / changes requested; cancellation rules', () {
    for (final state in ['DRAFT', 'CHANGES_REQUESTED']) {
      final rules = ApprovalDetailRules(
        request: approval(status: state), user: {'id': 'employee'});
      expect(rules.canEditAndSubmit, isTrue);
      expect(rules.canCancel, isTrue);
    }
    for (final state in ['APPROVED', 'REJECTED', 'CANCELLED']) {
      final rules = ApprovalDetailRules(
        request: approval(status: state), user: {'id': 'employee'});
      expect(rules.canEditAndSubmit, isFalse);
      expect(rules.canCancel, isFalse);
    }
    final other = ApprovalDetailRules(
      request: approval(status: 'PENDING'), user: {'id': 'outsider'});
    expect(other.canCancel, isFalse);
    expect(other.canComment, isFalse);
  });

  test('comments are allowed to requester, reviewers and system admin', () {
    final request = approval();
    expect(ApprovalDetailRules(request: request,
      user: {'id': 'employee'}).canComment, isTrue);
    expect(ApprovalDetailRules(request: request,
      user: {'id': 'finance'}).canComment, isTrue);
    expect(ApprovalDetailRules(request: request,
      user: {'id': 'admin', 'roles': ['SYSTEM_ADMIN']}).canComment, isTrue);
    expect(ApprovalDetailRules(request: request,
      user: {'id': 'manager'}).canComment, isFalse);
  });

  test('frozen workflow fields and type version take precedence', () {
    final rules = ApprovalDetailRules(
      request: approval(), user: {'id': 'manager'});
    expect(rules.formSchema.keys, ['reason']);
    expect(rules.typeName, 'Original type');
    expect(rules.typeVersion, '3');
    expect(rules.revision, 2);
  });
}
