import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/drive/data/drive_service.dart';

/// Read-only folder browser until Move here is pressed. The backend validates
/// ownership, same-space destination and protects against moving into itself.
class DriveMoveDialog extends StatefulWidget {
  const DriveMoveDialog({
    super.key,
    required this.item,
    required this.service,
  });

  final Map<String, dynamic> item;
  final DriveService service;

  @override
  State<DriveMoveDialog> createState() => _DriveMoveDialogState();
}

class _DriveMoveDialogState extends State<DriveMoveDialog> {
  String? _parent;
  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _crumbs = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _version = 0;

  AppPalette get p => Theme.of(context).extension<AppPalette>()!;

  @override
  void initState() {
    super.initState();
    _browse(null);
  }

  @override
  void dispose() {
    _version++;
    super.dispose();
  }

  Future<void> _browse(String? parent) async {
    final version = ++_version;
    setState(() {
      _parent = parent;
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.getPersonalListing(parentId: parent);
      if (!mounted || version != _version) return;
      setState(() {
        _crumbs = data.breadcrumbs;
        _folders = data.items.where((item) =>
            item['kind'] == 'FOLDER' &&
            item['id'] != widget.item['id'] &&
            const {'OWNER', 'MANAGER', 'EDITOR', 'EDITOR_DELETE'}
                .contains(item['access'])).toList();
      });
    } catch (error) {
      if (!mounted || version != _version) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && version == _version) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _loading || _error != null ||
        _parent == widget.item['parentId']) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.moveItem(widget.item['id'].toString(), _parent);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: p.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 425),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(19, 18, 19, 19),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Move ${widget.item['name']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: p.muted),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 5,
                children: [
                  TextButton(
                    onPressed: _loading || _saving ? null : () => _browse(null),
                    child: const Text('Personal'),
                  ),
                  for (final crumb in _crumbs) ...[
                    Icon(Icons.chevron_right_rounded, color: p.muted, size: 17),
                    TextButton(
                      onPressed: _loading || _saving ? null :
                          () => _browse(crumb['id'].toString()),
                      child: Text(
                        (crumb['name'] ?? '').toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 310, minHeight: 82),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.cardBorder),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: TextButton(
                            onPressed: () => _browse(_parent),
                            child: const Text('Retry loading folders'),
                          ))
                        : _folders.isEmpty
                            ? Center(child: Text(
                                'No subfolders here',
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ))
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                itemCount: _folders.length,
                                separatorBuilder: (_, _) =>
                                    Divider(color: p.cardBorder, height: 1),
                                itemBuilder: (context, index) {
                                  final folder = _folders[index];
                                  return ListTile(
                                    onTap: _saving ? null :
                                        () => _browse(folder['id'].toString()),
                                    leading: Icon(Icons.folder_outlined,
                                        color: p.secondaryText),
                                    title: Text(
                                      (folder['name'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: p.ink,
                                          fontWeight: FontWeight.w700),
                                    ),
                                    trailing: Icon(
                                        Icons.chevron_right_rounded,
                                        color: p.muted),
                                  );
                                },
                              ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        AppColors.gradientStart, AppColors.gradientEnd,
                      ]),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ElevatedButton(
                      onPressed: _saving || _loading || _error != null ||
                          _parent == widget.item['parentId'] ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                      ),
                      child: _saving
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                          : const Text('Move here'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
