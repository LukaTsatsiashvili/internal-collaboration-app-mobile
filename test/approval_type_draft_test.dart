import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/approvals/data/approval_type_draft.dart';

void main() {
  final activeUsers = [
    {'id': 'admin-1', 'status': 'ACTIVE', 'displayName': 'Admin'},
    {'id': 'inactive-1', 'status': 'INACTIVE', 'displayName': 'Inactive'},
  ];

  test('default mobile form equals web default configuration', () {
    final draft = ApprovalTypeDraft();
    draft.name = 'Budget request';
    draft.code = 'budget_request';
    expect(draft.validate(users: activeUsers), isNull);
    final body = draft.toPayload();
    expect(body['code'], 'BUDGET_REQUEST');
    expect(body['formSchema'], {
      'field1': {
        'label': 'Reason',
        'type': 'textarea',
        'required': true,
      },
    });
    expect(body['steps'], [
      {
        'stepNumber': 1,
        'name': 'Manager review',
        'approverRule': 'REQUESTER_MANAGER',
        'approverValue': null,
      },
    ]);
  });

  test('select field sends options and steps have consecutive numbers', () {
    final draft = ApprovalTypeDraft();
    draft.name = 'Approvals';
    draft.code = 'APPROVALS';
    expect(draft.addField(), isTrue);
    final choice = draft.fields.last;
    choice.label = 'Type';
    choice.type = 'select';
    choice.options = ['Option 1', 'Option 2'];
    expect(draft.addStep(), isTrue);
    draft.steps.last.name = 'Finance review';
    draft.steps.last.approverRule = 'USER';
    draft.steps.last.approverValue = 'admin-1';
    expect(draft.validate(users: activeUsers), isNull);
    final body = draft.toPayload();
    expect(body['formSchema'][choice.keyName]['options'],
      ['Option 1', 'Option 2']);
    expect(body['steps'][1]['stepNumber'], 2);
    expect(body['steps'][1]['approverValue'], 'admin-1');
  });

  test('field key format and uniqueness follow backend rules', () {
    final draft = ApprovalTypeDraft()
      ..name = 'Valid name'
      ..code = 'VALID_NAME';
    expect(draft.addField(), isTrue);
    draft.fields.last.label = 'Department';
    draft.fields.last.keyName = 'field1';
    expect(draft.validate(users: activeUsers), contains('unique'));
    draft.fields.last.keyName = '1wrong';
    expect(draft.validate(users: activeUsers), contains('key must begin'));
    draft.fields.last.keyName = 'department';
    expect(draft.validate(users: activeUsers), isNull);
  });

  test('user approvers must be active and valid', () {
    final draft = ApprovalTypeDraft()
      ..name = 'Valid name'
      ..code = 'VALID_NAME';
    draft.steps.first.approverRule = 'USER';
    draft.steps.first.approverValue = 'inactive-1';
    expect(draft.validate(users: activeUsers), contains('active approver'));
    draft.steps.first.approverValue = 'admin-1';
    expect(draft.validate(users: activeUsers), isNull);
  });

  test('enforces the API limits for select options and steps', () {
    final draft = ApprovalTypeDraft()
      ..name = 'Valid name'
      ..code = 'VALID_NAME';
    draft.fields.first.type = 'select';
    draft.fields.first.options = [];
    expect(draft.validate(users: activeUsers), contains('options'));
    draft.fields.first.options = ['First'];
    expect(draft.validate(users: activeUsers), isNull);
    for (var i = 1; i < 20; i++) {
      expect(draft.addStep(), isTrue);
    }
    expect(draft.steps.length, 20);
    expect(draft.addStep(), isFalse);
    expect(draft.validate(users: activeUsers), isNull);
  });
  test('editing a stored type restores its form fields and steps in order', () {
    final draft = ApprovalTypeDraft.fromExisting({
      'name': 'Purchase approval',
      'code': 'PURCHASE',
      'description': 'Buy equipment',
      'formSchema': {
        'amount': {
          'type': 'number', 'label': 'Amount', 'required': true,
        },
        'reason': {
          'type': 'select', 'label': 'Reason', 'required': false,
          'options': ['Office', 'Store'],
        },
      },
      'steps': [
        {'stepNumber': 2, 'name': 'Finance review',
          'approverRule': 'USER', 'approverValue': 'admin-1'},
        {'stepNumber': 1, 'name': 'Manager review',
          'approverRule': 'REQUESTER_MANAGER', 'approverValue': null},
      ],
    });
    expect(draft.fields.map((f) => f.keyName),
        ['amount', 'reason']);
    expect(draft.fields.last.options, ['Office', 'Store']);
    expect(draft.steps.first.name, 'Manager review');
    expect(draft.steps.last.approverRule, 'USER');
    expect(draft.validate(users: activeUsers), isNull);
    final payload = draft.toPayload();
    expect(payload['steps'][0]['stepNumber'], 1);
    expect(payload['steps'][1]['stepNumber'], 2);
    expect(payload['steps'][1]['approverValue'], 'admin-1');
  });

  test('editing older ROLE approver definitions preserves role code', () {
    final draft = ApprovalTypeDraft.fromExisting({
      'name': 'Role approval',
      'code': 'ROLE_APPROVAL',
      'formSchema': {},
      'steps': [
        {'stepNumber': 1, 'name': 'Finance review',
          'approverRule': 'ROLE', 'approverValue': 'FINANCE'},
      ],
    });
    expect(draft.validate(users: activeUsers), isNull);
    expect(draft.toPayload()['steps'][0]['approverRule'], 'ROLE');
    expect(draft.toPayload()['steps'][0]['approverValue'], 'FINANCE');
  });

}
