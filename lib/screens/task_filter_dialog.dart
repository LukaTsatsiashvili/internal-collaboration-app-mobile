import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../core/theme/app_dropdown_theme.dart';
import 'task_advanced_filters.dart';

class TaskFilterDialog extends StatefulWidget {
  final TaskAdvancedFilters initial;
  final List<dynamic> people;
  final List<dynamic> groups;
  final List<dynamic> departments;

  const TaskFilterDialog({
    super.key,
    required this.initial,
    required this.people,
    required this.groups,
    required this.departments,
  });

  @override
  State<TaskFilterDialog> createState() => _TaskFilterDialogState();
}

class _TaskFilterDialogState extends State<TaskFilterDialog> {
  late final TaskAdvancedFilters _draft;
  final Map<String, TextEditingController> _search = {};

  static const _statuses = [
    'DRAFT', 'OPEN', 'IN_PROGRESS', 'BLOCKED',
    'WAITING_REVIEW', 'COMPLETED', 'CANCELLED',
  ];
  static const _priorities = ['LOW', 'NORMAL', 'HIGH', 'URGENT'];

  @override
  void initState() {
    super.initState();
    _draft = widget.initial.copy();
    for (final name in ['assignee', 'creator', 'participant', 'group', 'department']) {
      _search[name] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _search.values) {
      controller.dispose();
    }
    super.dispose();
  }

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;

  void _toggle(Set<String> values, String id) {
    setState(() {
      if (!values.add(id)) values.remove(id);
    });
  }

  Widget _heading(String name) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          name,
          style: TextStyle(
            color: _p.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _check(bool checked) => Container(
        width: 17,
        height: 17,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? AppColors.primary : _p.card,
          border: Border.all(
              color: checked ? AppColors.primary : _p.cardBorder),
          borderRadius: BorderRadius.circular(5),
        ),
        child: checked
            ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
            : null,
      );

