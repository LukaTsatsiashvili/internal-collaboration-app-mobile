import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../core/theme/app_dropdown_theme.dart';

import 'task_group_dialog.dart';
import 'task_create_sheet.dart';
import 'task_filter_dialog.dart';
import 'task_details_sheet.dart';
import 'task_advanced_filters.dart';

import '../features/tasks/data/task_service.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, this.service, this.openCreateOnStart = false});

  /// Optional service injection keeps group workflows testable.
  final TaskService? service;
  /// Dashboard quick action opens the existing task creation sheet.
  final bool openCreateOnStart;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final TaskService _taskService;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  TaskAdvancedFilters _advancedFilters = TaskAdvancedFilters();
  String? _currentUserId;
  String _selectedSort = 'Default';

  bool _isLoading = true;
  bool _isCreatingGroup = false;
  bool _isCreatingTask = false;
  String? _busyGroupId;
  int _loadRequestId = 0;
  List<dynamic> _tasks = [];
  List<dynamic> _groups = [];
  String? _errorMessage;

  static const List<String> _viewLabels = [
    'All', 'Active', 'Assigned', 'Created', 'Participant', 'Completed',
  ];
  static const List<String> _sortOptions = [
    'Default',
    'Due date · earliest',
    'Due date · latest',
    'Priority · high to low',
    'Priority · low to high',
    'Created · newest',
    'Created · oldest',
    'Title · A to Z',
    'Title · Z to A',
    'Status',
  ];
  static const Map<String, int> _priorityOrder = {
    'LOW': 0, 'NORMAL': 1, 'HIGH': 2, 'URGENT': 3,
  };
  static const Map<String, int> _statusOrder = {
    'DRAFT': 0, 'OPEN': 1, 'IN_PROGRESS': 2, 'BLOCKED': 3,
    'WAITING_REVIEW': 4, 'COMPLETED': 5, 'CANCELLED': 6,
  };
  String _selectedView = 'All';

  @override
  void initState() {
    super.initState();
    _taskService = widget.service ?? TaskService();
    // Wait for personal groups before opening the Dashboard-created form:
    // otherwise its Group dropdown would be incorrectly empty at launch.
    final loading = _loadData();
    if (widget.openCreateOnStart) {
      loading.then((_) {
        if (mounted) _showNewTaskBottomSheet();
      });
    }
  }

  Future<void> _loadData() async {
    final requestId = ++_loadRequestId;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch the full accessible list once: every category/search/sort is
      // applied locally, so switching tabs never triggers new requests.
      final results = await Future.wait<dynamic>([
        _taskService.getTasks(),
        _taskService.getTaskGroups(),
        _currentUserId == null
            ? _taskService.getCurrentUserId()
            : Future<String>.value(_currentUserId!),
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _tasks = results[0] as List<dynamic>;
        _groups = results[1] as List<dynamic>;
        _currentUserId = results[2] as String;
      });
    } catch (error) {
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _errorMessage = error.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted && requestId == _loadRequestId) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _loadRequestId++;
    _searchController.dispose();
    super.dispose();
  }


  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;
  bool get _dark => Theme.of(context).brightness == Brightness.dark;

  BoxDecoration _panel({double radius = 20}) => BoxDecoration(
    color: _p.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _p.cardBorder),
    boxShadow: [
      BoxShadow(
        color: _p.panelShadow,
        blurRadius: 18,
        offset: const Offset(0, 5),
      ),
    ],
  );

  // These six views are mutually exclusive; each reflects the current user
  // and the exact status fields returned by the dev-luka backend.
  void _chooseView(String label) {
    if (_selectedView == label) return;
    setState(() => _selectedView = label);
  }

  bool _matchesCategory(dynamic task) {
    final status = (task['status'] ?? '').toString().toUpperCase();
    final userId = _currentUserId;
    switch (_selectedView) {
      case 'Active':
        // Match the web TasksPage quick filter: every status except done
        // and cancelled (including drafts) is considered active.
        return status != 'COMPLETED' && status != 'CANCELLED';
      case 'Assigned':
        return userId != null && task['assigneeId']?.toString() == userId;
      case 'Created':
        return userId != null && task['creatorId']?.toString() == userId;
      case 'Participant':
        final participants = task['participants'];
        return userId != null &&
            participants is List &&
            participants.any((p) =>
                p is Map &&
                (p['userId']?.toString() == userId ||
                    (p['user'] is Map &&
                        p['user']['id']?.toString() == userId)));
      case 'Completed':
        return status == 'COMPLETED';
      default:
        return true;
    }
  }

  List<dynamic> _filterPeople() {
    // Identical to the web Tasks page: people already mentioned in any
    // accessible task. No separate users.read permission is needed.
    final people = <String, dynamic>{};
    for (final task in _tasks) {
      for (final person in [task['creator'], task['assignee']]) {
        if (person is Map && person['id'] != null) {
          people[person['id'].toString()] = person;
        }
      }
      final participants = task['participants'];
      if (participants is List) {
        for (final participant in participants) {
          if (participant is Map && participant['user'] is Map) {
            final user = participant['user'];
            if (user['id'] != null) {
              people[user['id'].toString()] = user;
            }
          }
        }
      }
    }
    final list = people.values.toList();
    list.sort((a, b) => (a['displayName'] ?? a['email'] ?? '')
        .toString().toLowerCase().compareTo(
        (b['displayName'] ?? b['email'] ?? '').toString().toLowerCase()));
    return list;
  }

  List<dynamic> _filterDepartments() {
    final values = <String, dynamic>{};
    for (final task in _tasks) {
      final department = task['department'];
      if (department is Map && department['id'] != null) {
        values[department['id'].toString()] = department;
      }
    }
    final list = values.values.toList();
    list.sort((a, b) => (a['name'] ?? '').toString().toLowerCase()
        .compareTo((b['name'] ?? '').toString().toLowerCase()));
    return list;
  }

  Future<void> _openAdvancedFilters() async {
    final selection = await showDialog<TaskAdvancedFilters>(
      context: context,
      builder: (context) => TaskFilterDialog(
        initial: _advancedFilters,
        people: _filterPeople(),
        groups: _groups,
        departments: _filterDepartments(),
      ),
    );
    if (!mounted || selection == null) return;
    setState(() => _advancedFilters = selection);
  }

  int _compareDate(dynamic first, dynamic second, {bool descending = false}) {
    final a = DateTime.tryParse((first ?? '').toString());
    final b = DateTime.tryParse((second ?? '').toString());
    // Missing dates are always last, in both directions.
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    final comparison = a.compareTo(b);
    return descending ? -comparison : comparison;
  }

  int _compareTasks(dynamic a, dynamic b) {
    switch (_selectedSort) {
      case 'Due date · earliest':
        return _compareDate(a['dueDate'], b['dueDate']);
      case 'Due date · latest':
        return _compareDate(a['dueDate'], b['dueDate'], descending: true);
      case 'Priority · high to low':
        return (_priorityOrder[(b['priority'] ?? '').toString()] ?? 1)
            .compareTo(_priorityOrder[(a['priority'] ?? '').toString()] ?? 1);
      case 'Priority · low to high':
        return (_priorityOrder[(a['priority'] ?? '').toString()] ?? 1)
            .compareTo(_priorityOrder[(b['priority'] ?? '').toString()] ?? 1);
      case 'Created · newest':
        return _compareDate(a['createdAt'], b['createdAt'], descending: true);
      case 'Created · oldest':
        return _compareDate(a['createdAt'], b['createdAt']);
      case 'Title · A to Z':
        return (a['title'] ?? '').toString().toLowerCase()
            .compareTo((b['title'] ?? '').toString().toLowerCase());
      case 'Title · Z to A':
        return (b['title'] ?? '').toString().toLowerCase()
            .compareTo((a['title'] ?? '').toString().toLowerCase());
      case 'Status':
        return (_statusOrder[(a['status'] ?? '').toString()] ?? 99)
            .compareTo(_statusOrder[(b['status'] ?? '').toString()] ?? 99);
      default:
        return 0;
    }
  }

  int _manualPosition(dynamic task) {
    final value = task['personalLayout']?['position'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 2147483647;
  }

  int _compareManualPosition(dynamic a, dynamic b) =>
      _manualPosition(a).compareTo(_manualPosition(b));

  void _sortWithinGroups(
    Map<String?, List<dynamic>> grouped,
    Map<String, int> originalOrder,
  ) {
    for (final tasks in grouped.values) {
      tasks.sort((a, b) {
        // Match the web's Default/manual position ordering, but only display
        // "Default" in the picker. Do not modify positions on the server.
        final comparison = _selectedSort == 'Default'
            ? _compareManualPosition(a, b)
            : _compareTasks(a, b);
        if (comparison != 0) return comparison;
        final manual = _compareManualPosition(a, b);
        if (manual != 0) return manual;
        // Stable tie-breaker for tasks with identical/missing positions.
        return (originalOrder[a['id']?.toString()] ?? 0)
            .compareTo(originalOrder[b['id']?.toString()] ?? 0);
      });
    }
  }

  String get _shortSortLabel {
    switch (_selectedSort) {
      case 'Due date · earliest': return 'Due ↑';
      case 'Due date · latest': return 'Due ↓';
      case 'Priority · high to low': return 'Priority ↓';
      case 'Priority · low to high': return 'Priority ↑';
      case 'Created · newest': return 'New ↑';
      case 'Created · oldest': return 'Old ↑';
      case 'Title · A to Z': return 'Title A-Z';
      case 'Title · Z to A': return 'Title Z-A';
      case 'Status': return 'Status';
      default: return 'Default';
    }
  }

  Widget _sortMenu() {
    final p = _p;
    // Local theme prevents tap/hover feedback in the popup without changing
    // the persistent blue background of the chosen sorting option.
    return AppDropdownTheme(
      child: PopupMenuButton<String>(
      tooltip: 'Sort tasks',
      position: PopupMenuPosition.under,
      offset: AppDropdownTheme.menuGap,
      // No initialValue: it makes Flutter pre-scroll the selected row into
      // position, cutting off the first Default item on smaller screens.
      onSelected: (value) => setState(() => _selectedSort = value),
      constraints: BoxConstraints(
        minWidth: 250,
        maxWidth: (MediaQuery.sizeOf(context).width - 28)
            .clamp(250.0, 360.0).toDouble(),
        maxHeight: MediaQuery.sizeOf(context).height * 0.67,
      ),
      color: p.card,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(23),
        side: BorderSide(color: p.cardBorder),
      ),
      itemBuilder: (context) {
        final widgets = <PopupMenuEntry<String>>[];
        for (var i = 0; i < _sortOptions.length; i++) {
          if (const {3, 5, 7, 9}.contains(i)) {
            widgets.add(PopupMenuDivider(height: 12));
          }
          final label = _sortOptions[i];
          final selected = label == _selectedSort;
          widgets.add(
            PopupMenuItem<String>(
              value: label,
              height: i == 0 || i == _sortOptions.length - 1 ? 63 : 51,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: selected ? p.unreadBackground : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: selected
                      ? Border.all(color: p.link.withValues(alpha: 0.14))
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected ? p.link : p.secondaryText,
                          fontSize: 12.5,
                          fontWeight: selected
                              ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_rounded, color: p.link, size: 19),
                  ],
                ),
              ),
            ),
          );
        }
        return widgets;
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_vert_rounded, size: 17,
              color: _selectedSort == 'Default' ? p.muted : p.link),
          const SizedBox(width: 4),
          Text(
            _shortSortLabel,
            style: TextStyle(
              color: _selectedSort == 'Default' ? p.secondaryText : p.link,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _headerButton(String title, IconData icon, VoidCallback? onPressed, {bool primary = false}) {
    final p = _p;
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(17),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: primary ? null : p.card,
              gradient: primary ? const LinearGradient(colors: [
                AppColors.gradientStart, AppColors.gradientEnd,
              ]) : null,
              border: primary ? null : Border.all(color: p.cardBorder),
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: primary ? AppColors.primary.withValues(alpha: 0.20) : p.cardShadow,
                  blurRadius: 9,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: primary ? Colors.white : p.secondaryText),
              const SizedBox(width: 4),
              Text(title, style: TextStyle(
                color: primary ? Colors.white : p.secondaryText,
                fontSize: 10.5, fontWeight: FontWeight.w700,
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(17, 14, 15, 13),
    child: Row(children: [
      Expanded(child: Text('Tasks', style: TextStyle(
        color: _p.ink, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.5,
      ))),
      _headerButton('New group', Icons.create_new_folder_outlined,
        _isCreatingGroup ? null : _showNewGroupDialog),
      const SizedBox(width: 7),
      _headerButton('New task', Icons.add_rounded,
        _isCreatingTask ? null : _showNewTaskBottomSheet, primary: true),
    ]),
  );

  Widget _tabs() => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      itemCount: _viewLabels.length,
      separatorBuilder: (_, __) => const SizedBox(width: 3),
      itemBuilder: (context, index) {
        final text = _viewLabels[index], active = text == _selectedView;
        return InkWell(
          onTap: () => _chooseView(text),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: active ? _p.unreadBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(text, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: active ? _p.link : _p.muted,
            )),
          ),
        );
      },
    ),
  );

  Widget _toolbar() => Container(
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
    decoration: _panel(),
    child: Column(children: [
      _tabs(),
      const SizedBox(height: 5),
      Divider(color: _p.cardBorder, height: 1),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (text) => setState(() => _searchQuery = text),
            textInputAction: TextInputAction.search,
            style: TextStyle(color: _p.ink, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Search tasks',
              hintStyle: TextStyle(color: _p.hintText, fontSize: 11),
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 9,
              ),
              suffixIconConstraints: const BoxConstraints(
                minHeight: 32, minWidth: 32,
              ),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: _p.muted,
                      ),
                    ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Filter tasks',
          onPressed: _openAdvancedFilters,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.filter_list_rounded,
                size: 19,
                color: _advancedFilters.activeCount == 0
                    ? _p.secondaryText : _p.link,
              ),
              if (_advancedFilters.activeCount > 0)
                Positioned(
                  right: -5, top: -5,
                  child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _sortMenu(),
        const SizedBox(width: 11),
      ]),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _p.page,
    body: SafeArea(
      child: Column(children: [
        _header(),
        _toolbar(),
        Expanded(child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(_errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ))
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: _buildGroupedTaskList(),
                  ),
        ),
      ]),
    ),
  );

  Widget _buildGroupedTaskList() {
    // Existing user-specific grouping and parent-task fallback are unchanged.
    final Map<String?, List<dynamic>> groupedTasks = {
      for (final group in _groups) group['id'].toString(): <dynamic>[],
      null: <dynamic>[],
    };
    // Compose quick tab, advanced filters, and text search. For subtasks,
    // the parent's personal group is used just like in the web Tasks page.
    final query = _searchQuery.trim().toLowerCase();
    final tasksById = {
      for (final task in _tasks) task['id']?.toString(): task,
    };
    for (final task in _tasks) {
      String? groupId = task['personalLayout']?['groupId']?.toString();
      if (groupId == null && task['parentTaskId'] != null) {
        final parent = tasksById[task['parentTaskId']?.toString()];
        groupId = parent?['personalLayout']?['groupId']?.toString();
      }

      if (!_matchesCategory(task) ||
          !_advancedFilters.matches(task, effectiveGroupId: groupId)) {
        continue;
      }
      if (query.isNotEmpty) {
        final title = (task['title'] ?? '').toString().toLowerCase();
        final description = (task['description'] ?? '').toString().toLowerCase();
        if (!title.contains(query) && !description.contains(query)) continue;
      }
      groupedTasks[groupedTasks.containsKey(groupId) ? groupId : null]!
          .add(task);
    }
    final originalOrder = <String, int>{
      for (var i = 0; i < _tasks.length; i++)
        if (_tasks[i]['id'] != null) _tasks[i]['id'].toString(): i,
    };
    _sortWithinGroups(groupedTasks, originalOrder);
    final keys = <String?>[..._groups.map((g) => g['id'].toString()), null];
    final hasFilters = query.isNotEmpty ||
        _selectedView != 'All' || _advancedFilters.activeCount > 0;
    final visibleKeys = hasFilters
        ? keys.where((key) => groupedTasks[key]!.isNotEmpty).toList()
        : keys;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(13, 0, 13, 22),
      children: [
        if (visibleKeys.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 56),
            child: Center(
              child: Text(
                'No matching tasks',
                style: TextStyle(color: _p.muted, fontSize: 13),
              ),
            ),
          ),
        ...visibleKeys.map((groupId) {
          final name = groupId == null
              ? 'Ungrouped'
              : _groups.firstWhere((g) => g['id'].toString() == groupId)['name'].toString();
          return _taskGroup(groupId, name, groupedTasks[groupId] ?? <dynamic>[]);
        }),
      ],
    );
  }

  Widget _taskGroup(String? groupId, String name, List<dynamic> tasks) {
    final p = _p;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // Empty groups start closed and groups with tasks start open;
        // PageStorage remembers manual expanded/collapsed changes afterwards.
        key: PageStorageKey<String>(
          'task-group-' + (groupId ?? 'ungrouped') +
              (tasks.isEmpty ? '-empty' : '-populated'),
        ),
        initiallyExpanded: tasks.isNotEmpty,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: p.muted,
        collapsedIconColor: p.muted,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(children: [
          Flexible(child: Text(name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.ink, fontSize: 12, fontWeight: FontWeight.w800),
          )),
          const SizedBox(width: 5),
          Text(tasks.length.toString() + (tasks.length == 1 ? ' task' : ' tasks'),
            style: TextStyle(color: p.muted, fontSize: 10)),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
            onPressed: _isCreatingTask ? null
                : () => _showNewTaskBottomSheet(initialGroupId: groupId),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('+ Add task', style: TextStyle(
              color: p.link, fontSize: 10, fontWeight: FontWeight.w600,
            )),
          ),
          if (groupId != null) ...[
            const SizedBox(width: 4),
            IconButton(
              key: ValueKey('edit-task-group-$groupId'),
              tooltip: 'Rename $name',
              onPressed: _busyGroupId == null
                  ? () => _renameTaskGroup(groupId, name) : null,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.edit_outlined, color: p.muted, size: 17),
            ),
            IconButton(
              key: ValueKey('delete-task-group-$groupId'),
              tooltip: 'Delete $name',
              onPressed: _busyGroupId == null
                  ? () => _deleteTaskGroup(groupId, name) : null,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.delete_outline_rounded, color: p.muted, size: 18),
            ),
          ],
        ]),
        children: tasks.isEmpty
            ? [Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 16),
                child: Text('No tasks in this group.',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              )]
            : tasks.map(_buildTaskCard).toList(),
      ),
    );
  }

  String _dueDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return 'No due date';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[date.month - 1] + ' ' + date.day.toString() + ', ' + date.year.toString();
  }

  Widget _tag(String text, {Color? background, Color? foreground}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      color: background ?? _p.searchBackground,
    ),
    child: Text(text, style: TextStyle(
      color: foreground ?? _p.secondaryText,
      fontSize: 10, fontWeight: FontWeight.w700,
    )),
  );

  Future<void> _openTaskDetails(dynamic task) async {
    final id = task['id']?.toString();
    if (id == null || id.isEmpty) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.none,
      builder: (_) => TaskDetailsSheet(
        taskId: id,
        service: _taskService,
        groups: _groups,
      ),
    );
    // Refresh even after a system-back dismissal; the sheet may already
    // have saved status, layout, or comments on the backend.
    if (!mounted) return;
    await _loadData();
  }

  Widget _buildTaskCard(dynamic task) {
    final p = _p;
    final title = (task['title'] ?? '').toString();
    final description = (task['description'] ?? '').toString();
    final priority = (task['priority'] ?? 'NORMAL').toString().toUpperCase();
    final status = (task['status'] ?? 'OPEN').toString().toUpperCase();
    final due = _dueDate(task['dueDate']);
    final assignee = (task['assignee']?['displayName'] ??
      task['assignee']?['email'] ?? 'Unassigned').toString();
    final completed = status == 'COMPLETED';
    final high = priority == 'HIGH' || priority == 'URGENT';
    final statusText = status == 'IN_PROGRESS' ? 'In Progress'
        : status == 'OPEN' ? 'Open'
        : status == 'COMPLETED' ? 'Completed'
        : status;
    // The dev-luka backend includes _count.comments in task list responses.
    final rawCommentCount =
        task['_count'] is Map ? task['_count']['comments'] : null;
    final int? commentCount = rawCommentCount is num
        ? rawCommentCount.toInt()
        : int.tryParse(rawCommentCount?.toString() ?? '');
    final priorityText = priority.isEmpty ? 'Normal'
        : priority.substring(0, 1) + priority.substring(1).toLowerCase();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTaskDetails(task),
      child: Container(
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
      decoration: _panel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 17, height: 17,
            decoration: BoxDecoration(
              color: completed ? p.unreadBackground : p.card,
              border: Border.all(color: completed ? p.link : p.cardBorder),
              borderRadius: BorderRadius.circular(5),
            ),
            child: completed ? Icon(Icons.check_rounded, size: 13, color: p.link) : null,
          ),
          const SizedBox(width: 9),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w800,
              )),
              const SizedBox(height: 3),
              Text(description.isEmpty ? 'No description' : description,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 10.5),
              ),
            ],
          )),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          Container(
            width: 25, height: 25,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.unreadBackground,
            ),
            child: Icon(assignee == 'Unassigned' ? Icons.question_mark_rounded
                : Icons.person_rounded, size: 15, color: p.link),
          ),
          const SizedBox(width: 7),
          Expanded(child: Text(assignee,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.secondaryText,
              fontSize: 10.5, fontWeight: FontWeight.w600),
          )),
          _tag(priorityText,
            background: high
                ? const Color(0xFFED9A16).withValues(alpha: _dark ? 0.19 : 0.10)
                : p.searchBackground,
            foreground: high ? const Color(0xFFED9A16) : p.secondaryText,
          ),
          if (task['parentTaskId'] == null)
            AppDropdownTheme(
              child: PopupMenuButton<String>(
                position: PopupMenuPosition.under,
                offset: AppDropdownTheme.menuGap,
              tooltip: 'Move to my group',
              icon: Icon(Icons.more_vert_rounded, color: p.muted, size: 19),
              padding: const EdgeInsets.only(left: 4),
              onSelected: (value) => _moveTaskToGroup(
                task['id'].toString(), value.isEmpty ? null : value,
              ),
              itemBuilder: (context) => [
                const PopupMenuItem<String>(value: '', child: Text('Ungrouped')),
                ..._groups.map((group) => PopupMenuItem<String>(
                  value: group['id'].toString(),
                  child: Text(group['name'].toString()),
                )),
              ],
              ),
            ),
        ]),
        const SizedBox(height: 11),
        Divider(height: 1, color: p.cardBorder),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.calendar_today_outlined, size: 13, color: p.muted),
          const SizedBox(width: 5),
          Expanded(child: Text(due,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted,
                fontWeight: FontWeight.w600, fontSize: 10),
          )),
          _tag(statusText),
          const SizedBox(width: 9),
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 13,
            color: p.muted,
          ),
          if (commentCount != null) ...[
            const SizedBox(width: 4),
            Text(
              commentCount.toString(),
              style: TextStyle(
                color: p.muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ]),
      ]),
      ),
    );
  }

  Future<void> _moveTaskToGroup(String taskId, String? groupId) async {
    try {
      await _taskService.moveTaskToGroup(taskId, groupId);
      if (!mounted) return;
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showNewGroupDialog() async {
    // The dialog only returns a value. It never performs an API call.
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const TaskGroupDialog(),
    );
    if (!mounted || name == null || _isCreatingGroup) return;

    setState(() => _isCreatingGroup = true);
    try {
      await _taskService.createTaskGroup(name: name);
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ჯგუფი წარმატებით შეიქმნა')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isCreatingGroup = false);
    }
  }

  Future<void> _renameTaskGroup(String groupId, String oldName) async {
    if (_busyGroupId != null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TaskGroupDialog(
        initialName: oldName, renameTitle: 'Rename task group',
      ),
    );
    if (!mounted || name == null || name == oldName ||
        _busyGroupId != null) return;
    setState(() => _busyGroupId = groupId);
    try {
      await _taskService.renameTaskGroup(id: groupId, name: name);
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ჯგუფის სახელი განახლებულია')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      if (mounted) setState(() => _busyGroupId = null);
    }
  }

  Future<void> _deleteTaskGroup(String groupId, String name) async {
    if (_busyGroupId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _p.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: _p.cardBorder),
        ),
        title: Text('Delete “$name”?', style: TextStyle(color: _p.ink)),
        content: Text(
          'Tasks in this group will move to Ungrouped for you. '
          'No tasks will be deleted, and other users are not affected.',
          style: TextStyle(color: _p.secondaryText, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.error,
              fontWeight: FontWeight.w700,
            )),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busyGroupId != null) return;
    setState(() => _busyGroupId = groupId);
    try {
      await _taskService.deleteTaskGroup(groupId);
      if (!mounted) return;
      setState(() => _advancedFilters.groupIds.remove(groupId));
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'ჯგუფი წაიშალა; დავალებები გადავიდა Ungrouped-ში',
        )),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      if (mounted) setState(() => _busyGroupId = null);
    }
  }

  Future<void> _showNewTaskBottomSheet({String? initialGroupId}) async {
    // The sheet owns its controllers. It only returns an immutable draft.
    final draft = await showModalBottomSheet<TaskCreationDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The sheet now renders its own inset, fully rounded card.
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.none,
      builder: (_) => TaskCreateSheet(
        service: _taskService,
        groups: _groups,
        initialGroupId: initialGroupId,
      ),
    );
    if (!mounted || draft == null || _isCreatingTask) return;
    setState(() => _isCreatingTask = true);

    try {
      final attachmentIds = <String>[];
      if (draft.attachment != null) {
        final bytes = await draft.attachment!.readAsBytes();
        if (!mounted) return;
        final fileId = await _taskService.uploadFileBytes(
          bytes,
          draft.attachment!.name,
        );
        if (!mounted) return;
        if (fileId == null) throw Exception('ფაილის ატვირთვა ვერ მოხერხდა');
        attachmentIds.add(fileId);
      }

      await _taskService.createTask(
        title: draft.title,
        description: draft.description,
        assigneeId: draft.assigneeId,
        groupId: draft.groupId,
        priority: draft.priority,
        dueDate: draft.dueDate,
        participantIds: draft.participantIds,
        attachmentIds: attachmentIds,
      );
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('დავალება წარმატებით შეიქმნა!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isCreatingTask = false);
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'IN_PROGRESS':
        return Colors.amber.shade300;
      case 'COMPLETED':
        return Colors.green.shade300;
      case 'BLOCKED':
        return Colors.red.shade300;
      default:
        return Colors.blue.shade200;
    }
  }
}
