import 'package:flutter/material.dart';

/// Dialog owns its controller and returns only a group name.
/// No API call or ScaffoldMessenger lookup happens inside this route.
class TaskGroupDialog extends StatefulWidget {
  const TaskGroupDialog({super.key});

  @override
  State<TaskGroupDialog> createState() => _TaskGroupDialogState();
}

class _TaskGroupDialogState extends State<TaskGroupDialog> {
  final TextEditingController _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 120) {
      setState(() => _error = 'მიუთითე ჯგუფის სახელი (მაქს. 120 სიმბოლო)');
      return;
    }
    // Pop is synchronous, using the *still mounted* dialog context.
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New task group'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 120,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: 'Group name',
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create group')),
      ],
    );
  }
}
