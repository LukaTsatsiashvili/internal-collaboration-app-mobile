import 'package:flutter/material.dart';

import '../core/theme/app_dropdown_theme.dart';
import '../core/theme/app_theme_extensions.dart';
import '../core/widgets/app_modal_elements.dart';
import '../features/drive/data/drive_service.dart';

/// Space roles are separate from Personal Drive's per-file grants.
/// Matches Web /drive/spaces/:id/members: NONE, VIEWER, EDITOR, MANAGER.
/// Global defaults to Viewer. System administrators remain Manager.
class DriveMembersDialog extends StatefulWidget {
  const DriveMembersDialog({
    super.key,
    required this.space,
    required this.service,
  });

  final Map<String, dynamic> space;
  final DriveService service;

  @override
  State<DriveMembersDialog> createState() => _DriveMembersDialogState();
}

class _DriveMembersDialogState extends State<DriveMembersDialog> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _people = [];
  Map<String, String> _roles = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  AppPalette get p => Theme.of(context).extension<AppPalette>()!;
  String get _type => (widget.space['type'] ?? '').toString();
  String get _name => (widget.space['name'] ?? '').toString();

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

  bool _isAdmin(Map<String, dynamic> user) {
    final roles = user['roles'];
    return roles is List && roles.contains('SYSTEM_ADMIN');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait<dynamic>([
        widget.service.getPeople(),
        widget.service.getSpaceMembers(widget.space['id'].toString()),
      ]);
      if (!mounted) return;
      final people = (result[0] as List<Map<String, dynamic>>)
          .where((user) => user['status'] == 'ACTIVE').toList()
        ..sort((a, b) => (a['displayName'] ?? '').toString()
            .toLowerCase().compareTo(
              (b['displayName'] ?? '').toString().toLowerCase()));
      final membership = result[1] as DriveSpaceMembers;
      final roles = <String, String>{};
      for (final member in membership.members) {
        if (member['userId'] is String && member['role'] is String) {
          roles[member['userId'].toString()] = member['role'].toString();
        }
      }
      for (final user in people) {
        if (_isAdmin(user)) roles[user['id'].toString()] = 'MANAGER';
      }
      setState(() {
        _people = people;
        _roles = roles;
      });
    } catch (error) {
      if (mounted) setState(() => _error =
          error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visible {
    final term = _search.text.trim().toLowerCase();
    return _people.where((user) =>
        (user['displayName'] ?? user['email'] ?? '')
            .toString().toLowerCase().contains(term)).toList();
  }

  Future<void> _save() async {
    if (_saving || _loading || _error != null) return;
    setState(() { _saving = true; _error = null; });
    try {
      final members = _roles.entries.where((e) => e.value != 'NONE')
          .map((e) => <String, dynamic>{
                'userId': e.key,
                'role': e.value,
              }).toList();
      // Backend performs the final member validation and GROUP_MANAGER_REQUIRED.
      await widget.service.saveSpaceMembers(
        widget.space['id'].toString(), members,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _member(Map<String, dynamic> person) {
    final id = person['id'].toString();
    final name = (person['displayName'] ?? person['email'] ?? '').toString();
    final admin = _isAdmin(person);
    final role = admin ? 'MANAGER' : (_roles[id] ?? 'NONE');
    return Container(
      key: ValueKey('space-member-$id'),
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: p.unreadBackground,
            child: Text(
              name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
              style: TextStyle(color: p.link, fontWeight: FontWeight.w800,
                  fontSize: 12),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink, fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
                if (admin) ...[
                  const SizedBox(height: 4),
                  Text('System administrator · Always manager',
                      maxLines: 2,
                      style: TextStyle(color: p.muted, fontSize: 9.5)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 385 ? 125 : 140,
            child: AppSelectDropdown<String>(
              label: 'Role for $name',
              value: role,
              onChanged: admin || _saving ? null : (value) {
                if (value == null) return;
                setState(() => _roles[id] = value);
              },
              fontSize: 10.5,
              items: [
                DropdownMenuItem(
                  value: 'NONE',
                  child: Text(_type == 'GLOBAL'
                      ? 'Default viewer' : 'Not a member'),
                ),
                const DropdownMenuItem(
                    value: 'VIEWER', child: Text('Viewer')),
                const DropdownMenuItem(
                    value: 'EDITOR', child: Text('Editor')),
                const DropdownMenuItem(
                    value: 'MANAGER', child: Text('Manager')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.87,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppModalHeader(
                title: 'Members · $_name',
                onClose: _saving ? null : () => Navigator.pop(context),
              ),
              const SizedBox(height: 15),
              Text(
                _type == 'GLOBAL'
                    ? 'Everyone can view Global. Add Editor or Manager roles for people who should maintain it.'
                    : 'Group members receive the workspace role shown here. System administrators always have Manager access and cannot be downgraded.',
                style: TextStyle(
                  color: p.secondaryText, fontSize: 11, height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 45,
                decoration: BoxDecoration(color: p.searchBackground,
                    borderRadius: BorderRadius.circular(13)),
                child: TextField(
                  controller: _search,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: p.ink, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search people',
                    hintStyle: TextStyle(color: p.hintText, fontSize: 11),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: p.searchIcon, size: 19),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null && _people.isEmpty
                        ? Center(child: TextButton(
                            onPressed: _load, child: const Text('Retry'),
                          ))
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              if (_visible.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Text('No matching people',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: p.muted)),
                                ),
                              for (final person in _visible) _member(person),
                            ],
                          ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 7),
                Text(_error!, style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(
                        color: p.secondaryText, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 132,
                    child: AppModalPrimaryButton(
                      label: 'Save members',
                      busy: _saving,
                      onPressed: _loading || _saving || _people.isEmpty
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
