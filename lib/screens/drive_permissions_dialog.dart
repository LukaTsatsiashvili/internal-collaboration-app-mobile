import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/app_modal_elements.dart';
import '../core/theme/app_dropdown_theme.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/drive/data/drive_service.dart';

class DrivePermissionsDialog extends StatefulWidget {
  const DrivePermissionsDialog({
    super.key,
    required this.item,
    required this.service,
  });

  final Map<String, dynamic> item;
  final DriveService service;

  @override
  State<DrivePermissionsDialog> createState() => _DrivePermissionsDialogState();
}

class _DrivePermissionsDialogState extends State<DrivePermissionsDialog> {
  final _search = TextEditingController();
  List<_Recipient> _recipients = [];
  Map<String, String> _assignments = {};
  bool _includeDescendants = false;
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  AppPalette get p => Theme.of(context).extension<AppPalette>()!;
  bool get _folder => widget.item['kind'] == 'FOLDER';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      // Only the current owner can open item permissions in Personal Drive.
      final results = await Future.wait<dynamic>([
        widget.service.getPeople(),
        widget.service.getDepartments(),
        widget.service.getShares(widget.item['id'].toString()),
      ]);
      if (!mounted) return;
      final people = results[0] as List<Map<String, dynamic>>;
      final departments = results[1] as List<Map<String, dynamic>>;
      final shares = results[2] as DriveShares;
      final recipients = <_Recipient>[];
      for (final user in people) {
        if (user['status'] != 'ACTIVE' ||
            user['id'] == widget.item['ownerId']) continue;
        recipients.add(_Recipient(
          key: 'u:${user['id']}',
          label: (user['displayName'] ?? user['email'] ?? '').toString(),
          kind: 'Person',
        ));
      }
      for (final department in departments) {
        recipients.add(_Recipient(
          key: 'd:${department['id']}',
          label: (department['name'] ?? '').toString(),
          kind: 'Department',
        ));
      }
      recipients.sort((a, b) => a.label.toLowerCase()
          .compareTo(b.label.toLowerCase()));

