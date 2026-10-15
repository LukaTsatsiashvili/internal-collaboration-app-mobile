import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../features/tasks/data/task_service.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with SingleTickerProviderStateMixin {
  final TaskService _taskService = TaskService();
  late TabController _tabController;

  bool _isLoading = true;
  List<dynamic> _tasks = [];
  List<dynamic> _departments = [];
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final statusFilter = _statuses[_tabController.index];
      final results = await Future.wait([
        _taskService.getTasks(status: statusFilter),
        _taskService.getDepartments(),
      ]);

      setState(() {
        _tasks = results[0];
        _departments = results[1];
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
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
            onPressed: _showNewGroupDialog,
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
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _buildGroupedTaskList(),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewTaskBottomSheet,
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }

  Widget _buildGroupedTaskList() {
    final Map<String?, List<dynamic>> groupedTasks = {};
    
    for (var dept in _departments) {
      groupedTasks[dept['id']] = [];
    }
    groupedTasks[null] = [];

    for (var task in _tasks) {
      final deptId = task['departmentId'] ?? task['department']?['id'];
      if (groupedTasks.containsKey(deptId)) {
        groupedTasks[deptId]!.add(task);
      } else {
        groupedTasks[null]!.add(task);
      }
    }

    final allKeys = [
      ..._departments.map((d) => d['id'] as String?),
      null
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: allKeys.map((deptId) {
        final deptName = deptId == null 
            ? 'Ungrouped' 
            : _departments.firstWhere((d) => d['id'] == deptId, orElse: () => {})['name'] ?? 'Group';
        
        final groupTasks = groupedTasks[deptId] ?? [];

        return ExpansionTile(
          initiallyExpanded: true,
          title: Text(
            '$deptName (${groupTasks.length} tasks)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          children: groupTasks.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('No tasks in this group.', style: TextStyle(color: Colors.grey)),
                  )
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
    final assigneeName = task['assignee']?['displayName'] ?? task['assignee']?['email'] ?? 'Unassigned';

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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                          const Icon(Icons.person, size: 14, color: Colors.blueGrey),
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
                            const Icon(Icons.calendar_today, size: 14, color: Colors.redAccent),
                            const SizedBox(width: 4),
                            Text(
                              dueDate,
                              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Chip(
              label: Text(status, style: const TextStyle(fontSize: 10)),
              backgroundColor: _getStatusColor(status),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void _showNewGroupDialog() {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New task group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              try {
                await _taskService.createDepartment(name: nameController.text.trim());
                Navigator.pop(context);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ჯგუფი წარმატებით შეიქმნა')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Create group'),
          ),
        ],
      ),
    );
  }

  void _showNewTaskBottomSheet() {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    
    String? selectedAssigneeId;
    String? selectedDepartmentId;
    String selectedPriority = 'NORMAL';
    DateTime? selectedDueDate;
    List<String> selectedParticipantIds = [];
    XFile? attachedXFile;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16, right: 16, top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New task', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Task title *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<List<dynamic>>(
                        future: _taskService.getUsers(),
                        builder: (context, snapshot) {
                          final users = snapshot.data ?? [];
                          return DropdownButtonFormField<String>(
                            value: selectedAssigneeId,
                            decoration: const InputDecoration(labelText: 'Assigned to', border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Unassigned')),
                              ...users.map((u) => DropdownMenuItem(
                                    value: u['id'].toString(),
                                    child: Text(u['displayName'] ?? u['email'] ?? 'User', overflow: TextOverflow.ellipsis),
                                  )),
                            ],
                            onChanged: (val) => setStateModal(() => selectedAssigneeId = val),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedPriority,
                        decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'LOW', child: Text('Low')),
                          DropdownMenuItem(value: 'NORMAL', child: Text('Normal')),
                          DropdownMenuItem(value: 'HIGH', child: Text('High')),
                          DropdownMenuItem(value: 'URGENT', child: Text('Urgent')),
                        ],
                        onChanged: (val) => setStateModal(() => selectedPriority = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: selectedDepartmentId,
                  decoration: const InputDecoration(labelText: 'Group', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Ungrouped')),
                    ..._departments.map((d) => DropdownMenuItem(
                          value: d['id'].toString(),
                          child: Text(d['name']),
                        )),
                  ],
                  onChanged: (val) => setStateModal(() => selectedDepartmentId = val),
                ),
                const SizedBox(height: 12),

                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(selectedDueDate == null ? 'Select Due Date' : selectedDueDate.toString().substring(0, 10)),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null) setStateModal(() => selectedDueDate = date);
                  },
                ),
                const SizedBox(height: 12),

                const Text('Participants *', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  height: 120,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                  child: FutureBuilder<List<dynamic>>(
                    future: _taskService.getUsers(),
                    builder: (context, snapshot) {
                      final users = snapshot.data ?? [];
                      if (users.isEmpty) return const Center(child: CircularProgressIndicator());
                      return ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final userId = user['id'].toString();
                          final isSelected = selectedParticipantIds.contains(userId);
                          return CheckboxListTile(
                            title: Text(user['displayName'] ?? user['email']),
                            value: isSelected,
                            onChanged: (checked) {
                              setStateModal(() {
                                if (checked == true) {
                                  selectedParticipantIds.add(userId);
                                } else {
                                  selectedParticipantIds.remove(userId);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file),
                  label: Text(attachedXFile == null ? 'Choose File' : attachedXFile!.name),
                  onPressed: () async {
                    final XFile? pickedFile = await openFile();
                    if (pickedFile != null) {
                      setStateModal(() => attachedXFile = pickedFile);
                    }
                  },
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (titleController.text.trim().isEmpty || selectedParticipantIds.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('გთხოვთ შეავსოთ სათაური და აირჩიოთ მინიმუმ ერთი მონაწილე!'), backgroundColor: Colors.red),
                          );
                          return;
                        }

                        try {
                          List<String> attachmentIds = [];
                          if (attachedXFile != null) {
                            final bytes = await attachedXFile!.readAsBytes();
                            final fileId = await _taskService.uploadFileBytes(bytes, attachedXFile!.name);
                            if (fileId != null) attachmentIds.add(fileId);
                          }

                          await _taskService.createTask(
                            title: titleController.text.trim(),
                            description: descController.text.trim(),
                            assigneeId: selectedAssigneeId,
                            departmentId: selectedDepartmentId,
                            priority: selectedPriority,
                            dueDate: selectedDueDate?.toIso8601String(),
                            participantIds: selectedParticipantIds,
                            attachmentIds: attachmentIds,
                          );

                          Navigator.pop(context);
                          _loadData();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('დავალება წარმატებით შეიქმნა!'), backgroundColor: Colors.green),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                          );
                        }
                      },
                      child: const Text('Save task'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
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