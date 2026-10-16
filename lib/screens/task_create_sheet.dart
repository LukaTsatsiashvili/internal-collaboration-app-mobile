import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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
    if (title.isEmpty || _participantIds.isEmpty) {
      setState(
        () => _error = 'შეავსე სათაური და აირჩიე მინიმუმ ერთი მონაწილე.',
      );
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'New task',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _title,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    labelText: 'Task title *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<dynamic>>(
                  future: _usersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text(
                        'თანამშრომლების ჩატვირთვის შეცდომა: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      );
                    }
                    final users = snapshot.data ?? <dynamic>[];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _assigneeId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Assigned to',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Unassigned'),
                            ),
                            ...users.map(
                              (user) => DropdownMenuItem<String>(
                                value: user['id'].toString(),
                                child: Text(
                                  (user['displayName'] ??
                                          user['email'] ??
                                          'User')
                                      .toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _assigneeId = value),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Participants *',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 132,
                          child: ListView.builder(
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final userId = user['id'].toString();
                              return CheckboxListTile(
                                dense: true,
                                title: Text(
                                  (user['displayName'] ??
                                          user['email'] ??
                                          'User')
                                      .toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                value: _participantIds.contains(userId),
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _participantIds.add(userId);
                                    } else {
                                      _participantIds.remove(userId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'LOW', child: Text('Low')),
                    DropdownMenuItem(value: 'NORMAL', child: Text('Normal')),
                    DropdownMenuItem(value: 'HIGH', child: Text('High')),
                    DropdownMenuItem(value: 'URGENT', child: Text('Urgent')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _priority = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _groupId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Group',
                    border: OutlineInputBorder(),
                  ),
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    _dueDate == null
                        ? 'Select Due Date'
                        : _dueDate!.toIso8601String().substring(0, 10),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickingFile ? null : _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_file?.name ?? 'Choose File'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _submit,
                      child: const Text('Save task'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
