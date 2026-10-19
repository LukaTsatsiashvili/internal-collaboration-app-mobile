import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/approvals/data/approval_service.dart';
import '../features/approvals/data/approval_type_draft.dart';

/// Mobile version of the web's approval type configurator.
/// Returns true only after the API confirms successful creation or a new version.
class ApprovalTypeCreateSheet extends StatefulWidget {
  const ApprovalTypeCreateSheet({
    super.key,
    required this.service,
    this.existing,
  });

  final ApprovalService service;
  final Map<String, dynamic>? existing;

  @override
  State<ApprovalTypeCreateSheet> createState() => _ApprovalTypeCreateSheetState();
}

class _ApprovalTypeCreateSheetState extends State<ApprovalTypeCreateSheet> {
  late final ApprovalTypeDraft _draft;
  bool get _editing => widget.existing != null;
  bool get _codeLocked {
    final count = widget.existing?['_count'];
    return count is Map && (count['requests'] as num? ?? 0) > 0;
  }
  final ScrollController _scroll = ScrollController();
  List<dynamic> _users = [];
  String? _usersError;
  String? _error;
  bool _saving = false;
  bool _loadingUsers = true;

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;

  @override
  void initState() {
    super.initState();
    _draft = widget.existing == null
        ? ApprovalTypeDraft()
        : ApprovalTypeDraft.fromExisting(widget.existing!);
    _loadUsers();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loadingUsers = true;
      _usersError = null;
    });
    try {
      final users = await widget.service.getUsersForApprovalSteps();
      if (!mounted) return;
      setState(() => _users = users.where((user) =>
          user is Map && user['status'] == 'ACTIVE').toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _usersError =
          'Users could not be loaded. Select a manager rule or retry.');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  void _set(void Function() change) {
    if (_saving) return;
    setState(() {
      change();
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final validation = _draft.validate(users: _users);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await widget.service.updateApprovalType(
          widget.existing!['id'].toString(), _draft.toPayload(),
        );
      } else {
        await widget.service.createApprovalType(_draft.toPayload());
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: _p.hintText, fontSize: 12),
    filled: true,
    fillColor: _p.card,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 13, vertical: 13,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: _p.cardBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: _p.cardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: _p.link, width: 1.5),
    ),
  );

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(title, style: TextStyle(
      color: _p.secondaryText,
      fontSize: 11, fontWeight: FontWeight.w800,
    )),
  );

  Widget _sectionHeading(String title) => Padding(
    padding: const EdgeInsets.only(top: 17, bottom: 12),
    child: Text(title, style: TextStyle(
      color: _p.ink, fontSize: 14, fontWeight: FontWeight.w800,
    )),
  );

  Widget _input({
    required String initial,
    required String hint,
    required ValueChanged<String> onChanged,
    required String stableKey,
    int maxLines = 1,
    int? maxLength,
    List<TextInputFormatter>? formatters,
    bool enabled = true,
  }) => TextFormField(
    key: ValueKey(stableKey),
    initialValue: initial,
    enabled: !_saving && enabled,
    keyboardType: maxLines > 1
        ? TextInputType.multiline : TextInputType.text,
    textInputAction: maxLines > 1
        ? TextInputAction.newline : TextInputAction.next,
    minLines: maxLines,
    maxLines: maxLines,
    maxLength: maxLength,
    buildCounter: (context, {required currentLength,
        required isFocused, maxLength}) => null,
    inputFormatters: formatters,
    onChanged: onChanged,
    style: TextStyle(
      color: _p.ink, fontSize: 12.5, fontWeight: FontWeight.w600,
    ),
    decoration: _decoration(hint),
  );

  Widget _choice({
    required String selectedLabel,
    required Map<String, String> options,
    required ValueChanged<String> onSelected,
    String? tooltip,
  }) => LayoutBuilder(
    builder: (context, bounds) => PopupMenuButton<String>(
    tooltip: tooltip ?? 'Select option',
    enabled: !_saving,
    position: PopupMenuPosition.under,
    color: _p.card,
    constraints: BoxConstraints(
      minWidth: bounds.maxWidth,
      maxWidth: bounds.maxWidth,
      maxHeight: MediaQuery.sizeOf(context).height * 0.55,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: BorderSide(color: _p.cardBorder),
    ),
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final option in options.entries)
        PopupMenuItem<String>(
          value: option.key,
          child: Row(children: [
            Expanded(child: Text(option.value,
              style: TextStyle(color: _p.secondaryText, fontSize: 12))),
            if (option.value == selectedLabel)
              Icon(Icons.check_rounded, size: 17, color: _p.link),
          ]),
        ),
    ],
    child: Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _p.cardBorder),
      ),
      child: Row(children: [
        Expanded(child: Text(selectedLabel,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _p.secondaryText, fontSize: 12,
            fontWeight: FontWeight.w700,
          ))),
        const SizedBox(width: 6),
        Icon(Icons.keyboard_arrow_down_rounded, color: _p.link, size: 19),
      ]),
    ),
    ),
  );

  Widget _addButton(String title, VoidCallback? onPressed) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(Icons.add_rounded, color: _p.link, size: 17),
    label: Text(title, style: TextStyle(
      color: _p.secondaryText, fontSize: 11.5,
      fontWeight: FontWeight.w800,
    )),
    style: OutlinedButton.styleFrom(
      backgroundColor: _p.card,
      side: BorderSide(color: _p.cardBorder),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  Widget _fieldCard(ApprovalTypeFieldDraft field, int index) {
    return Container(
      key: ValueKey('approval-field-${field.localId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _p.card,
        border: Border.all(color: _p.cardBorder),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(children: [
        _input(
          initial: field.keyName,
          hint: 'Field key (e.g. field1)',
          stableKey: 'field-${field.localId}-key',
          maxLength: 60,
          onChanged: (text) => field.keyName = text,
        ),
        const SizedBox(height: 8),
        _input(
          initial: field.label,
          hint: 'Field label',
          stableKey: 'field-${field.localId}-label',
          maxLength: 120,
          onChanged: (text) => field.label = text,
        ),
        const SizedBox(height: 8),
        _choice(
          tooltip: 'Field ${index + 1} type',
          selectedLabel: field.type,
          options: const {
            'text': 'text', 'textarea': 'textarea',
            'number': 'number', 'date': 'date',
            'select': 'select', 'checkbox': 'checkbox',
          },
          onSelected: (value) => _set(() {
            field.type = value;
            if (value == 'select' && field.options.isEmpty) {
              field.options = ['Option 1'];
            }
          }),
        ),
        if (field.type == 'select') ...[
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft,
            child: _heading('Options')),
          for (var optionIndex = 0;
              optionIndex < field.options.length; optionIndex++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                Expanded(child: _input(
                  initial: field.options[optionIndex],
                  hint: 'Option ${optionIndex + 1}',
                  stableKey: 'option-${field.localId}-$optionIndex-${field.options.length}',
                  maxLength: 120,
                  onChanged: (text) => field.options[optionIndex] = text,
                )),
                if (field.options.length > 1)
                  IconButton(
                    tooltip: 'Remove option',
                    onPressed: _saving ? null : () => _set(() {
                      field.options.removeAt(optionIndex);
                    }),
                    icon: Icon(Icons.close_rounded,
                      size: 18, color: _p.muted),
                  ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: _addButton('Add option',
              field.options.length >= 50 || _saving ? null :
              () => _set(() => field.options.add(''))),
          ),
        ],
        const SizedBox(height: 6),
        Row(children: [
          Checkbox(
            value: field.required,
            onChanged: _saving ? null :
                (v) => _set(() => field.required = v ?? false),
            activeColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
          ),
          Text('Required', style: TextStyle(
            color: _p.secondaryText, fontSize: 11.5,
            fontWeight: FontWeight.w700,
          )),
          const Spacer(),
          IconButton(
            tooltip: 'Remove field ${index + 1}',
            onPressed: _saving ? null :
                () => _set(() => _draft.fields.remove(field)),
            icon: Icon(Icons.close_rounded,
              color: _p.muted, size: 19),
          ),
        ]),
      ]),
    );
  }

  Map<String, String> get _approverOptions {
    final choices = <String, String>{
      'REQUESTER_MANAGER': 'Requester’s manager',
      'DEPARTMENT_MANAGER': 'Department manager',
    };
    for (final person in _users) {
      if (person is! Map || person['id'] == null) continue;
      choices[person['id'].toString()] =
          (person['displayName'] ?? person['email'] ?? '').toString();
    }
    return choices;
  }

  Widget _stepCard(ApprovalTypeStepDraft step, int index) {
    final selected = step.approverRule == 'USER'
        ? step.approverValue : step.approverRule;
    final choices = _approverOptions;
    // Older workflow versions can contain ROLE rules even though the web
    // editor only offers two manager rules and active user IDs.
    if (step.approverRule == 'ROLE' && step.approverValue.isNotEmpty) {
      choices['ROLE:${step.approverValue}'] =
          'Role: ${step.approverValue}';
    }
    return Container(
      key: ValueKey('approval-step-${step.localId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _p.cardBorder),
      ),
      child: Column(children: [
        Row(children: [
          Text('${index + 1}.', style: TextStyle(
            color: _p.muted, fontSize: 12,
            fontWeight: FontWeight.w800,
          )),
          const SizedBox(width: 8),
          Expanded(child: _input(
            initial: step.name,
            hint: 'Step name',
            stableKey: 'step-${step.localId}-name',
            maxLength: 150,
            onChanged: (text) => step.name = text,
          )),
          if (_draft.steps.length > 1)
            IconButton(
              tooltip: 'Remove step ${index + 1}',
              onPressed: _saving ? null :
                  () => _set(() => _draft.steps.remove(step)),
              icon: Icon(Icons.close_rounded,
                color: _p.muted, size: 19),
            ),
        ]),
        const SizedBox(height: 9),
        _choice(
          tooltip: 'Step ${index + 1} approver',
          selectedLabel: choices[step.approverRule == 'ROLE'
              ? 'ROLE:${step.approverValue}' : selected] ??
              (step.approverRule == 'USER'
                  ? 'Select an active user' : 'Select approver'),
          options: choices,
          onSelected: (value) => _set(() {
            if (value.startsWith('ROLE:')) {
              step.approverRule = 'ROLE';
              step.approverValue = value.substring(5);
            } else if (value == 'REQUESTER_MANAGER' ||
                value == 'DEPARTMENT_MANAGER') {
              step.approverRule = value;
              step.approverValue = '';
            } else {
              step.approverRule = 'USER';
              step.approverValue = value;
            }
          }),
        ),
      ]),
    );
  }

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(15, 11, 15, 15),
    decoration: BoxDecoration(
      color: _p.panel,
      border: Border(top: BorderSide(color: _p.cardBorder)),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_error != null) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: Text(_error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 11.5, fontWeight: FontWeight.w600,
          )),
        ),
        const SizedBox(height: 8),
      ],
      Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _saving ? null : _submit,
            borderRadius: BorderRadius.circular(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_saving)
                const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
              else ...[
                Text(_editing ? 'Save new version' : 'Create approval type',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w800,
                  )),
                const SizedBox(width: 9),
                const Icon(Icons.arrow_forward_rounded,
                  size: 18, color: Colors.white),
              ],
            ]),
          ),
        ),
      ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safeArea = MediaQuery.paddingOf(context);
    final available = math.max(
      160.0,
      height - keyboard - safeArea.top - safeArea.bottom - 40.0,
    );
    final dialogHeight = math.min(height * 0.90, available);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: Padding(
          // Leave space below the sheet so the bottom radius is visible.
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          child: Material(
            color: _p.panel,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(26),
            child: SizedBox(
              height: dialogHeight,
              child: Column(children: [
                const SizedBox(height: 9),
                Container(
                  height: 4, width: 34,
                  decoration: BoxDecoration(
                    color: _p.muted.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(17, 9, 10, 12),
                  child: Row(children: [
                    Container(
                      height: 8, width: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF89B0FF),
                        shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Text(
                      _editing ? 'Edit ${widget.existing!['name']}' : 'New approval type',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _p.ink, fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ))),
                    IconButton(
                      tooltip: 'Close new approval type',
                      onPressed: _saving ? null :
                          () => Navigator.of(context).pop(false),
                      icon: Icon(Icons.close_rounded,
                        color: _p.muted, size: 20),
                    ),
                  ]),
                ),
                Divider(height: 1, color: _p.cardBorder),
                Expanded(child: ListView(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(15, 17, 15, 22),
                  children: [
                    if (_editing) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _p.searchBackground,
                          border: Border.all(color: _p.cardBorder),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Version ${widget.existing!['version']} · '
                          '${widget.existing!['_count'] is Map ? (widget.existing!['_count']['requests'] ?? 0) : 0} requests. '
                          'Saving creates a new version; existing requests keep their original workflow.',
                          style: TextStyle(
                            color: _p.secondaryText, fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _heading('Name'),
                    _input(
                      initial: _draft.name,
                      hint: 'e.g. Budget Request',
                      stableKey: 'approval-type-name',
                      maxLength: 200,
                      onChanged: (v) => _draft.name = v,
                    ),
                    const SizedBox(height: 12),
                    _heading('Code (letters, numbers, underscores)'),
                    _input(
                      initial: _draft.code,
                      hint: 'e.g. BUDGET_REQUEST',
                      stableKey: 'approval-type-code',
                      enabled: !_codeLocked,
                      maxLength: 50,
                      formatters: [
                        TextInputFormatter.withFunction((oldValue, newValue) =>
                          newValue.copyWith(text: newValue.text.toUpperCase())),
                      ],
                      onChanged: (v) => _draft.code = v,
                    ),
                    if (_codeLocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text('The code is locked because this type is already in use.',
                          style: TextStyle(color: _p.muted, fontSize: 11)),
                      ),
                    const SizedBox(height: 12),
                    _heading('Description'),
                    _input(
                      initial: _draft.description,
                      hint: 'Provide context or instructions for this approval process...',
                      stableKey: 'approval-type-description',
                      maxLines: 3,
                      maxLength: 2000,
                      onChanged: (v) => _draft.description = v,
                    ),
                    _sectionHeading('Request form'),
                    for (var i = 0; i < _draft.fields.length; i++)
                      _fieldCard(_draft.fields[i], i),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _addButton('Add field',
                        _draft.fields.length >= 40 || _saving ? null :
                        () => _set(() => _draft.addField())),
                    ),
                    _sectionHeading('Approval steps, in order'),
                    for (var i = 0; i < _draft.steps.length; i++)
                      _stepCard(_draft.steps[i], i),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _addButton('Add step',
                        _draft.steps.length >= 20 || _saving ? null :
                        () => _set(() => _draft.addStep())),
                    ),
                    if (_loadingUsers) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(color: _p.link),
                    ] else if (_usersError != null) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: Text(_usersError!,
                          style: TextStyle(
                            color: _p.secondaryText, fontSize: 11))),
                        TextButton(onPressed: _loadUsers,
                          child: const Text('Retry')),
                      ]),
                    ],
                  ],
                )),
                _footer(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
