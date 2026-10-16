import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:path_provider/path_provider.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/tasks/data/task_service.dart';

/// Task details owns its async operations and routes. The parent refreshes
/// the task list only when this sheet reports an actual modification.
class TaskDetailsSheet extends StatefulWidget {
  final String taskId;
  final TaskService service;
  final List<dynamic> groups;

  const TaskDetailsSheet({
    super.key,
    required this.taskId,
    required this.service,
    required this.groups,
  });

  @override
  State<TaskDetailsSheet> createState() => _TaskDetailsSheetState();
}

class _TaskDetailsSheetState extends State<TaskDetailsSheet> {
  static const _saveChannel = MethodChannel('gtex_collab_app/file_save');
  static const _statusValues = [
    'DRAFT', 'OPEN', 'IN_PROGRESS', 'BLOCKED', 'WAITING_REVIEW',
    'COMPLETED', 'CANCELLED',
  ];

  final _commentController = TextEditingController();
  IO.Socket? _socket;
  Map<String, dynamic>? _task;
  XFile? _commentFile;
  String? _commentFileId;
  bool _uploadingCommentFile = false;
  bool _attachingTaskFile = false;
  int _loadEpoch = 0;
  String? _error;
  String? _downloadingFile;
  bool _loading = true;
  bool _updating = false;
  bool _sendingComment = false;
  bool _activityExpanded = false;
  bool _changed = false;

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;

  @override
  void initState() {
    super.initState();
    _load();
    _connectRealtime();
  }

  Future<void> _connectRealtime() async {
    try {
      final token = await const FlutterSecureStorage().read(key: 'access_token');
      if (!mounted || token == null || token.isEmpty) return;
      final socket = IO.io('https://collaboration.gtexshop.ge', <String, dynamic>{
        'transports': ['websocket'],
        'forceNew': true,
        'autoConnect': false,
        'auth': {'token': token},
      });
      if (!mounted) {
        socket.dispose();
        return;
      }
      _socket = socket;
      void refreshIfCurrent(dynamic event) {
        if (!mounted || event is! Map) return;
        final id = event['taskId'] ?? event['id'];
        if (id?.toString() == widget.taskId && !_updating && !_sendingComment) {
          _load(showSpinner: false);
        }
      }
      socket.on('task:comment-created', refreshIfCurrent);
      socket.on('task:updated', refreshIfCurrent);
      socket.connect();
    } catch (_) {
      // Task details and manual actions remain usable without a socket.
    }
  }

  @override
  void dispose() {
    _loadEpoch++;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _commentController.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_changed);

