/// Mirrors the web New Approval Type configurator and API schema.
///
/// Only creation is implemented here; editing/versioning is a separate flow.
class ApprovalTypeFieldDraft {
  ApprovalTypeFieldDraft({
    required this.localId,
    required this.keyName,
    required this.label,
    required this.type,
    required this.required,
    List<String>? options,
  }) : options = options ?? <String>[];

  final int localId;
  String keyName;
  String label;
  String type;
  bool required;
  List<String> options;
}

class ApprovalTypeStepDraft {
  ApprovalTypeStepDraft({
    required this.localId,
    required this.name,
    required this.approverRule,
    this.approverValue = '',
  });

  final int localId;
  String name;
  String approverRule;
  String approverValue;
}

class ApprovalTypeDraft {
  String name = '';
  String code = '';
  String description = '';

  int _nextId = 2;

  final List<ApprovalTypeFieldDraft> fields = [
    ApprovalTypeFieldDraft(
      localId: 1,
      keyName: 'field1',
      label: 'Reason',
      type: 'textarea',
      required: true,
    ),
  ];

  final List<ApprovalTypeStepDraft> steps = [
    ApprovalTypeStepDraft(
      localId: 1,
      name: 'Manager review',
      approverRule: 'REQUESTER_MANAGER',
    ),
  ];

  static const fieldTypes = [
    'text', 'textarea', 'number', 'date', 'select', 'checkbox',
  ];

  int _id() => _nextId++;

  bool addField() {
    if (fields.length >= 40) return false;
    var n = fields.length + 1;
    while (fields.any((field) => field.keyName == 'field$n')) {
      n++;
    }
    fields.add(ApprovalTypeFieldDraft(
      localId: _id(),
      keyName: 'field$n',
      label: '',
      type: 'text',
      required: false,
    ));
    return true;
  }

  bool addStep() {
    if (steps.length >= 20) return false;
    steps.add(ApprovalTypeStepDraft(
      localId: _id(),
      name: 'Review',
      approverRule: 'REQUESTER_MANAGER',
    ));
    return true;
  }

  /// Returns the first actionable validation message.
  String? validate({required List<dynamic> users}) {
    if (name.trim().length < 2 || name.trim().length > 200) {
      return 'Name must contain 2–200 characters.';
    }
    if (code.trim().length < 2 || code.trim().length > 50 ||
        !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(code.trim())) {
      return 'Code must contain 2–50 letters, numbers or underscores.';
    }
    if (description.length > 2000) {
      return 'Description cannot exceed 2000 characters.';
    }
    if (fields.length > 40) return 'Only 40 request fields are allowed.';

    final keys = <String>{};
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,59}$')
          .hasMatch(field.keyName.trim())) {
        return 'Field ${i + 1}: key must begin with a letter and contain at most 60 letters, numbers or underscores.';
      }
      if (!keys.add(field.keyName.trim())) {
        return 'Field keys must be unique.';
      }
      if (field.label.trim().isEmpty || field.label.trim().length > 120) {
        return 'Field ${i + 1}: label must contain 1–120 characters.';
      }
      if (!fieldTypes.contains(field.type)) {
        return 'Field ${i + 1}: invalid input type.';
      }
      if (field.type == 'select') {
        if (field.options.isEmpty || field.options.length > 50) {
          return 'Field ${i + 1}: choose between 1 and 50 options.';
        }
        if (field.options.any((value) =>
            value.isEmpty || value.length > 120)) {
          return 'Field ${i + 1}: options must contain 1–120 characters.';
        }
      }
    }
    if (steps.isEmpty || steps.length > 20) {
      return 'Add between 1 and 20 approval steps.';
    }
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step.name.trim().length < 2 || step.name.trim().length > 150) {
        return 'Step ${i + 1}: name must contain 2–150 characters.';
      }
      if (!const ['USER', 'REQUESTER_MANAGER', 'DEPARTMENT_MANAGER']
          .contains(step.approverRule)) {
        return 'Step ${i + 1}: invalid approver.';
      }
      if (step.approverRule == 'USER') {
        if (step.approverValue.isEmpty ||
            !users.any((user) =>
                user is Map &&
                user['id']?.toString() == step.approverValue &&
                user['status'] == 'ACTIVE')) {
          return 'Step ${i + 1}: choose an active approver.';
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toPayload() => {
        'name': name.trim(),
        'code': code.trim().toUpperCase(),
        if (description.isNotEmpty) 'description': description,
        'formSchema': <String, dynamic>{
          for (final field in fields)
            field.keyName.trim(): <String, dynamic>{
              'label': field.label.trim(),
              'type': field.type,
              'required': field.required,
              if (field.type == 'select')
                'options': List<String>.of(field.options),
            },
        },
        'steps': [
          for (var i = 0; i < steps.length; i++)
            <String, dynamic>{
              'stepNumber': i + 1,
              'name': steps[i].name.trim(),
              'approverRule': steps[i].approverRule,
              'approverValue': steps[i].approverRule == 'USER'
                  ? steps[i].approverValue
                  : null,
            },
        ],
      };
}