  Widget _chips(String heading, List<String> choices, Set<String> values) {
    final p = _p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(heading),
        LayoutBuilder(
          builder: (context, layout) {
            const space = 8.0;
            final halfWidth = (layout.maxWidth - space) / 2;
            return Wrap(
              spacing: space,
              runSpacing: 7,
              children: [
                for (var i = 0; i < choices.length; i++)
                  SizedBox(
                    width: choices.length.isOdd && i == choices.length - 1
                        ? layout.maxWidth
                        : halfWidth,
                    child: Builder(
                      builder: (context) {
                        final option = choices[i];
                        final checked = values.contains(option);
                        return Material(
                          color: checked ? p.unreadBackground : p.card,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: checked
                                  ? p.link.withValues(alpha: 0.3)
                                  : p.cardBorder,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _toggle(values, option),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 12),
                              child: Row(
                                children: [
                                  _check(checked),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      option.replaceAll('_', ' '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: checked
                                            ? p.link
                                            : option == 'URGENT'
                                                ? const Color(0xFFF16A7A)
                                                : p.secondaryText,
                                      ),
                                    ),
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
            );
          },
        ),
      ],
    );
  }

  String _userName(dynamic value) {
    final display = (value['displayName'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;
    final first = (value['firstName'] ?? '').toString().trim();
    final last = (value['lastName'] ?? '').toString().trim();
    final full = [first, last].where((part) => part.isNotEmpty).join(' ');
    return full.isEmpty ? (value['email'] ?? '').toString() : full;
  }

  Widget _list({
    required String heading,
    required String keyName,
    required List<dynamic> items,
    required Set<String> selected,
    required String Function(dynamic) title,
    required IconData icon,
    String? nullId,
    String? nullTitle,
  }) {
    final p = _p;
    final controller = _search[keyName]!;
    final choices = <Map<String, String>>[
      if (nullId != null && nullTitle != null)
        {'id': nullId, 'title': nullTitle, 'subtitle': ''},
      ...items.where((item) => item['id'] != null).map(
        (item) => {
          'id': item['id'].toString(),
          'title': title(item),
          'subtitle': (item['email'] ?? item['code'] ?? '').toString(),
        },
      ),
    ];
    final query = controller.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? choices
        : choices.where((item) =>
            item['title']!.toLowerCase().contains(query) ||
            item['subtitle']!.toLowerCase().contains(query)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(heading),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.card,
            border: Border.all(color: p.cardBorder),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 9, 9, 2),
                child: TextField(
                  controller: controller,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: p.ink, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search ' + heading.toLowerCase() + '...',
                    hintStyle: TextStyle(color: p.hintText, fontSize: 11),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: p.searchIcon),
                    suffixIcon: controller.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              controller.clear();
                              setState(() {});
                            },
                            icon: Icon(Icons.close_rounded,
                                size: 16, color: p.muted),
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: p.searchBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(color: p.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(color: p.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(color: p.link),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 157,
                child: visible.isEmpty
                    ? Center(
                        child: Text('No matches',
                          style: TextStyle(color: p.muted, fontSize: 11)),
                      )
                    : ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          final id = item['id']!;
                          final chosen = selected.contains(id);
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggle(selected, id),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: p.unreadBackground,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Icon(icon,
                                          size: 15, color: p.link),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        item['title']!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: p.ink,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    _check(chosen),
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

  Widget _dropdown({
    required String heading,
    required String selected,
    required Map<String, String> choices,
    required ValueChanged<String> onSelect,
  }) {
    final p = _p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(heading),
        AppDropdownTheme(
          child: LayoutBuilder(
            builder: (context, bounds) => PopupMenuButton<String>(
              tooltip: heading,
              position: PopupMenuPosition.under,
              offset: AppDropdownTheme.menuGap,
              color: p.card,
              elevation: 9,
              constraints: AppDropdownTheme.menuBounds(
                bounds.maxWidth, 260,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
                side: BorderSide(color: p.cardBorder),
              ),
              onSelected: onSelect,
              itemBuilder: (context) => [
                for (final choice in choices.entries)
                  PopupMenuItem<String>(
                    value: choice.key,
                    height: 45,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            choice.value,
                            style: TextStyle(
                              color: selected == choice.key ? p.link : p.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (selected == choice.key)
                          Icon(Icons.check_rounded, size: 17, color: p.link),
                      ],
                    ),
                  ),
              ],
              child: Container(
                height: 45,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: p.card,
                  border: Border.all(color: p.cardBorder),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        choices[selected] ?? choices.values.first,
                        style: TextStyle(
                          color: p.secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: p.muted, size: 19),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _dateText(DateTime? value) {
    if (value == null) return 'mm/dd/yyyy';
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return m + '/' + d + '/' + value.year.toString();
  }

  Widget _dateField(
      String heading, DateTime? selected, ValueChanged<DateTime?> onChange) {
    final p = _p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(heading),
        Material(
          color: p.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: p.cardBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () async {
              final value = await showDatePicker(
                context: context,
                initialDate: selected ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (!mounted || value == null) return;
              onChange(value);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 9, vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateText(selected),
                      style: TextStyle(
                        color: selected == null ? p.hintText : p.ink,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  if (selected != null)
                    IconButton(
                      constraints: const BoxConstraints(
                          minHeight: 20, minWidth: 20),
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.close_rounded,
                          size: 16, color: p.muted),
                      onPressed: () => onChange(null),
                    )
                  else
                    Icon(Icons.calendar_today_outlined,
                        color: p.link, size: 15),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer() => Container(
    decoration: BoxDecoration(
      color: _p.panel,
      border: Border(top: BorderSide(color: _p.cardBorder)),
    ),
    padding: const EdgeInsets.fromLTRB(15, 11, 15, 14),
    child: Container(
      height: 47,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(_draft.copy()),
          borderRadius: BorderRadius.circular(16),
          child: const Center(
            child: Text(
              'Done  ✓',
              style: TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Dialog(
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
          maxHeight: MediaQuery.sizeOf(context).height * 0.91,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 13, 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF89B0FF),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Filter tasks',
                          style: TextStyle(
                            color: p.ink, fontSize: 18,
                            fontWeight: FontWeight.w800,
                          )),
                        const SizedBox(height: 4),
                        Text('These filters refine the selected quick filter.',
                          style: TextStyle(
                            color: p.muted, fontSize: 10.5,
                          )),
                      ],
                    ),
                  ),
                  Material(
                    color: p.card,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded,
                          color: p.muted, size: 19),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Row(
                children: [
                  if (_draft.activeCount > 0)
                    TextButton(
                      onPressed: () => setState(_draft.clear),
                      child: Text('Clear all',
                        style: TextStyle(
                          color: p.link, fontSize: 11,
                          fontWeight: FontWeight.w700,
                        )),
                    ),
                  const Spacer(),
                  if (_draft.activeCount > 0)
                    Text(
                      _draft.activeCount.toString() + ' ACTIVE ' +
                          (_draft.activeCount == 1 ? 'FILTER' : 'FILTERS'),
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 9.5, fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: p.cardBorder),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(15, 16, 15, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _chips('STATUS', _statuses, _draft.statuses),
                    const SizedBox(height: 21),
                    _chips('PRIORITY', _priorities, _draft.priorities),
                    const SizedBox(height: 21),
                    _dropdown(
                      heading: 'Due date',
                      selected: _draft.due,
                      choices: const {
                        'any': 'Any Due Date',
                        'overdue': 'Overdue',
                        'today': 'Due Today',
                        'next7': 'Due In Next 7 Days',
                        'no_due': 'No Due Date',
                      },
                      onSelect: (value) => setState(() => _draft.due = value),
                    ),
                    const SizedBox(height: 20),
                    _list(
                      heading: 'Assigned to', keyName: 'assignee',
                      items: widget.people, selected: _draft.assigneeIds,
                      title: _userName, icon: Icons.person_outline_rounded,
                      nullId: '__unassigned__', nullTitle: 'Unassigned',
                    ),
                    const SizedBox(height: 20),
                    _list(
                      heading: 'Created by', keyName: 'creator',
                      items: widget.people, selected: _draft.creatorIds,
                      title: _userName, icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 20),
                    _list(
                      heading: 'Participant', keyName: 'participant',
                      items: widget.people, selected: _draft.participantIds,
                      title: _userName, icon: Icons.people_outline_rounded,
                    ),
                    const SizedBox(height: 20),
                    _list(
                      heading: 'Personal group', keyName: 'group',
                      items: widget.groups, selected: _draft.groupIds,
                      title: (item) => (item['name'] ?? '').toString(),
                      icon: Icons.folder_outlined,
                      nullId: '__ungrouped__', nullTitle: 'Ungrouped',
                    ),
                    const SizedBox(height: 20),
                    _list(
                      heading: 'Department', keyName: 'department',
                      items: widget.departments,
                      selected: _draft.departmentIds,
                      title: (item) => (item['name'] ?? '').toString(),
                      icon: Icons.business_outlined,
                      nullId: '__no_department__', nullTitle: 'No department',
                    ),
                    const SizedBox(height: 20),
                    _dropdown(
                      heading: 'Attachments',
                      selected: _draft.attachments,
                      choices: const {
                        'any': 'Any',
                        'with': 'Has Attachments',
                        'without': 'Has No Attachments',
                      },
                      onSelect: (value) =>
                          setState(() => _draft.attachments = value),
                    ),
                    const SizedBox(height: 19),
                    Row(
                      children: [
                        Expanded(
                          child: _dateField(
                            'Created from', _draft.createdFrom,
                            (value) => setState(
                                () => _draft.createdFrom = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dateField(
                            'Created to', _draft.createdTo,
                            (value) => setState(() => _draft.createdTo = value),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }
}
