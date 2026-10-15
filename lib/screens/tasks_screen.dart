import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New group',
            onPressed: _isCreatingGroup ? null : _showNewGroupDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Open'),
            Tab(text: 'In Progress'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _buildGroupedTaskList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreatingTask ? null : _showNewTaskBottomSheet,
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }

  Widget _buildGroupedTaskList() {
    final Map<String?, List<dynamic>> groupedTasks = {
      for (final group in _groups) group['id'].toString(): <dynamic>[],
      null: <dynamic>[],
    };
    final tasksById = {for (final task in _tasks) task['id']?.toString(): task};

    for (final task in _tasks) {
      // The backend returns each user's own layout, not the task's department.
      String? groupId = task['personalLayout']?['groupId']?.toString();
      // A subtask visually follows its parent when that parent is available.
      if (groupId == null && task['parentTaskId'] != null) {
        final parent = tasksById[task['parentTaskId']?.toString()];
        groupId = parent?['personalLayout']?['groupId']?.toString();
      }
      groupedTasks[groupedTasks.containsKey(groupId) ? groupId : null]!.add(
        task,
      );
    }

    final keys = <String?>[
      ..._groups.map((group) => group['id'].toString()),
      null,
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: keys.map((groupId) {
        final name = groupId == null
            ? 'Ungrouped'
            : _groups
                  .firstWhere(
                    (group) => group['id'].toString() == groupId,
                  )['name']
                  .toString();
        final groupTasks = groupedTasks[groupId] ?? <dynamic>[];
        return ExpansionTile(
          key: PageStorageKey<String>('task-group-${groupId ?? 'ungrouped'}'),
          initiallyExpanded: true,
          title: Text(
            '$name (${groupTasks.length} tasks)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          children: groupTasks.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text(
                      'No tasks in this group.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ]
              : groupTasks.map((task) => _buildTaskCard(task)).toList(),
        );
      }).toList(),
    );
  }

  // 🔹 გასწორებული ბარათი (მოხსნილია Pixel Overflow)
  Widget _buildTaskCard(dynamic task) {
    final title = task['title'] ?? '';
    final description = task['description'] ?? '';
    final status = task['status'] ?? 'OPEN';
    final dueDate = task['dueDate']?.toString().substring(0, 10);
    final assigneeName =
        task['assignee']?['displayName'] ??
        task['assignee']?['email'] ??
        'Unassigned';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.person,
                            size: 14,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              assigneeName,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (dueDate != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dueDate,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(status, style: const TextStyle(fontSize: 10)),
                  backgroundColor: _getStatusColor(status),
                  visualDensity: VisualDensity.compact,
                ),
                if (task['parentTaskId'] == null)
                  PopupMenuButton<String>(
                    tooltip: 'Move to my group',
                    icon: const Icon(Icons.drive_file_move_outline, size: 20),
                    onSelected: (value) => _moveTaskToGroup(
                      task['id'].toString(),
                      value.isEmpty ? null : value,
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: '',
                        child: Text('Ungrouped'),
                      ),
                      ..._groups.map(
                        (group) => PopupMenuItem<String>(
                          value: group['id'].toString(),
                          child: Text(group['name'].toString()),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
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