      // Keep every existing grant, even when its recipient is not in the
      // current active directory: like the Web interface, do not silently
      // revoke a grant just because the recipient is outside search/results.
      final assignments = <String, String>{};
      for (final grant in shares.grants) {
        final userId = grant['userId'];
        final departmentId = grant['departmentId'];
        final key = userId != null ? 'u:$userId'
            : departmentId != null ? 'd:$departmentId' : null;
        if (key != null && grant['access'] != null) {
          assignments[key] = grant['access'].toString();
        }
      }
      setState(() {
        _loaded = true;
        _recipients = recipients;
        _assignments = assignments;
        _includeDescendants =
            shares.grants.any((grant) => grant['scope'] == 'DESCENDANTS');
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Recipient> get _visible {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty ? _recipients : _recipients.where((r) =>
        r.label.toLowerCase().contains(query) ||
        r.kind.toLowerCase().contains(query)).toList();
  }

  void _assign(String key, String? access) {
    setState(() {
      _error = null;
      if (access == null || access == 'NONE') {
        _assignments.remove(key);
      } else {
        _assignments[key] = access;
      }
    });
  }

  void _bulk(String? access) {
    setState(() {
      _error = null;
      for (final r in _visible) {
        if (access == null) _assignments.remove(r.key);
        else _assignments[r.key] = access;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _loading || !_loaded) return;
    setState(() => _saving = true);
    try {
      final grants = <Map<String, dynamic>>[];
      for (final entry in _assignments.entries) {
        if (entry.key.length < 3) continue;
        grants.add(<String, dynamic>{
          entry.key.startsWith('u:') ? 'userId' : 'departmentId':
              entry.key.substring(2),
          'access': entry.value,
          // Web: Personal folder grants default to ITEM_ONLY, unless
          // the user explicitly opts to share all descendants too.
          'scope': _folder && _includeDescendants
              ? 'DESCENDANTS' : 'ITEM_ONLY',
        });
      }
      await widget.service.setShares(
        widget.item['id'].toString(),
        grants: grants,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  Widget _panel({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: p.card,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: p.cardBorder),
      boxShadow: [
        BoxShadow(color: p.cardShadow, blurRadius: 12,
            offset: const Offset(0, 3)),
      ],
    ),
    child: child,
  );

  // The active bulk button follows the actual grants, not the last tap.
  // Bulk actions apply only to the currently visible search results, just as
  // in the Web permissions editor.
  bool _isBulkActive(String? access) {
    final visible = _visible;
    final expected = access ?? 'NONE';
    return visible.isNotEmpty &&
        visible.every((recipient) =>
            (_assignments[recipient.key] ?? 'NONE') == expected);
  }

  Widget _bulkButton(String label, String? access) {
    final active = _isBulkActive(access);
    return Expanded(
      child: SizedBox(
        height: 34,
        child: OutlinedButton(
          key: ValueKey('drive-bulk-${access ?? 'NONE'}'),
          onPressed: _saving || _loading ? null : () => _bulk(access),
          style: OutlinedButton.styleFrom(
            backgroundColor: active ? p.unreadBackground : p.card,
            side: BorderSide(
              color: active ? p.link : p.cardBorder,
              width: active ? 1.5 : 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: FittedBox(
            child: Text(
              label,
              style: TextStyle(
                color: active ? p.link : p.secondaryText,
                fontSize: 10,
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _personRow(_Recipient r) {
    final current = _assignments[r.key] ?? 'NONE';
    final initial = r.label.isEmpty ? '?' : r.label.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _panel(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: p.unreadBackground,
              child: Text(initial, style: TextStyle(
                color: p.link, fontWeight: FontWeight.w800, fontSize: 12,
              )),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink, fontWeight: FontWeight.w700,
                      fontSize: 11.5)),
                  const SizedBox(height: 3),
                  Text(r.kind, style: TextStyle(
                    color: p.muted, fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(width: 5),
            SizedBox(
              width: MediaQuery.sizeOf(context).width <= 380 ? 119 : 138,
              child: AppSelectDropdown<String>(
                label: 'Permission for ${r.label}',
                value: current,
                onChanged: _saving ? null : (value) => _assign(r.key, value),
                items: const [
                  DropdownMenuItem(value: 'NONE', child: Text('No Access')),
                  DropdownMenuItem(value: 'VIEWER', child: Text('Viewer')),
                  DropdownMenuItem(value: 'EDITOR', child: Text('Editor')),
                  DropdownMenuItem(
                    value: 'EDITOR_DELETE',
                    child: Text('Edit/Delete'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(25),
        side: BorderSide(color: p.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppModalHeader(
                title: 'Permissions · ${widget.item['name']}',
                onClose: _saving ? null : () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 15),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: p.unreadBackground,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.cardBorder),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                color: p.link, size: 17),
                            const SizedBox(width: 9),
                            Expanded(child: Text(
                              'Personal items stay private unless you explicitly share them. Folder sharing is item-only by default.',
                              style: TextStyle(color: p.secondaryText,
                                  fontSize: 11, height: 1.45),
                            )),
                          ],
                        ),
                      ),
                      if (_folder) ...[
                        const SizedBox(height: 12),
                        _panel(child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _includeDescendants,
                              onChanged: _saving ? null : (value) => setState(
                                  () => _includeDescendants = value ?? false),
                              activeColor: AppColors.primary,
                            ),
                            const SizedBox(width: 5),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Include current and future contents',
                                  style: TextStyle(color: p.ink,
                                    fontWeight: FontWeight.w700, fontSize: 11.5)),
                                const SizedBox(height: 5),
                                Text(
                                  'Off means recipients can open this folder, but files and nested folders remain private unless shared separately.',
                                  style: TextStyle(
                                    color: p.secondaryText, fontSize: 10.5,
                                    height: 1.4),
                                ),
                              ],
                            )),
                          ],
                        )),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: p.searchBackground,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        height: 45,
                        child: TextField(
                          controller: _search,
                          enabled: !_saving,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(color: p.ink, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Search people or departments',
                            hintStyle: TextStyle(color: p.hintText,
                              fontSize: 11),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search_rounded,
                                color: p.searchIcon, size: 19),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        _bulkButton('All Viewer', 'VIEWER'),
                        const SizedBox(width: 5),
                        _bulkButton('All Editor', 'EDITOR'),
                      ]),
                      const SizedBox(height: 5),
                      Row(children: [
                        _bulkButton('All Edit/Delete', 'EDITOR_DELETE'),
                        const SizedBox(width: 5),
                        _bulkButton('Deselect all', null),
                      ]),
                      const SizedBox(height: 13),
                      Row(children: [
                        Text('MEMBERS & DEPARTMENTS',
                          style: TextStyle(color: p.muted,
                              fontWeight: FontWeight.w700, fontSize: 10)),
                        const Spacer(),
                        Text('${_visible.length} entries',
                            style: TextStyle(color: p.muted, fontSize: 10)),
                      ]),
                      const SizedBox(height: 7),
                      if (_loading)
                        const Padding(padding: EdgeInsets.all(28),
                          child: Center(child: CircularProgressIndicator()))
                      else if (_error != null && _recipients.isEmpty)
                        TextButton(onPressed: _load,
                          child: const Text('Retry loading permissions'))
                      else if (_visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('No matching people or departments',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted)),
                        )
                      else
                        ..._visible.map(_personRow),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.error,
                )),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: p.secondaryText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 158,
                    child: AppModalPrimaryButton(
                      label: 'Save permissions',
                      busy: _saving,
                      onPressed: _saving || _loading || !_loaded
                          ? null : _save,
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

class _Recipient {
  const _Recipient({required this.key, required this.label,
    required this.kind});
  final String key;
  final String label;
  final String kind;
}
