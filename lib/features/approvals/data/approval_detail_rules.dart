/// Mirrors the visibility rules in the web RequestDetail view.
class ApprovalDetailRules {
  const ApprovalDetailRules({required this.request, required this.user});

  final Map<String, dynamic> request;
  final Map<String, dynamic> user;

  String get userId => user['id']?.toString() ?? '';
  String get status => request['status']?.toString() ?? '';
  bool get mine => userId.isNotEmpty &&
      request['requesterId']?.toString() == userId;

  List<dynamic> get steps =>
      request['steps'] is List ? request['steps'] as List : const [];

  Map<dynamic, dynamic>? get currentStep {
    final expected = request['currentStepNumber'];
    for (final item in steps) {
      if (item is Map && item['status'] == 'PENDING' &&
          item['stepNumber'] == expected) {
        return item;
      }
    }
    return null;
  }

  bool get canAct => status == 'PENDING' && userId.isNotEmpty &&
      currentStep?['approverId']?.toString() == userId;

  bool get canEditAndSubmit => mine &&
      const ['DRAFT', 'CHANGES_REQUESTED'].contains(status);

  bool get canCancel => mine &&
      !const ['APPROVED', 'REJECTED', 'CANCELLED'].contains(status);

  bool get canComment {
    if (canAct) return false; // Reviewer uses the decision's comment.
    if (mine) return true;
    if ((user['roles'] is List) &&
        (user['roles'] as List).contains('SYSTEM_ADMIN')) return true;
    return userId.isNotEmpty && steps.any(
      (step) => step is Map && step['approverId']?.toString() == userId);
  }

  int get revision => (request['revision'] as num?)?.toInt() ?? -1;

  Map<dynamic, dynamic> get formSchema {
    final snapshot = request['workflowSnapshot'];
    final schema = snapshot is Map ? snapshot['formSchema'] : null;
    if (schema is Map) return schema;
    final type = request['approvalType'];
    final fallback = type is Map ? type['formSchema'] : null;
    return fallback is Map ? fallback : {};
  }

  String get typeName {
    final snapshot = request['workflowSnapshot'];
    final type = snapshot is Map ? snapshot['type'] : null;
    final fallback = request['approvalType'];
    final name = type is Map ? type['name'] : null;
    return (name ?? (fallback is Map ? fallback['name'] : null)
        ?? 'Request').toString();
  }

  String get typeVersion {
    final snapshot = request['workflowSnapshot'];
    final type = snapshot is Map ? snapshot['type'] : null;
    final version = type is Map ? type['version'] : null;
    return (version ?? request['approvalTypeVersion'] ?? 1).toString();
  }
}
