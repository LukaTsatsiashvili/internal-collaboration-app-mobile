import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/approvals/data/approval_request_draft.dart';
import '../features/approvals/data/approval_service.dart';

/// New Request mirrors web RequestForm. Returns true after confirmed creation.
class ApprovalRequestCreateDialog extends StatefulWidget {
  const ApprovalRequestCreateDialog({
    super.key,
    required this.service,
    this.filePicker,
  });
  final ApprovalService service;

  /// Injectable for tests; production uses the platform's file_selector.
  final Future<XFile?> Function()? filePicker;

  @override
  State<ApprovalRequestCreateDialog> createState() =>
      _ApprovalRequestCreateDialogState();
}

class _ApprovalRequestCreateDialogState
    extends State<ApprovalRequestCreateDialog> {
  final ApprovalRequestDraft _draft = ApprovalRequestDraft();
  final TextEditingController _title = TextEditingController();
  List<dynamic> _types = [];
  XFile? _file;
  bool _loading = true;
  bool _saving = false;
  bool _pickingFile = false;
  String? _error;

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final types = await widget.service.getApprovalTypes();
      if (!mounted) return;
      setState(() => _types = types.where((type) =>
          type is Map && type['status'] == 'ACTIVE').toList());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<dynamic, dynamic>? get _selectedType {
    for (final item in _types) {
      if (item is Map && item['id']?.toString() == _draft.approvalTypeId) {
        return item;
      }
    }
    return null;
  }

  Map<dynamic, dynamic>? get _schema {
    final value = _selectedType?['formSchema'];
    return value is Map ? value : null;
  }

  void _update(String key, dynamic value) {
    setState(() {
      if (value == null || (value is String && value.isEmpty)) {
        _draft.values.remove(key);
      } else {
        _draft.values[key] = value;
      }
      _error = null;
    });
  }

  Future<void> _pickAttachment() async {
    if (_saving || _pickingFile) return;
    setState(() => _pickingFile = true);
    try {
      final file = widget.filePicker != null
          ? await widget.filePicker!()
          : await openFile();
      if (!mounted) return;
      if (file != null) setState(() { _file = file; _error = null; });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not choose the attachment: $error');
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  Future<void> _save({required bool submit}) async {
    if (_saving || _loading) return;
    _draft.title = _title.text;
    final validation = _draft.validate(_schema, submit: submit);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _error = null; });
    try {
      final attachmentIds = <String>[];
      if (_file != null) {
        final bytes = await _file!.readAsBytes();
        final id = await widget.service.uploadApprovalAttachment(
            bytes, _file!.name);
        attachmentIds.add(id);
      }
      await widget.service.createApprovalRequest(
        approvalTypeId: _draft.approvalTypeId,
        title: _draft.title,
        data: _draft.submittedValues(_schema!),
        submit: submit,
        attachmentIds: attachmentIds,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: _p.cardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: _p.link, width: 1.4),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(text, style: TextStyle(
      color: _p.secondaryText,
      fontSize: 12, fontWeight: FontWeight.w700,
    )),
  );

  /// Existing app style for dropdowns, including choices longer than screen.
  Widget _menu({
    required String selectedLabel,
    required Map<String, String> entries,
    required ValueChanged<String> onSelected,
    required String tooltip,
  }) => LayoutBuilder(
    builder: (context, bounds) => PopupMenuButton<String>(
    tooltip: tooltip,
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
    itemBuilder: (_) => [
      for (final option in entries.entries)
        PopupMenuItem<String>(
          value: option.key,
          child: Row(children: [
            Expanded(child: Text(option.value, style: TextStyle(
                color: _p.secondaryText, fontSize: 12))),
            if (option.value == selectedLabel)
              Icon(Icons.check_rounded, color: _p.link, size: 17),
          ]),
        ),
    ],
    child: Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: _p.card,
        border: Border.all(color: _p.cardBorder),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(children: [
        Expanded(child: Text(selectedLabel,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _p.secondaryText, fontSize: 12))),
        Icon(Icons.keyboard_arrow_down_rounded,
          color: _p.link, size: 20),
      ]),
    ),
    ),
  );

  Widget _dynamicField(String key, Map field) {
    final type = (field['type'] ?? 'text').toString();
    final label = (field['label'] ?? key).toString();
    final required = field['required'] == true;
    final value = _draft.values[key];
    final heading = '$label${required ? ' *' : ''}';
    final fieldKey = ValueKey('approval-request-${_draft.approvalTypeId}-$key');
    return Padding(
      key: ValueKey('request-field-$key'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(heading),
        if (type == 'select')
          _menu(
            tooltip: 'Select $label',
            selectedLabel: (value ?? 'Choose…').toString(),
            entries: {
              for (final option in (field['options'] is List
                  ? field['options'] as List : <dynamic>[]))
                option.toString(): option.toString(),
            },
            onSelected: (next) => _update(key, next),
          )
        else if (type == 'checkbox')
          Row(children: [
            Checkbox(
              key: fieldKey,
              value: value == true,
              activeColor: AppColors.primary,
              onChanged: _saving
                  ? null : (checked) => _update(key, checked ?? false),
            ),
            Expanded(child: Text(value == true ? 'Yes' : 'No',
              style: TextStyle(color: _p.secondaryText, fontSize: 12))),
          ])
        else if (type == 'date')
          InkWell(
            onTap: _saving ? null : () async {
              final raw = value?.toString();
              final date = raw == null ? null : DateTime.tryParse(raw);
              final picked = await showDatePicker(
                context: context,
                initialDate: date ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (!mounted || picked == null) return;
              final dateValue = '${picked.year.toString().padLeft(4, '0')}-'
                  '${picked.month.toString().padLeft(2, '0')}-'
                  '${picked.day.toString().padLeft(2, '0')}';
              _update(key, dateValue);
            },
            borderRadius: BorderRadius.circular(13),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              height: 45,
              decoration: BoxDecoration(
                color: _p.card,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _p.cardBorder),
              ),
              child: Row(children: [
                Expanded(child: Text(value?.toString() ?? 'Choose date',
                  style: TextStyle(color: _p.secondaryText, fontSize: 12))),
                Icon(Icons.calendar_today_outlined,
                  color: _p.muted, size: 18),
              ]),
            ),
          )
        else
          TextFormField(
            key: fieldKey,
            initialValue: value?.toString() ?? '',
            enabled: !_saving,
            keyboardType: type == 'number'
                ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                : type == 'textarea'
                    ? TextInputType.multiline : TextInputType.text,
            maxLines: type == 'textarea' ? 3 : 1,
            textInputAction: type == 'textarea'
                ? TextInputAction.newline : TextInputAction.next,
            onChanged: (text) => _update(key, text),
            style: TextStyle(color: _p.ink, fontSize: 12.5),
            decoration: _decoration('Enter $label'),
          ),
      ]),
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_error != null) ...[
        Align(alignment: Alignment.centerLeft,
          child: Text(_error!, style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.error,
          ))),
        const SizedBox(height: 10),
      ],
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        OutlinedButton(
          onPressed: _saving || _loading
              ? null : () => _save(submit: false),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _p.cardBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13)),
          ),
          child: Text('Save draft', style: TextStyle(
            color: _p.secondaryText, fontWeight: FontWeight.w700,
            fontSize: 12,
          )),
        ),
        const SizedBox(width: 9),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              AppColors.gradientStart, AppColors.gradientEnd,
            ]),
            borderRadius: BorderRadius.circular(13),
          ),
          child: TextButton(
            onPressed: _saving || _loading
                ? null : () => _save(submit: true),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 15, vertical: 13),
            ),
            child: _saving
                ? const SizedBox(height: 16, width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                : const Text('Submit request', style: TextStyle(
                    color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      alignment: Alignment.center,
      backgroundColor: _p.panel,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: _p.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 690),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 9, 13),
            child: Row(children: [
              Container(height: 8, width: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF89B0FF))),
              const SizedBox(width: 9),
              Expanded(child: Text('New request', style: TextStyle(
                color: _p.ink, fontSize: 18, fontWeight: FontWeight.w800))),
              IconButton(
                tooltip: 'Close new request',
                onPressed: _saving ? null :
                    () => Navigator.of(context).pop(false),
                icon: Icon(Icons.close_rounded, color: _p.muted, size: 19),
              ),
            ]),
          ),
          Divider(height: 1, color: _p.cardBorder),
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(17, 18, 17, 12),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('Request type'),
                  if (_loading)
                    const SizedBox(height: 46,
                      child: Center(child: LinearProgressIndicator()))
                  else ...[
                    _menu(
                      tooltip: 'Choose request type',
                      selectedLabel: (_selectedType?['name'] ?? 'Choose a type')
                          .toString(),
                      entries: {
                        for (final type in _types.whereType<Map>())
                          type['id'].toString(): type['name'].toString(),
                      },
                      onSelected: (id) => setState(() {
                        _draft.selectType(id);
                        _error = null;
                      }),
                    ),
                    if (_types.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('No active request types available.',
                          style: TextStyle(
                            color: _p.muted, fontSize: 11)),
                      ),
                  ],
                  const SizedBox(height: 15),
                  _label('Title'),
                  TextField(
                    key: const ValueKey('new-approval-request-title'),
                    controller: _title,
                    enabled: !_saving,
                    maxLength: 250,
                    buildCounter: (context, {required currentLength,
                        required isFocused, maxLength}) => null,
                    style: TextStyle(color: _p.ink, fontSize: 12.5),
                    decoration: _decoration('Request title'),
                  ),
                  if (_schema != null) ...[
                    const SizedBox(height: 14),
                    for (final entry in _schema!.entries)
                      if (entry.value is Map)
                        _dynamicField(entry.key.toString(), entry.value as Map),
                  ],
                  const SizedBox(height: 15),
                  _label('Attachment (optional)'),
                  InkWell(
                    onTap: _saving ? null : _pickAttachment,
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: _p.card,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: _p.cardBorder),
                      ),
                      child: Row(children: [
                        Icon(Icons.attach_file_rounded,
                          size: 18, color: _p.secondaryText),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          _file?.name ?? 'Choose file',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _p.secondaryText,
                            fontSize: 12),
                        )),
                        if (_pickingFile) const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                        if (_file != null)
                          IconButton(
                            tooltip: 'Remove attachment',
                            onPressed: _saving ? null :
                                () => setState(() => _file = null),
                            icon: Icon(Icons.close_rounded,
                                color: _p.muted, size: 17),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: _p.cardBorder),
          _footer(),
        ]),
      ),
    );
  }
}
