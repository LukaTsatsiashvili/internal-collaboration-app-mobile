/// Client-side approval filters. An empty selection in a dimension means Any.
/// Multiple values within one dimension use OR; dimensions combine with AND.
class ApprovalAdvancedFilters {
  static const ungrouped = '__ungrouped__';

  final Set<String> statuses;
  final Set<String> typeIds;
  final Set<String> requesterIds;
  final Set<String> groupIds;
  DateTime? createdFrom;
  DateTime? createdTo;

  ApprovalAdvancedFilters({
    Set<String>? statuses,
    Set<String>? typeIds,
    Set<String>? requesterIds,
    Set<String>? groupIds,
    this.createdFrom,
    this.createdTo,
  })  : statuses = {...?statuses},
        typeIds = {...?typeIds},
        requesterIds = {...?requesterIds},
        groupIds = {...?groupIds};

  ApprovalAdvancedFilters copy() => ApprovalAdvancedFilters(
        statuses: statuses,
        typeIds: typeIds,
        requesterIds: requesterIds,
        groupIds: groupIds,
        createdFrom: createdFrom,
        createdTo: createdTo,
      );

  int get activeCount => [
        statuses.isNotEmpty,
        typeIds.isNotEmpty,
        requesterIds.isNotEmpty,
        groupIds.isNotEmpty,
        createdFrom != null,
        createdTo != null,
      ].where((value) => value).length;

  void clear() {
    statuses.clear();
    typeIds.clear();
    requesterIds.clear();
    groupIds.clear();
    createdFrom = null;
    createdTo = null;
  }

  static DateTime? _localDay(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString())?.toLocal();
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool matches(dynamic request) {
    if (request is! Map) return false;
    if (statuses.isNotEmpty &&
        !statuses.contains(request['status']?.toString())) {
      return false;
    }

    if (typeIds.isNotEmpty &&
        !typeIds.contains(request['approvalTypeId']?.toString())) {
      return false;
    }

    if (requesterIds.isNotEmpty &&
        !requesterIds.contains(request['requesterId']?.toString())) {
      return false;
    }

    final layout = request['personalLayout'];
    final rawGroup = layout is Map ? layout['groupId']?.toString() : null;
    final groupId = rawGroup == null || rawGroup.isEmpty
        ? ungrouped
        : rawGroup;
    if (groupIds.isNotEmpty && !groupIds.contains(groupId)) return false;

    if (createdFrom != null || createdTo != null) {
      final day = _localDay(request['createdAt']);
      if (day == null) return false;
      if (createdFrom != null && day.isBefore(_day(createdFrom!))) {
        return false;
      }
      if (createdTo != null && day.isAfter(_day(createdTo!))) {
        return false;
      }
    }
    return true;
  }
}