  Future<void> _load({bool showSpinner = true}) async {
    final epoch = ++_loadEpoch;
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final task = await widget.service.getTaskDetails(widget.taskId);
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _task = task;
        _error = null;
      });
    } catch (error) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && epoch == _loadEpoch) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _changeStatus(String status) async {
    if (_updating || _task == null || _task!['status'] == status) return;
    final children = _list(_task!['subtasks']);
    if (status == 'COMPLETED' &&
        children.any((task) => task['status'] != 'COMPLETED')) {
      final accept = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Complete task?'),
          content: const Text(
            'Some subtasks are still incomplete. Complete this task anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Complete'),
            ),
          ],
        ),
      );
      if (!mounted || accept != true) return;
    }
    setState(() => _updating = true);
    try {
      await widget.service.updateTaskStatus(widget.taskId, status);
      if (!mounted) return;
      _changed = true;
      await _load(showSpinner: false);
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _changeGroup(String? groupId) async {
    if (_updating || _task == null) return;
    final current = _task!['personalLayout'];
    final currentGroup = current is Map ? current['groupId']?.toString() : null;
    if (currentGroup == groupId) return;
    setState(() => _updating = true);
    try {
      // Confirm the ID returned by the server before changing the visible
      // value; do not silently treat a selected popup item as a saved group.
      final saved = await widget.service.moveTaskToGroup(widget.taskId, groupId);
      if (!mounted) return;
      _loadEpoch++; // stale/socket fetches cannot overwrite this saved value
      final updatedTask = Map<String, dynamic>.from(_task!);
      updatedTask['personalLayout'] = saved;
      setState(() {
        _task = updatedTask;
        _changed = true;
      });
      // Refresh history and other server-backed task fields.
      await _load(showSpinner: false);
      if (mounted && _error != null) {
        _message('ჯგუფი შენახულია; დეტალების განახლება ვერ მოხერხდა.');
      }
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _pickCommentFile() async {
    if (_sendingComment || _uploadingCommentFile) return;
    try {
      final selected = await openFile();
      if (!mounted || selected == null) return;
      // Selection is not an upload. Upload now and show a confirmed state.
      setState(() {
        _commentFile = selected;
        _commentFileId = null;
        _uploadingCommentFile = true;
      });
      final bytes = await selected.readAsBytes();
      final id = await widget.service.uploadFileBytes(bytes, selected.name);
      if (!mounted) return;
      if (id == null) throw Exception('სერვერმა ატვირთვა ვერ დაადასტურა');
      setState(() => _commentFileId = id);
      _message('ფაილი აიტვირთა. კომენტარის გაგზავნისას მიემაგრება.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _commentFile = null;
        _commentFileId = null;
      });
      _message('ფაილი ვერ აიტვირთა: ' + error.toString());
    } finally {
      if (mounted) setState(() => _uploadingCommentFile = false);
    }
  }

  Future<void> _uploadFileToTask() async {
    if (_attachingTaskFile || _task == null) return;
    try {
      final selected = await openFile();
      if (!mounted || selected == null) return;
      setState(() => _attachingTaskFile = true);
      final bytes = await selected.readAsBytes();
      final fileId = await widget.service.uploadFileBytes(bytes, selected.name);
      if (fileId == null) throw Exception('სერვერმა ფაილის ატვირთვა ვერ დაადასტურა');
      final existing = _list(_task?['attachments'])
          .where((entry) => entry is Map)
          .map((entry) => entry['fileId']?.toString() ??
              (entry['file'] is Map
                  ? entry['file']['id']?.toString() : null))
          .whereType<String>()
          .toList();
      await widget.service.attachFileToTask(
        widget.taskId, existingIds: existing, newFileId: fileId,
      );
      if (!mounted) return;
      _changed = true;
      await _load(showSpinner: false);
      if (mounted) _message('ფაილი აიტვირთა და დავალებას მიემაგრა.');
    } catch (error) {
      _message('ფაილის მიმაგრება ვერ მოხერხდა: ' +
          error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _attachingTaskFile = false);
    }
  }

  Future<void> _sendComment() async {
    if (_sendingComment || _uploadingCommentFile) return;
    if (_commentController.text.trim().isEmpty) {
      _message('კომენტარის ტექსტი სავალდებულოა.');
      return;
    }
    if (_commentFile != null && _commentFileId == null) {
      _message('ფაილის ატვირთვის დასრულებას დაელოდეთ.');
      return;
    }
    setState(() => _sendingComment = true);
    try {
      await widget.service.addTaskComment(
        widget.taskId,
        content: _commentController.text.trim(),
        attachmentIds: _commentFileId == null
            ? const [] : [_commentFileId!],
      );
      if (!mounted) return;
      _commentController.clear();
      setState(() {
        _commentFile = null;
        _commentFileId = null;
      });
      _changed = true;
      await _load(showSpinner: false);
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _download(dynamic attachment) async {
    final rawFile = attachment is Map ? attachment['file'] : null;
    final file = rawFile is Map ? rawFile : attachment;
    if (file is! Map || file['id'] == null) {
      _message('ფაილი ვერ მოიძებნა');
      return;
    }
    final id = file['id'].toString();
    if (_downloadingFile != null) return;
    final rawName = (file['originalName'] ?? 'download').toString();
    final cleanName = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    File? temporary;
    setState(() => _downloadingFile = id);
    try {
      final folder = await getTemporaryDirectory();
      temporary = File(folder.path + '/task_' +
          DateTime.now().microsecondsSinceEpoch.toString() + '_' + cleanName);
      await widget.service.downloadFileToPath(id, temporary.path);
      if (!mounted) return;
      if (Platform.isAndroid) {
        final saved = await _saveChannel.invokeMethod<bool>(
          'saveDownloadedFile',
          {'path': temporary.path, 'name': cleanName},
        );
        if (saved == true) _message('ფაილი შენახულია');
      } else {
        final folder = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        final destination = File(folder.path + '/' + cleanName);
        await temporary.copy(destination.path);
        _message('ფაილი შენახულია: ' + destination.path);
      }
    } catch (error) {
      _message('ჩამოტვირთვა ვერ მოხერხდა: ' + error.toString());
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
      if (mounted) setState(() => _downloadingFile = null);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<dynamic> _list(dynamic value) =>
      value is List ? value : <dynamic>[];

  String _name(dynamic person, {String fallback = 'Unknown'}) {
    if (person is Map) {
      final value = person['displayName'] ?? person['email'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return fallback;
  }

  String _human(String status) {
    if (status.isEmpty) return '';
    return status
        .split('_')
        .map((word) => word.isEmpty
            ? ''
            : word.substring(0, 1).toUpperCase() +
                word.substring(1).toLowerCase())
        .join(' ');
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED': return const Color(0xFF13BA86);
      case 'CANCELLED': return const Color(0xFFF16A7A);
      case 'BLOCKED': return const Color(0xFFF16A7A);
      case 'WAITING_REVIEW': return const Color(0xFFF1AA37);
      case 'IN_PROGRESS': return const Color(0xFF7B68E9);
      case 'DRAFT': return _p.muted;
      default: return _p.link;
    }
  }

  String _date(dynamic value) {
    if (value == null || value.toString().isEmpty) return 'No due date';
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return value.toString();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[date.month - 1] + ' ' + date.day.toString() + ', ' +
        date.year.toString();
  }

  String _size(dynamic bytes) {
    final number = bytes is num
        ? bytes.toDouble()
        : double.tryParse(bytes?.toString() ?? '') ?? 0;
    if (number <= 0) return '';
    if (number < 1024) return number.toStringAsFixed(0) + ' B';
    if (number < 1048576) return (number / 1024).toStringAsFixed(1) + ' KB';
    return (number / 1048576).toStringAsFixed(1) + ' MB';
  }

  BoxDecoration _surface({double radius = 19}) => BoxDecoration(
    color: _p.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _p.cardBorder),
  );

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      border: Border.all(color: color.withValues(alpha: 0.14)),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 6, width: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(
          color: color, fontSize: 10.5, fontWeight: FontWeight.w700,
        )),
      ],
    ),
  );

  Widget _avatar(String value, {double size = 26}) => Container(
    height: size,
    width: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _p.unreadBackground,
      borderRadius: BorderRadius.circular(size / 3),
    ),
    child: Text(value.isEmpty ? '?' : String.fromCharCode(value.runes.first).toUpperCase(),
      style: TextStyle(color: _p.link, fontSize: size * 0.42,
          fontWeight: FontWeight.w800)),
  );

  Widget _personBox(String label, dynamic person, {String fallback = 'Unknown'}) {
    final name = _name(person, fallback: fallback);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: _p.muted, fontSize: 10)),
        const SizedBox(height: 7),
        Row(
          children: [
            _avatar(name, size: 23),
            const SizedBox(width: 7),
            Expanded(
              child: Text(name, maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _p.ink, fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Shared popup for both status and personal group; restrict menu width
  /// to the field and disable splash/hover as in the New Task sheet.
  Widget _dropdown({
    required String value,
    required List<MapEntry<String, String>> options,
    required ValueChanged<String> onChanged,
    Color? dotColor,
  }) {
    final p = _p;
    final selected = options.where((item) => item.key == value);
    final name = selected.isNotEmpty ? selected.first.value : options.first.value;
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: LayoutBuilder(
        builder: (context, bounds) => PopupMenuButton<String>(
          enabled: !_updating,
          tooltip: 'Choose ' + name,
          position: PopupMenuPosition.under,
          offset: const Offset(0, 4),
          color: p.card,
          constraints: BoxConstraints(
            minWidth: bounds.maxWidth,
            maxWidth: bounds.maxWidth,
            maxHeight: 315,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: BorderSide(color: p.cardBorder),
          ),
          onSelected: onChanged,
          itemBuilder: (context) => [
            for (final option in options)
              PopupMenuItem<String>(
                value: option.key,
                height: 48,
                child: Row(
                  children: [
                    if (dotColor != null) ...[
                      Container(
                        height: 8, width: 8,
                        decoration: BoxDecoration(
                          color: _statusColor(option.key),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 9),
                    ],
                    Expanded(
                      child: Text(option.value,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: option.key == value
                            ? p.link : p.ink, fontSize: 12)),
                    ),
                    if (option.key == value)
                      Icon(Icons.check_rounded, size: 16, color: p.link),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: _surface(radius: 14),
            child: Row(
              children: [
                if (dotColor != null) ...[
                  Container(
                    height: 8, width: 8,
                    decoration: BoxDecoration(
                      color: dotColor, shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                ] else ...[
                  Icon(Icons.folder_outlined, size: 16, color: p.link),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(name, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.secondaryText,
                        fontWeight: FontWeight.w700, fontSize: 11.5)),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 19, color: p.link),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label,
      style: TextStyle(color: _p.muted, fontSize: 10,
          fontWeight: FontWeight.w700)),
  );

  Widget _metadata(Map<String, dynamic> task) {
    final status = (task['status'] ?? 'OPEN').toString();
    final layout = task['personalLayout'];
    final groupId = layout is Map ? layout['groupId']?.toString() ?? '' : '';
    final groups = <MapEntry<String, String>>[
      const MapEntry('', 'Ungrouped'),
      ...widget.groups.map((group) =>
          MapEntry(group['id'].toString(), group['name'].toString())),
    ];
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('METADATA & TIMELINE',
                style: TextStyle(color: _p.muted, fontSize: 10.5,
                    fontWeight: FontWeight.w800, letterSpacing: 0.35),
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _p.unreadBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Task #' + (task['taskNumber'] ?? task['number'] ??
                      task['id'].toString().substring(0, 8)).toString(),
                  style: TextStyle(color: _p.link,
                      fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _personBox('Assigned to', task['assignee'],
                fallback: 'Unassigned')),
            const SizedBox(width: 14),
            Expanded(child: _personBox('Created by', task['creator'])),
          ]),
          const SizedBox(height: 17),
          _metaLabel('Due date'),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 7),
              decoration: _surface(radius: 13),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_today_outlined,
                  size: 14, color: _p.link),
                const SizedBox(width: 6),
                Text(_date(task['dueDate']), style: TextStyle(
                  color: _p.secondaryText, fontSize: 11)),
              ]),
            ),
          ),
          const SizedBox(height: 15),
          _metaLabel('Status'),
          _dropdown(
            value: status,
            dotColor: _statusColor(status),
            options: [
              for (final item in _statusValues)
                MapEntry(item, _human(item)),
            ],
            onChanged: _changeStatus,
          ),
          if (task['parentTaskId'] == null) ...[
            const SizedBox(height: 15),
            _metaLabel('My group'),
            _dropdown(
              value: groupId,
              options: groups,
              onChanged: (value) => _changeGroup(
                  value.isEmpty ? null : value),
            ),
          ],
          if (_updating) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _participants(Map<String, dynamic> task) {
    final people = _list(task['participants']);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Participants', style: TextStyle(
            color: _p.ink, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 4),
          Text('People involved in this task. Use Edit task to change participants.',
              style: TextStyle(color: _p.muted, fontSize: 10.5)),
          const SizedBox(height: 14),
          if (people.isEmpty)
            Text('No participants.', style: TextStyle(color: _p.muted,
                fontSize: 12))
          else
            Wrap(
              spacing: 6, runSpacing: 7,
              children: people.map((person) {
                final name = _name(
                  person is Map ? person['user'] : null,
                );
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 7),
                  decoration: _surface(radius: 17),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _avatar(name, size: 23),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _p.ink,
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _subtasks(Map<String, dynamic> task) {
    final children = _list(task['subtasks']);
    final completed = children.where((child) =>
        child['status'] == 'COMPLETED').length;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Subtasks', style: TextStyle(
                      color: _p.ink, fontSize: 13,
                      fontWeight: FontWeight.w800,
                    )),
                    const SizedBox(height: 4),
                    Text(children.isEmpty
                        ? 'Break this task into smaller steps.'
                        : completed.toString() + ' / ' +
                            children.length.toString() + ' completed',
                        style: TextStyle(color: _p.muted, fontSize: 10.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 9),
                decoration: _surface(radius: 13),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: _p.link, size: 16),
                  const SizedBox(width: 4),
                  Text('Add subtask', style: TextStyle(
                    color: _p.secondaryText,
                    fontSize: 10.5, fontWeight: FontWeight.w700,
                  )),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (children.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: _surface(radius: 13),
              child: Center(child: Text('No subtasks yet.',
                style: TextStyle(color: _p.muted, fontSize: 11))),
            )
          else
            ...children.map((child) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Icon(child['status'] == 'COMPLETED'
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                      color: _p.link, size: 19),
                  const SizedBox(width: 8),
                  Expanded(child: Text((child['title'] ?? '').toString(),
                    style: TextStyle(color: _p.ink, fontSize: 11.5,
                        fontWeight: FontWeight.w600))),
                  _tag(_human((child['status'] ?? 'OPEN').toString()),
                      _statusColor((child['status'] ?? 'OPEN').toString())),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _attachments(List<dynamic> items, {bool insideComment = false}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!insideComment) ...[
          Padding(
            padding: const EdgeInsets.only(left: 3, bottom: 10),
            child: Text('ATTACHMENT', style: TextStyle(
              color: _p.muted, fontSize: 11,
              fontWeight: FontWeight.w800)),
          ),
        ],
        ...items.map((attachment) {
          final item = attachment is Map ? attachment['file'] : null;
          final file = item is Map ? item : attachment;
          final id = (file is Map ? file['id'] : null)?.toString() ?? '';
          final name = (file is Map ? file['originalName'] : null)
              ?.toString() ?? 'File';
          final bytes = file is Map ? file['sizeBytes'] : null;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 11, vertical: 9),
            decoration: _surface(radius: 15),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _p.unreadBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.insert_drive_file_outlined,
                    color: _p.link, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _p.ink,
                        fontWeight: FontWeight.w700, fontSize: 11)),
                  if (_size(bytes).isNotEmpty)
                    Text(_size(bytes),
                      style: TextStyle(color: _p.muted, fontSize: 10)),
                ],
              )),
              IconButton(
                tooltip: 'Download file',
                onPressed: id.isEmpty || _downloadingFile != null
                    ? null : () => _download(attachment),
                icon: _downloadingFile == id
                    ? const SizedBox(
                        height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.download_rounded,
                        color: _p.link, size: 19),
              ),
            ]),
          );
        }),
      ],
    );
  }

  Widget _discussion(Map<String, dynamic> task) {
    final comments = _list(task['comments']);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('Discussion · ' + comments.length.toString(),
              style: TextStyle(color: _p.ink, fontSize: 13,
                  fontWeight: FontWeight.w800))),
            Text('Realtime', style: TextStyle(
              color: _p.muted, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          for (final entry in comments) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _avatar(_name(entry['author']), size: 28),
                const SizedBox(width: 9),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name(entry['author']), style: TextStyle(
                      color: _p.ink, fontSize: 11,
                      fontWeight: FontWeight.w800)),
                    Text(_date(entry['createdAt']), style: TextStyle(
                      color: _p.muted, fontSize: 10)),
                    const SizedBox(height: 5),
                    Text((entry['content'] ?? '').toString(),
                      style: TextStyle(color: _p.secondaryText,
                          fontSize: 12, height: 1.4)),
                    const SizedBox(height: 7),
                    _attachments(_list(entry['attachments']),
                        insideComment: true),
                  ],
                )),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: _p.cardBorder),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _commentController,
            minLines: 4,
            maxLines: 9,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: _p.ink, fontSize: 12.5),
            decoration: InputDecoration(
              hintText: 'Add a comment...',
              hintStyle: TextStyle(color: _p.hintText, fontSize: 12),
              filled: true,
              fillColor: _p.card,
              contentPadding: const EdgeInsets.all(13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _p.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _p.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _p.link, width: 1.2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                onPressed: (_sendingComment || _uploadingCommentFile)
                    ? null : _pickCommentFile,
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                icon: _uploadingCommentFile
                    ? const SizedBox(height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        _commentFileId != null
                            ? Icons.cloud_done_outlined
                            : Icons.attach_file_rounded,
                        color: _p.link, size: 16),
                label: Text(_uploadingCommentFile
                    ? 'Uploading...'
                    : _commentFileId != null
                        ? 'Uploaded: ' + (_commentFile?.name ?? '')
                        : 'Attach a file',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _p.secondaryText,
                      fontSize: 10.5)),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 39,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                gradient: const LinearGradient(colors: [
                  AppColors.gradientStart, AppColors.gradientEnd,
                ]),
              ),
              child: TextButton(
                onPressed: (_sendingComment || _uploadingCommentFile) ? null : _sendComment,
                child: _sendingComment
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Comment', style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  String _historyDescription(dynamic event) {
    final date = _date(event['createdAt']);
    final author = _name(event['actor']);
    if (event['actionType'] == 'PERSONAL_GROUP_CHANGED') {
      final oldValue = event['oldValue'];
      final newValue = event['newValue'];
      final oldId = oldValue is Map ? oldValue['groupId']?.toString() : null;
      final newId = newValue is Map ? newValue['groupId']?.toString() : null;
      String groupName(String? id) {
        if (id == null) return 'Ungrouped';
        for (final group in widget.groups) {
          if (group['id']?.toString() == id) {
            return (group['name'] ?? '').toString();
          }
        }
        return 'Previous group';
      }
      return date + ' · ' + author + ' · My group: ' +
          groupName(oldId) + ' → ' + groupName(newId);
    }
    return date + ' · ' + author + ' · ' +
        _human((event['actionType'] ?? '').toString());
  }

  Widget _history(Map<String, dynamic> task) {
    final events = _list(task['history']);
    return Container(
      decoration: _surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _activityExpanded = !_activityExpanded),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(children: [
                Icon(_activityExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                    size: 19, color: _p.muted),
                const SizedBox(width: 6),
                Expanded(child: Text('Activity history',
                  style: TextStyle(color: _p.secondaryText,
                      fontSize: 11.5, fontWeight: FontWeight.w800))),
              ]),
            ),
          ),
          if (_activityExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: events.isEmpty
                    ? [Text('No activity yet.',
                        style: TextStyle(color: _p.muted, fontSize: 11))]
                    : events.map((event) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Text(
                          _historyDescription(event),
                          style: TextStyle(color: _p.secondaryText,
                              fontSize: 10.5),
                        ),
                      )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _details(Map<String, dynamic> task) {
    final title = (task['title'] ?? '').toString();
    final status = (task['status'] ?? 'OPEN').toString();
    final priority = (task['priority'] ?? 'NORMAL').toString();
    final group = task['personalLayout'] is Map
        ? task['personalLayout']['group'] : null;
    final description = (task['description'] ?? '').toString();
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: TextStyle(
              color: _p.ink, fontSize: 21, letterSpacing: -0.5,
              fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 9),
              decoration: _surface(radius: 17),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_note_rounded, size: 15, color: _p.link),
                const SizedBox(width: 4),
                Text('Edit task', style: TextStyle(
                    fontSize: 10.5, color: _p.secondaryText,
                    fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
        if (task['parentTask'] is Map) ...[
          const SizedBox(height: 6),
          Text('Subtask of ' +
              (task['parentTask']['title'] ?? '').toString(),
            style: TextStyle(color: _p.muted, fontSize: 11)),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 7, runSpacing: 7, children: [
          _tag(_human(priority), priority == 'HIGH' ||
              priority == 'URGENT'
              ? const Color(0xFFF0A128) : _p.link),
          _tag(_human(status), _statusColor(status)),
          if (group is Map)
            _tag('My group · ' + (group['name'] ?? '').toString(),
                _p.secondaryText),
        ]),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: _surface(radius: 15),
          child: Text(description.isEmpty
              ? 'No description provided.' : description,
            style: TextStyle(color: _p.secondaryText,
                fontSize: 12.5, height: 1.4)),
        ),
        const SizedBox(height: 17),
        _metadata(task),
        const SizedBox(height: 16),
        _participants(task),
        if (task['parentTaskId'] == null) ...[
          const SizedBox(height: 16),
          _subtasks(task),
        ],
        const SizedBox(height: 19),
        Row(children: [
          Expanded(child: Text('ATTACHMENT', style: TextStyle(
            color: _p.muted, fontSize: 11,
            fontWeight: FontWeight.w800))),
          TextButton.icon(
            onPressed: _attachingTaskFile ? null : _uploadFileToTask,
            icon: _attachingTaskFile
                ? const SizedBox(width: 15, height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.add_rounded, color: _p.link, size: 17),
            label: Text(_attachingTaskFile ? 'Uploading...' : 'Upload file',
              style: TextStyle(color: _p.link, fontSize: 11)),
          ),
        ]),
        _attachments(_list(task['attachments']), insideComment: true),
        const SizedBox(height: 16),
        _discussion(task),
        const SizedBox(height: 13),
        _history(task),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, inset + 8),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: (media.size.height - inset - media.padding.top) * 0.95,
          ),
          child: Material(
            color: p.page,
            borderRadius: BorderRadius.circular(25),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: p.card,
                  padding: const EdgeInsets.fromLTRB(16, 13, 13, 12),
                  child: Row(children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF89B0FF),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Task details', style: TextStyle(
                      color: p.ink, fontSize: 16,
                      fontWeight: FontWeight.w800))),
                    Material(
                      color: p.searchBackground,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: _close,
                        icon: Icon(Icons.close_rounded, color: p.muted,
                            size: 18),
                      ),
                    ),
                  ]),
                ),
                Divider(height: 1, color: p.cardBorder),
                Expanded(
                  child: _loading && _task == null
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null && _task == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(_error!, textAlign: TextAlign.center,
                                      style: TextStyle(color: p.secondaryText)),
                                  ),
                                  TextButton(
                                    onPressed: _load,
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            )
                          : _task == null
                              ? const SizedBox.shrink()
                              : _details(_task!),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
