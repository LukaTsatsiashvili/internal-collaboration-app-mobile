import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';

import 'task_group_dialog.dart';
import 'task_create_sheet.dart';

import '../features/tasks/data/task_service.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  final TaskService _taskService = TaskService();
  late TabController _tabController;

  bool _isLoading = true;
  bool _isCreatingGroup = false;
  bool _isCreatingTask = false;
  int _loadRequestId = 0;
  List<dynamic> _tasks = [];
  List<dynamic> _groups = [];
  String? _errorMessage;

  final List<String?> _statuses = [null, 'OPEN', 'IN_PROGRESS', 'COMPLETED'];
  static const List<String> _viewLabels = ['All', 'Active', 'Assigned', 'Created', 'Participant', 'Completed'];
  String _selectedView = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadData();
      }
    });
    _loadData();
  }

  Future<void> _loadData() async {
    final requestId = ++_loadRequestId;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final statusFilter = _statuses[_tabController.index];
      final results = await Future.wait([
        _taskService.getTasks(status: statusFilter),
        _taskService.getTaskGroups(),
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _tasks = results[0];
        _groups = results[1];
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
    _tabController.dispose();
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

  // The new view labels are visual-only pending backend filtering work.
  // Existing All/Open/In Progress/Completed API filters remain in Filter.
  void _chooseView(String label) {
    setState(() => _selectedView = label);
    final target = label == 'Completed' ? 3 : 0;
    if (_tabController.index != target) _tabController.animateTo(target);
  }

  void _chooseLegacyStatus(int index) {
    setState(() => _selectedView = index == 3 ? 'Completed' : index == 0 ? 'All' : 'Active');
    if (_tabController.index == index) {
      _loadData();
    } else {
      _tabController.animateTo(index);
    }
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
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
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Text('Search tasks', style: TextStyle(
            color: _p.hintText, fontSize: 11,
          )),
        )),
        PopupMenuButton<int>(
          tooltip: 'Existing status filters',
          initialValue: _tabController.index,
          onSelected: _chooseLegacyStatus,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 0, child: Text('All')),
            PopupMenuItem(value: 1, child: Text('Open')),
            PopupMenuItem(value: 2, child: Text('In Progress')),
            PopupMenuItem(value: 3, child: Text('Completed')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.filter_list_rounded, size: 19, color: _p.secondaryText),
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.swap_vert_rounded, size: 17, color: _p.muted),
        const SizedBox(width: 4),
        Text('Default', style: TextStyle(
          color: _p.secondaryText, fontSize: 11, fontWeight: FontWeight.w700,
        )),
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
    final tasksById = {
      for (final task in _tasks) task['id']?.toString(): task,
    };
    for (final task in _tasks) {
      String? groupId = task['personalLayout']?['groupId']?.toString();
      if (groupId == null && task['parentTaskId'] != null) {
        final parent = tasksById[task['parentTaskId']?.toString()];
        groupId = parent?['personalLayout']?['groupId']?.toString();
      }
      groupedTasks[groupedTasks.containsKey(groupId) ? groupId : null]!.add(task);
    }
    final keys = <String?>[..._groups.map((g) => g['id'].toString()), null];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(13, 0, 13, 22),
      children: keys.map((groupId) {
        final name = groupId == null
            ? 'Ungrouped'
            : _groups.firstWhere((g) => g['id'].toString() == groupId)['name'].toString();
        return _taskGroup(groupId, name, groupedTasks[groupId] ?? <dynamic>[]);
      }).toList(),
    );
  }

  Widget _taskGroup(String? groupId, String name, List<dynamic> tasks) {
    final p = _p;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('task-group-' + (groupId ?? 'ungrouped')),
        initiallyExpanded: true,
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
            onPressed: _isCreatingTask ? null : _showNewTaskBottomSheet,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('+ Add task', style: TextStyle(
              color: p.link, fontSize: 10, fontWeight: FontWeight.w600,
            )),
          ),
          const SizedBox(width: 4),
          Icon(Icons.edit_outlined, color: p.muted, size: 16),
          const SizedBox(width: 8),
          Icon(Icons.delete_outline_rounded, color: p.muted, size: 17),
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
    final priorityText = priority.isEmpty ? 'Normal'
        : priority.substring(0, 1) + priority.substring(1).toLowerCase();

    return Container(
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
            PopupMenuButton<String>(
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
        ]),
      ]),
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

  Future<void> _showNewTaskBottomSheet() async {
    // The sheet owns its controllers. It only returns an immutable draft.
    final draft = await showModalBottomSheet<TaskCreationDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TaskCreateSheet(service: _taskService, groups: _groups),
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
