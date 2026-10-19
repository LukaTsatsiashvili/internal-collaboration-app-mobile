import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/screens/approval_advanced_filters.dart';

void main() {
  final first = {
    'status': 'PENDING',
    'approvalTypeId': 'purchase',
    'requesterId': 'alice',
    'personalLayout': {'groupId': 'finance'},
    'createdAt': '2026-10-12T12:00:00Z',
  };
  final second = {
    'status': 'APPROVED',
    'approvalTypeId': 'leave',
    'requesterId': 'bob',
    'personalLayout': null,
    'createdAt': '2026-10-13T12:00:00Z',
  };

  test('all approval statuses are unfiltered by default', () {
    final filters = ApprovalAdvancedFilters();
    expect(filters.activeCount, 0);
    expect(filters.matches(first), isTrue);
    expect(filters.matches(second), isTrue);
  });

  test('statuses use OR while filter dimensions use AND', () {
    final filters = ApprovalAdvancedFilters(
      statuses: {'PENDING', 'APPROVED'},
      typeIds: {'purchase'},
      requesterIds: {'alice'},
      groupIds: {'finance'},
    );
    expect(filters.matches(first), isTrue);
    expect(filters.matches(second), isFalse);
    filters.typeIds.add('leave');
    expect(filters.matches(second), isFalse);
    filters.requesterIds.add('bob');
    expect(filters.matches(second), isFalse); // group still mismatches
    filters.groupIds.add(ApprovalAdvancedFilters.ungrouped);
    expect(filters.matches(second), isTrue);
  });

  test('Ungrouped works with absent personalLayout', () {
    final filters = ApprovalAdvancedFilters(
      groupIds: {ApprovalAdvancedFilters.ungrouped},
    );
    expect(filters.matches(first), isFalse);
    expect(filters.matches(second), isTrue);
  });

  test('Created from/to dates are inclusive and compared in local days', () {
    final filters = ApprovalAdvancedFilters(
      createdFrom: DateTime(2026, 10, 12),
      createdTo: DateTime(2026, 10, 13),
    );
    expect(filters.matches(first), isTrue);
    expect(filters.matches(second), isTrue);
    filters.createdTo = DateTime(2026, 10, 12);
    expect(filters.matches(second), isFalse);
    filters.createdFrom = DateTime(2026, 10, 13);
    expect(filters.matches(first), isFalse);
  });

  test('draft changes do not mutate the applied filter until saved', () {
    final applied = ApprovalAdvancedFilters(statuses: {'PENDING'});
    final draft = applied.copy();
    draft.statuses.add('APPROVED');
    draft.requesterIds.add('bob');
    expect(applied.statuses, {'PENDING'});
    expect(applied.requesterIds, isEmpty);
    expect(draft.activeCount, 2);
    draft.clear();
    expect(draft.activeCount, 0);
    expect(applied.activeCount, 1);
  });
}
