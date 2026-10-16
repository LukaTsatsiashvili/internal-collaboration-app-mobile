/// Client-side Tasks filters, using the same conditions as the web Tasks page.
/// Quick tabs, search and sorting are composed separately by TasksScreen.
class TaskAdvancedFilters {
  final Set<String> statuses;
  final Set<String> priorities;
  final Set<String> assigneeIds;
  final Set<String> creatorIds;
  final Set<String> participantIds;
  final Set<String> groupIds;
  final Set<String> departmentIds;
  String due;
  String attachments;
  DateTime? createdFrom;
  DateTime? createdTo;

  TaskAdvancedFilters({
    Set<String>? statuses,
    Set<String>? priorities,
    Set<String>? assigneeIds,
    Set<String>? creatorIds,
    Set<String>? participantIds,
    Set<String>? groupIds,
    Set<String>? departmentIds,
    this.due = 'any',
    this.attachments = 'any',
    this.createdFrom,
    this.createdTo,
  })  : statuses = {...?statuses},
        priorities = {...?priorities},
        assigneeIds = {...?assigneeIds},
        creatorIds = {...?creatorIds},
        participantIds = {...?participantIds},
        groupIds = {...?groupIds},
        departmentIds = {...?departmentIds};

  TaskAdvancedFilters copy() => TaskAdvancedFilters(
        statuses: statuses,
        priorities: priorities,
        assigneeIds: assigneeIds,
        creatorIds: creatorIds,
        participantIds: participantIds,
        groupIds: groupIds,
        departmentIds: departmentIds,
        due: due,
        attachments: attachments,
        createdFrom: createdFrom,
        createdTo: createdTo,
      );

  /// Number of active filter dimensions, matching the web implementation.
  int get activeCount => [
        statuses.isNotEmpty,
        priorities.isNotEmpty,
        assigneeIds.isNotEmpty,
        creatorIds.isNotEmpty,
        participantIds.isNotEmpty,
        groupIds.isNotEmpty,
        departmentIds.isNotEmpty,
        due != 'any',
        attachments != 'any',
        createdFrom != null,
        createdTo != null,
      ].where((active) => active).length;

  void clear() {
    statuses.clear();
    priorities.clear();
    assigneeIds.clear();
    creatorIds.clear();
    participantIds.clear();
    groupIds.clear();
    departmentIds.clear();
    due = 'any';
    attachments = 'any';
    createdFrom = null;
    createdTo = null;
  }

  static DateTime? _parseDate(dynamic raw) =>
      raw == null ? null : DateTime.tryParse(raw.toString())?.toLocal();

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _dueMatches(DateTime? date, String status) {
    final now = DateTime.now();
    final today = _day(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final nextWeek = DateTime(today.year, today.month, today.day + 7);
    switch (due) {
      case 'overdue':
        return date != null &&
            status != 'COMPLETED' &&
            status != 'CANCELLED' &&
            date.isBefore(now);
      case 'today':
        return date != null &&
            !date.isBefore(today) &&
            date.isBefore(tomorrow);
      case 'next7':
        return date != null &&
            !date.isBefore(today) &&
            date.isBefore(nextWeek);
      case 'no_due':
        return date == null;
      default:
        return true;
    }
  }

  bool matches(dynamic task, {String? effectiveGroupId}) {
    final status = (task['status'] ?? '').toString().toUpperCase();
    final priority = (task['priority'] ?? '').toString().toUpperCase();
    final assignee = task['assigneeId']?.toString() ?? '__unassigned__';
    final creator = task['creatorId']?.toString();
    final department =
        task['departmentId']?.toString() ?? '__no_department__';
    final group = effectiveGroupId ?? '__ungrouped__';
    final people = task['participants'];
    final participants = people is List ? people : <dynamic>[];
    final files = task['attachments'];
    final hasFiles = files is List && files.isNotEmpty;
    final dueDate = _parseDate(task['dueDate']);
    final created = _parseDate(task['createdAt']);

    if (statuses.isNotEmpty && !statuses.contains(status)) return false;
    if (priorities.isNotEmpty && !priorities.contains(priority)) return false;
    if (assigneeIds.isNotEmpty && !assigneeIds.contains(assignee)) return false;
    if (creatorIds.isNotEmpty && !creatorIds.contains(creator)) return false;
    if (departmentIds.isNotEmpty && !departmentIds.contains(department)) {
      return false;
    }
    if (groupIds.isNotEmpty && !groupIds.contains(group)) return false;
    if (participantIds.isNotEmpty &&
        !participants.any((person) =>
            person is Map &&
            (participantIds.contains(person['userId']?.toString()) ||
                (person['user'] is Map &&
                    participantIds.contains(person['user']['id']?.toString()))))) {
      return false;
    }
    if (!_dueMatches(dueDate, status)) return false;
    if (attachments == 'with' && !hasFiles) return false;
    if (attachments == 'without' && hasFiles) return false;
    if (createdFrom != null &&
        (created == null || _day(created).isBefore(_day(createdFrom!)))) {
      return false;
    }
    if (createdTo != null &&
        (created == null || _day(created).isAfter(_day(createdTo!)))) {
      return false;
    }
    return true;
  }
}
