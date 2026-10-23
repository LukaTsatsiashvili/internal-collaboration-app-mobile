import 'package:flutter/material.dart';

import '../core/theme/app_theme_extensions.dart';
import '../core/theme/app_dropdown_theme.dart';
import '../core/widgets/app_modal_elements.dart';

/// Keep filters identical to the production web employee directory.
@immutable
class PeopleFilters {
  const PeopleFilters({
    this.departmentId,
    this.role,
    this.status = 'ACTIVE',
  });

  final String? departmentId;
  final String? role;
  final String? status;

  PeopleFilters copyWith({
    String? departmentId,
    String? role,
    String? status,
  }) => PeopleFilters(
    departmentId: departmentId ?? this.departmentId,
    role: role ?? this.role,
    status: status ?? this.status,
  );

  int get activeCount => [
    departmentId,
    role,
    status,
  ].where((item) => item != null && item.isNotEmpty).length;

  PeopleFilters withDepartment(String? id) =>
      PeopleFilters(departmentId: id, role: role, status: status);

  PeopleFilters withRole(String? value) =>
      PeopleFilters(departmentId: departmentId, role: value, status: status);

  PeopleFilters withStatus(String? value) =>
      PeopleFilters(departmentId: departmentId, role: role, status: value);

  static const clear = PeopleFilters(status: null);
}

class PeopleFilterDialog extends StatefulWidget {
  const PeopleFilterDialog({
    super.key,
    required this.initial,
    required this.departments,
  });

  final PeopleFilters initial;
  final List<Map<String, dynamic>> departments;

  @override
  State<PeopleFilterDialog> createState() => _PeopleFilterDialogState();
}

class _PeopleFilterDialogState extends State<PeopleFilterDialog> {
  late PeopleFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>()!;
    final departments = [...widget.departments]
      ..sort((a, b) => (a['name'] ?? '').toString()
          .compareTo((b['name'] ?? '').toString()));
    return Dialog(
      key: const ValueKey('people-filter-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 17),
      backgroundColor: p.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(25),
        side: BorderSide(color: p.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 17, 17, 19),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppModalHeader(
                  title: 'Filter people',
                  onClose: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 7),
                Text('Filter the employee directory',
                  style: TextStyle(color: p.secondaryText, fontSize: 11)),
                if (_draft.activeCount > 0) ...[
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('people-filter-clear'),
                      onPressed: () => setState(() => _draft = PeopleFilters.clear),
                      child: Text('Clear all',
                        style: TextStyle(color: p.link, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                    ),
                  ),
                ] else const SizedBox(height: 17),
                _fieldLabel('Department', p),
                AppSelectDropdown<String>(
                  label: 'All departments',
                  value: _draft.departmentId,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null, child: Text('All departments')),
                    for (final department in departments)
                      DropdownMenuItem<String>(
                        value: department['id']?.toString(),
                        child: Text(
                          department['name']?.toString() ?? 'Department',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(
                    () => _draft = _draft.withDepartment(value)),
                ),
                const SizedBox(height: 16),
                _fieldLabel('Role', p),
                AppSelectDropdown<String>(
                  label: 'All roles',
                  value: _draft.role,
                  items: const [
                    DropdownMenuItem<String>(value: null, child: Text('All roles')),
                    DropdownMenuItem(value: 'EMPLOYEE', child: Text('Employee')),
                    DropdownMenuItem(value: 'MANAGER', child: Text('Manager')),
                    DropdownMenuItem(value: 'AUDITOR', child: Text('Auditor')),
                    DropdownMenuItem(
                      value: 'SYSTEM_ADMIN', child: Text('System administrator')),
                  ],
                  onChanged: (value) => setState(
                    () => _draft = _draft.withRole(value)),
                ),
                const SizedBox(height: 16),
                _fieldLabel('Status', p),
                AppSelectDropdown<String>(
                  label: 'All statuses',
                  value: _draft.status,
                  items: const [
                    DropdownMenuItem<String>(
                      value: null, child: Text('All statuses')),
                    DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                    DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                  ],
                  onChanged: (value) => setState(
                    () => _draft = _draft.withStatus(value)),
                ),
                const SizedBox(height: 23),
                AppModalPrimaryButton(
                  label: 'Apply filters',
                  onPressed: () => Navigator.of(context).pop(_draft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String title, AppPalette p) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(title, style: TextStyle(
      color: p.ink, fontWeight: FontWeight.w700, fontSize: 12)),
  );
}
