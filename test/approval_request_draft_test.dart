import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/approvals/data/approval_request_draft.dart';

void main() {
  final schema = <String, dynamic>{
    'reason': {'label': 'Reason', 'type': 'textarea', 'required': true},
    'amount': {'label': 'Amount', 'type': 'number', 'required': false},
    'choice': {
      'label': 'Choice', 'type': 'select', 'required': true,
      'options': ['A', 'B'],
    },
    'effectiveDate': {'label': 'Effective date', 'type': 'date',
      'required': false},
    'confirm': {'label': 'Confirm', 'type': 'checkbox',
      'required': false},
  };

  test('draft permits missing required fields but submit rejects them', () {
    final draft = ApprovalRequestDraft()..selectType('type-1')..title='My request';
    expect(draft.validate(schema, submit: false), isNull);
    expect(draft.validate(schema, submit: true), 'Reason is required.');
    draft.values['reason'] = 'Please approve';
    expect(draft.validate(schema, submit: true), 'Choice is required.');
    draft.values['choice'] = 'A';
    expect(draft.validate(schema, submit: true), isNull);
  });

  test('numbers serialize as JSON numbers, checkbox as bool', () {
    final draft = ApprovalRequestDraft()..selectType('type-1')..title='My request';
    draft.values.addAll({'reason':'Text', 'choice':'B',
      'amount':'24.50', 'confirm':false});
    expect(draft.validate(schema, submit: true), isNull);
    final result = draft.submittedValues(schema);
    expect(result['amount'], 24.5);
    expect(result['amount'], isA<num>());
    expect(result['confirm'], isFalse);
  });

  test('invalid options, numeric, and dates rejected even for draft', () {
    final draft = ApprovalRequestDraft()..selectType('type-1')..title='My request';
    draft.values['choice'] = 'Missing';
    expect(draft.validate(schema, submit: false), contains('valid option'));
    draft.values.remove('choice');
    draft.values['amount'] = 'oops';
    expect(draft.validate(schema, submit: false), contains('valid number'));
    draft.values.remove('amount');
    draft.values['effectiveDate'] = '2026-02-31';
    expect(draft.validate(schema, submit: false), contains('valid date'));
    draft.values['effectiveDate'] = '2026-02-28';
    expect(draft.validate(schema, submit: false), isNull);
  });

  test('changing type clears stale dynamic field values', () {
    final draft = ApprovalRequestDraft()..selectType('type-1')..title='My request';
    draft.values['reason'] = 'Old form';
    draft.selectType('type-2');
    expect(draft.approvalTypeId, 'type-2');
    expect(draft.values, isEmpty);
    draft.values['unknown'] = 'bad';
    expect(draft.validate(schema, submit: false), contains('Unknown field'));
  });

  test('cannot save a request without selected type and title', () {
    final draft = ApprovalRequestDraft();
    expect(draft.validate(schema, submit: false), contains('type'));
    draft.selectType('type-1');
    expect(draft.validate(schema, submit: false), contains('Title'));
  });
}
