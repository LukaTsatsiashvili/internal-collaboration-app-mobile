import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';

import '../features/tasks/data/task_service.dart';

/// Immutable data returned by the bottom sheet; the parent page uses it with
/// TaskService after the sheet has closed.
class TaskCreationDraft {
  final String title;
  final String description;
  final String? assigneeId;
  final String? groupId;
  final String priority;
  final String? dueDate;
  final List<String> participantIds;
  final XFile? attachment;

  const TaskCreationDraft({
    required this.title,
    required this.description,
    required this.assigneeId,
    required this.groupId,
    required this.priority,
    required this.dueDate,
    required this.participantIds,
    required this.attachment,
  });
}

class TaskCreateSheet extends StatefulWidget {
  final TaskService service;
  final List<dynamic> groups;

  const TaskCreateSheet({
    super.key,
    required this.service,
    required this.groups,
  });

  @override
  State<TaskCreateSheet> createState() => _TaskCreateSheetState();
}

class _TaskCreateSheetState extends State<TaskCreateSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _participantSearch = TextEditingController();
  String _participantQuery = '';
  late final Future<List<dynamic>> _usersFuture;
  String? _assigneeId;
  String? _groupId;
  String _priority = 'NORMAL';
  DateTime? _dueDate;
  final Set<String> _participantIds = <String>{};
  XFile? _file;
  String? _error;
  bool _pickingFile = false;

  @override
  void initState() {
    super.initState();
    // Loading once prevents every checkbox/date selection from calling the API.
    _usersFuture = widget.service.getUsers();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _participantSearch.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_pickingFile) return;
    setState(() => _pickingFile = true);
    try {
      final selected = await openFile();
      if (!mounted) return;
      setState(() => _file = selected ?? _file);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'ფაილის არჩევა ვერ მოხერხდა: $error');
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (!mounted) return;
    if (date != null) setState(() => _dueDate = date);
  }

  void _submit() {
    final title = _title.text.trim();
    // Only the title is required. The backend accepts an empty participant list.
    if (title.isEmpty) {
      setState(() => _error = 'გთხოვთ მიუთითოთ დავალების სათაური.');
      return;
    }

    // No `await` here. The bottom sheet returns data, not a running Future.
    Navigator.of(context).pop(
      TaskCreationDraft(
        title: title,
        description: _description.text.trim(),
        assigneeId: _assigneeId,
        groupId: _groupId,
        priority: _priority,
        dueDate: _dueDate?.toIso8601String(),
        participantIds: List<String>.of(_participantIds),
        attachment: _file,
      ),
    );
  }

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;

  String _userName(dynamic user) {
    final first = (user['firstName'] ?? '').toString().trim();
    final last = (user['lastName'] ?? '').toString().trim();
    final fullName = [first, last].where((part) => part.isNotEmpty).join(' ');
    final displayName = (user['displayName'] ?? '').toString().trim();
    final email = (user['email'] ?? '').toString().trim();
    return displayName.isNotEmpty
        ? displayName
        : fullName.isNotEmpty
            ? fullName
            : email;
  }

  String _userSubtitle(dynamic user) {
    final department = user['department'];
    final departmentName = department is Map
        ? (department['name'] ?? '').toString().trim()
        : '';
    final jobTitle = (user['jobTitle'] ?? '').toString().trim();
    if (departmentName.isNotEmpty) return departmentName;
    if (jobTitle.isNotEmpty) return jobTitle;
    return (user['email'] ?? '').toString();
  }

  List<dynamic> _filteredParticipants(List<dynamic> users) {
    final query = _participantQuery.trim().toLowerCase();
    if (query.isEmpty) return users;
    return users.where((user) {
      final name = _userName(user).toLowerCase();
      final first = (user['firstName'] ?? '').toString().toLowerCase();
      final last = (user['lastName'] ?? '').toString().toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();
      final subtitle = _userSubtitle(user).toLowerCase();
      return name.contains(query) ||
          (first + ' ' + last).contains(query) ||
          email.contains(query) ||
          subtitle.contains(query);
    }).toList();
  }

  Widget _fieldLabel(String text, {bool isRequired = false, String? suffix}) {
    final p = _p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              color: p.secondaryText,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.65,
            ),
          ),
          if (isRequired)
            const Text(
              ' *',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          const Spacer(),
          if (suffix != null)
            Text(
              suffix,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: p.muted,
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(
    String hint, {
    Widget? prefix,
    Widget? suffix,
  }) {
    final p = _p;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: p.cardBorder),
    );
    return InputDecoration(
      filled: true,
      fillColor: p.card,
      hintText: hint,
      hintStyle: TextStyle(
        color: p.hintText,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: prefix,
      suffixIcon: suffix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 15,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.link, width: 1.4),
      ),
    );
  }

  Widget _titleField() {
    final p = _p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _title,
          builder: (context, value, child) => _fieldLabel(
            'TASK TITLE',
            isRequired: true,
            suffix: value.text.length.toString() + '/250',
          ),
        ),
        TextField(
          controller: _title,
          maxLength: 250,
          buildCounter: (context, {
            required int currentLength,
            required bool isFocused,
            required int? maxLength,
          }) => null,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          style: TextStyle(color: p.ink, fontSize: 13),
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration('Enter task title...'),
        ),
      ],
    );
  }

  Widget _descriptionField() {
    final p = _p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('DESCRIPTION'),
        TextField(
          controller: _description,
          minLines: 4,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: p.ink, fontSize: 13, height: 1.45),
          decoration: _fieldDecoration('Add detailed task instructions...'),
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) {
    final p = _p;
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: p.card,
      borderRadius: BorderRadius.circular(17),
      menuMaxHeight: MediaQuery.sizeOf(context).height * 0.40,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 20,
        color: p.muted,
      ),
      style: TextStyle(
        color: p.ink,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: _fieldDecoration(hint ?? ''),
      items: items,
      onChanged: onChanged,
    );
  }

  Color _priorityColor(String level) {
    switch (level) {
      case 'LOW':
        return const Color(0xFF4385F7);
      case 'HIGH':
        return const Color(0xFFE9A126);
      case 'URGENT':
        return const Color(0xFFF06464);
      default:
        return const Color(0xFF15BF8D);
    }
  }

  Widget _priorityItem(String value, String label) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: _priorityColor(value),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _participantsField(List<dynamic> users) {
    final p = _p;
    final filtered = _filteredParticipants(users);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _fieldLabel('PARTICIPANTS')),
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: p.unreadBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _participantIds.length.toString() + ' Selected',
                  style: TextStyle(
                    color: p.link,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: p.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 4),
                child: TextField(
                  controller: _participantSearch,
                  onChanged: (query) => setState(() => _participantQuery = query),
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: p.ink, fontSize: 12),
                  decoration: _fieldDecoration(
                    'Search participants...',
                    prefix: Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: p.searchIcon,
                    ),
                    suffix: _participantQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _participantSearch.clear();
                              setState(() => _participantQuery = '');
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              size: 17,
                              color: p.muted,
                            ),
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 174,
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _participantQuery.trim().isEmpty
                              ? 'No participants available'
                              : 'No matching participants',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(5, 4, 5, 6),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final user = filtered[index];
                          final id = user['id'].toString();
                          final selected = _participantIds.contains(id);
                          final name = _userName(user);
                          final hash = id.codeUnits.fold<int>(
                            0,
                            (total, code) => total + code,
                          );
                          const colors = [
                            Color(0xFF657FF1),
                            Color(0xFF2B9DD7),
                            Color(0xFF9B65E7),
                            Color(0xFF17BFA1),
                          ];
                          final accent = colors[hash % colors.length];

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    _participantIds.remove(id);
                                  } else {
                                    _participantIds.add(id);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.business_outlined,
                                        size: 17,
                                        color: accent,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: p.ink,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (_userSubtitle(user).isNotEmpty)
                                            Text(
                                              _userSubtitle(user),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: p.muted,
                                                fontSize: 10,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 19,
                                      height: 19,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.primary
                                            : p.card,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: selected
                                              ? AppColors.primary
                                              : p.cardBorder,
                                        ),
                                      ),
                                      child: selected
                                          ? const Icon(
                                              Icons.check_rounded,
                                              size: 14,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _usersFields() {
    final p = _p;
    return FutureBuilder<List<dynamic>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'თანამშრომლების ჩატვირთვის შეცდომა: ' +
                snapshot.error.toString(),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }
        final users = snapshot.data ?? <dynamic>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fieldLabel('ASSIGNED TO'),
            _dropdown<String>(
              value: _assigneeId,
              hint: 'Unassigned',
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Unassigned'),
                ),
                ...users.map(
                  (user) => DropdownMenuItem<String>(
                    value: user['id'].toString(),
                    child: Text(
                      _userName(user),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _assigneeId = value),
            ),
            const SizedBox(height: 18),
            _participantsField(users),
          ],
        );
      },
    );
  }

  Widget _priorityAndGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('PRIORITY'),
        _dropdown<String>(
          value: _priority,
          items: [
            DropdownMenuItem(value: 'LOW', child: _priorityItem('LOW', 'Low')),
            DropdownMenuItem(
              value: 'NORMAL',
              child: _priorityItem('NORMAL', 'Normal'),
            ),
            DropdownMenuItem(
              value: 'HIGH',
              child: _priorityItem('HIGH', 'High'),
            ),
            DropdownMenuItem(
              value: 'URGENT',
              child: _priorityItem('URGENT', 'Urgent'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _priority = value);
          },
        ),
        const SizedBox(height: 18),
        _fieldLabel('GROUP'),
        _dropdown<String>(
          value: _groupId,
          hint: 'Ungrouped',
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Ungrouped'),
            ),
            ...widget.groups.map(
              (group) => DropdownMenuItem<String>(
                value: group['id'].toString(),
                child: Text(
                  group['name'].toString(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _groupId = value),
        ),
      ],
    );
  }

  Widget _actionField({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final p = _p;
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: p.link, size: 17),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.link,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final p = _p;
    return Container(
      decoration: BoxDecoration(
        color: p.page,
        border: Border(top: BorderSide(color: p.cardBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: p.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Container(
              height: 47,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                gradient: const LinearGradient(
                  colors: [
                    AppColors.gradientStart,
                    AppColors.gradientEnd,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.23),
                    blurRadius: 13,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _submit,
                  borderRadius: BorderRadius.circular(25),
                  child: const Center(
                    child: Text(
                      'Save task',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight =
        media.size.height - keyboardInset - media.padding.top;
    final sheetHeight = (availableHeight * 0.94).clamp(0.0, media.size.height);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: sheetHeight),
          child: Material(
            color: p.page,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(27),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 17, 15, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF89B0FF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'New task',
                          style: TextStyle(
                            color: p.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      Material(
                        color: p.card,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            height: 34,
                            width: 34,
                            child: Icon(
                              Icons.close_rounded,
                              size: 19,
                              color: p.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _titleField(),
                        const SizedBox(height: 18),
                        _descriptionField(),
                        const SizedBox(height: 19),
                        _usersFields(),
                        const SizedBox(height: 19),
                        _priorityAndGroup(),
                        const SizedBox(height: 17),
                        _actionField(
                          icon: Icons.calendar_today_outlined,
                          label: _dueDate == null
                              ? 'Select Due Date'
                              : _dueDate!.toIso8601String().substring(0, 10),
                          onPressed: _pickDate,
                        ),
                        const SizedBox(height: 10),
                        _actionField(
                          icon: Icons.attach_file_rounded,
                          label: _file?.name ?? 'Choose File',
                          onPressed: _pickingFile ? null : _pickFile,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
