/// Local form rules that mirror apps/api/src/lib/approval-form.js.
/// API remains the final authority for permissions, approvers and versions.
class ApprovalRequestDraft {
  String approvalTypeId = '';
  String title = '';
  final Map<String, dynamic> values = {};

  /// A selected approval type changes its entire dynamic form.
  void selectType(String id) {
    if (approvalTypeId == id) return;
    approvalTypeId = id;
    values.clear();
  }

  String? validate(Map<dynamic, dynamic>? schema, {required bool submit}) {
    if (approvalTypeId.isEmpty) return 'Choose a request type.';
    if (title.trim().length < 2 || title.trim().length > 250) {
      return 'Title must contain 2–250 characters.';
    }
    if (schema == null) return 'Request type configuration is unavailable.';
    for (final entry in values.entries) {
      if (!schema.containsKey(entry.key)) {
        return 'Unknown field: ${entry.key}';
      }
    }
    for (final entry in schema.entries) {
      final config = entry.value;
      if (config is! Map) return 'Invalid request form configuration.';
      final type = (config['type'] ?? 'text').toString();
      final label = (config['label'] ?? entry.key).toString();
      final value = values[entry.key.toString()];
      final empty = value == null ||
          (value is String && value.trim().isEmpty);
      if (empty) {
        if (submit && config['required'] == true) {
          return '$label is required.';
        }
        continue;
      }
      switch (type) {
        case 'number':
          if (value is num && value.isFinite) break;
          if (value is String &&
              num.tryParse(value.trim())?.isFinite == true) break;
          return '$label must be a valid number.';
        case 'checkbox':
          if (value is! bool) return '$label must be checked or unchecked.';
          break;
        case 'date':
          if (value is! String ||
              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
            return '$label must be a valid date.';
          }
          final date = DateTime.tryParse(value);
          if (date == null ||
              date.year.toString().padLeft(4, '0') != value.substring(0, 4) ||
              date.month.toString().padLeft(2, '0') != value.substring(5, 7) ||
              date.day.toString().padLeft(2, '0') != value.substring(8, 10)) {
            return '$label must be a valid date.';
          }
          break;
        case 'select':
          final options = config['options'];
          if (value is! String || options is! List ||
              !options.contains(value)) {
            return '$label must use a valid option.';
          }
          break;
        case 'text':
        case 'textarea':
          if (value is! String ||
              value.length > (type == 'textarea' ? 10000 : 1000)) {
            return '$label has an invalid value.';
          }
          break;
        default:
          return 'Unsupported field type: $type';
      }
    }
    return null;
  }

  /// Dio serializes the numeric form fields as JSON numbers (not strings).
  Map<String, dynamic> submittedValues(Map<dynamic, dynamic> schema) {
    final converted = Map<String, dynamic>.from(values);
    for (final entry in schema.entries) {
      final key = entry.key.toString();
      final field = entry.value;
      if (field is Map && field['type'] == 'number') {
        final raw = converted[key];
        if (raw is String && raw.trim().isNotEmpty) {
          converted[key] = num.parse(raw.trim());
        } else if (raw is String && raw.trim().isEmpty) {
          converted.remove(key);
        }
      }
      if (converted[key] is String &&
          (converted[key] as String).trim().isEmpty) {
        converted.remove(key);
      }
    }
    return converted;
  }
}
