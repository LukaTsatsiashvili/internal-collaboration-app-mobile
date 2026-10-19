import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../core/theme/app_dropdown_theme.dart';
import '../features/approvals/data/approval_detail_rules.dart';
import '../features/approvals/data/approval_service.dart';
import 'approval_request_create_dialog.dart';

/// Shared details UI for Approvals cards and notification deep links.
/// Returns true if the server-side approval or personal layout changed.
class ApprovalDetailsSheet extends StatefulWidget {
  const ApprovalDetailsSheet({
    super.key,
    required this.requestId,
    required this.service,
    this.onChanged,
  });
  final String requestId;
  final ApprovalService service;
  /// Allows list/group counts to refresh even if sheet is swiped away.
  final VoidCallback? onChanged;

  @override
  State<ApprovalDetailsSheet> createState() => _ApprovalDetailsSheetState();
}

class _ApprovalDetailsSheetState extends State<ApprovalDetailsSheet> {
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _user;
  List<dynamic> _groups = [];
  final TextEditingController _comment = TextEditingController();
  String _decision = 'APPROVE';
  bool _loading = true;
  bool _busy = false;
  String? _downloadingId;
  String? _error;
  bool _changed = false;
  int _loadVersion = 0;

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;
  ApprovalDetailRules? get _rules =>
      _request == null || _user == null
          ? null : ApprovalDetailRules(request: _request!, user: _user!);

  @override
  void initState() {
    super.initState();
    _load();
    // The related notification is considered read when the detail is opened,
    // just like web RequestDetail. Failure never blocks the approval UI.
    widget.service.markApprovalNotificationsRead(widget.requestId)
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _loadVersion++;
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    final version = ++_loadVersion;
    if (mounted && showSpinner) {
      setState(() { _loading = true; _error = null; });
    }
    try {
      final request = await widget.service.getApprovalRequest(widget.requestId);
      final user = await widget.service.getCurrentApprovalUser();
      List<dynamic> groups = _groups;
      try {
        groups = await widget.service.getApprovalGroups();
      } catch (_) {} // Unavailable groups never block reading a request.
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _request = request;
        _user = user;
        _groups = groups;
        _error = null;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  String _message(Object error) => error.toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Invalid argument(s): ', '');

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _mutate(Future<void> Function() work) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await work();
      _changed = true;
      widget.onChanged?.call();
      await _load(showSpinner: false);
      if (mounted) {
        _comment.clear();
      }
    } catch (error) {
      if (!mounted) return;
      // On 409 refresh the latest revision, then display the actual error.
      final message = _message(error);
      await _load(showSpinner: false);
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setGroup(String? groupId) async {
    if (_busy) return;
    await _mutate(() => widget.service
        .setApprovalRequestGroup(widget.requestId, groupId));
  }

  Future<void> _confirmDecision() async {
    final rules = _rules;
    if (rules == null || !rules.canAct || _busy) return;
    final comment = _comment.text.trim();
    if (_decision != 'APPROVE' && comment.isEmpty) {
      setState(() => _error = 'Explain your decision (required)');
      return;
    }
    await _mutate(() => widget.service.decideApproval(
      id: widget.requestId,
      revision: rules.revision,
      action: _decision,
      comment: comment,
    ));
  }

  Future<void> _sendComment() async {
    final rules = _rules;
    if (rules == null || !rules.canComment || _busy) return;
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    await _mutate(() => widget.service.commentOnApproval(
      id: widget.requestId, content: text,
    ));
  }

  Future<void> _cancelRequest() async {
    final rules = _rules;
    if (rules == null || !rules.canCancel || _busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel request?'),
        content: const Text(
          'This request will be cancelled and cannot be reviewed further.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep request')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel request')),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    await _mutate(() => widget.service.cancelApproval(
      id: widget.requestId, revision: rules.revision,
    ));
  }

  Future<void> _reviseAndSubmit() async {
    final rules = _rules;
    if (rules == null || !rules.canEditAndSubmit || _busy) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApprovalRequestCreateDialog(
        service: widget.service, existing: _request,
      ),
    );
    if (!mounted || saved != true) return;
    _changed = true;
    widget.onChanged?.call();
    await _load(showSpinner: false);
  }

  Future<void> _download(Map file) async {
    final id = file['id']?.toString();
    if (id == null || id.isEmpty || _downloadingId != null) return;
    setState(() => _downloadingId = id);
    try {
      final bytes = await widget.service.downloadApprovalAttachment(id);
      final directory = await getTemporaryDirectory();
      // Reject any path segments from a server-supplied filename.
      final original = (file['originalName'] ?? 'attachment').toString();
      final safeName = original.replaceAll(RegExp(r'[\\/\x00-\x1f]'), '_');
      final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final saved = File('${directory.path}/approval_${safeId}_$safeName');
      await saved.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(saved.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        _snack('Downloaded: $safeName');
      }
    } catch (error) {
      if (mounted) _snack('Download failed: ${_message(error)}');
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  String _date(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _statusLabel(String raw) => raw.replaceAll('_', ' ')
      .toLowerCase().split(' ').map((part) => part.isEmpty ? part
          : part[0].toUpperCase() + part.substring(1)).join(' ');

  Color _statusColor(String raw) {
    if (raw == 'APPROVED') return const Color(0xFF16BE89);
    if (raw == 'REJECTED' || raw == 'CANCELLED') {
      return Theme.of(context).colorScheme.error;
    }
    if (raw == 'PENDING') return _p.link;
    if (raw == 'CHANGES_REQUESTED') return const Color(0xFFDB9C33);
    return _p.muted;
  }

  Widget _badge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(_statusLabel(status),
        style: TextStyle(color: color, fontSize: 10,
            fontWeight: FontWeight.w800)),
    );
  }

  BoxDecoration _card({Color? color}) => BoxDecoration(
    color: color ?? _p.card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _p.cardBorder),
    boxShadow: [BoxShadow(color: _p.panelShadow,
        blurRadius: 10, offset: const Offset(0, 3))],
  );

  Widget _caption(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(value.toUpperCase(), style: TextStyle(
      color: _p.muted, fontSize: 10.5,
      letterSpacing: 0.3, fontWeight: FontWeight.w800,
    )),
  );

  Widget _groupDropdown(Map<String, dynamic> request) {
    final layout = request['personalLayout'];
    final rawGroup = layout is Map ? layout['groupId']?.toString() : null;
    final current = _groups.any((group) =>
        group is Map && group['id']?.toString() == rawGroup)
        ? rawGroup : null;
    final options = <String?, String>{
      null: 'Ungrouped',
      for (final group in _groups)
        if (group is Map && group['id'] != null)
          group['id'].toString(): (group['name'] ?? 'Group').toString(),
    };
    return AppDropdownTheme(
      child: LayoutBuilder(
      builder: (context, bounds) => PopupMenuButton<String>(
        key: const ValueKey('approval-detail-group'),
        tooltip: 'Change personal group',
        enabled: !_busy,
        position: PopupMenuPosition.under,
        offset: AppDropdownTheme.menuGap,
        color: _p.card,
        elevation: 9,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: _p.cardBorder),
        ),
        constraints: AppDropdownTheme.menuBounds(
          bounds.maxWidth, MediaQuery.sizeOf(context).height * 0.4,
        ),
        onSelected: (value) => _setGroup(value.isEmpty ? null : value),
        itemBuilder: (_) => [
          for (final option in options.entries)
            PopupMenuItem<String>(
              value: option.key ?? '',
              child: Row(children: [
                Expanded(child: Text(option.value, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _p.secondaryText, fontSize: 12))),
                if (option.key == current)
                  Icon(Icons.check_rounded, color: _p.link, size: 18),
              ]),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          height: 44,
          decoration: _card(),
          child: Row(children: [
            Expanded(child: Text(options[current] ?? 'Ungrouped',
              style: TextStyle(color: _p.secondaryText, fontSize: 12,
                fontWeight: FontWeight.w700))),
            Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: _p.muted),
          ]),
        ),
      ),
      ),
    );
  }

  Widget _decisionDropdown() => AppDropdownTheme(
    child: LayoutBuilder(
    builder: (context, bounds) => PopupMenuButton<String>(
      key: const ValueKey('approval-detail-decision'),
      enabled: !_busy,
      tooltip: 'Review decision',
      position: PopupMenuPosition.under,
      offset: AppDropdownTheme.menuGap,
      color: _p.card,
      elevation: 9,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: _p.cardBorder),
      ),
      constraints: AppDropdownTheme.menuBounds(
        bounds.maxWidth, MediaQuery.sizeOf(context).height * 0.4,
      ),
      onSelected: (value) => setState(() => _decision = value),
      itemBuilder: (_) => [
        for (final item in const [
          ('APPROVE', 'Approve'),
          ('REQUEST_CHANGES', 'Request changes'),
          ('REJECT', 'Reject'),
        ])
          PopupMenuItem<String>(value: item.$1,
            child: Text(item.$2, style: TextStyle(
              color: _p.secondaryText, fontSize: 12))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13), height: 44,
        decoration: _card(),
        child: Row(children: [
          Expanded(child: Text(
            _decision == 'APPROVE' ? 'Approve'
                : _decision == 'REJECT' ? 'Reject' : 'Request changes',
            style: TextStyle(color: _p.secondaryText,
              fontSize: 12, fontWeight: FontWeight.w700),
          )),
          Icon(Icons.keyboard_arrow_down_rounded, color: _p.muted, size: 19),
        ]),
      ),
    ),
    ),
  );

  Widget _requestData(ApprovalDetailRules rules) {
    final data = rules.request['data'];
    final values = data is Map ? data : const <String, dynamic>{};
    final schema = rules.formSchema;
    if (schema.isEmpty && values.isEmpty) return const SizedBox.shrink();
    final keys = <String>{
      ...schema.keys.map((key) => key.toString()),
      ...values.keys.map((key) => key.toString()),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(13),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final key in keys) ...[
              Builder(builder: (_) {
                final spec = schema[key];
                final label = spec is Map
                    ? (spec['label'] ?? key).toString() : key;
                final raw = values[key];
                final value = raw is bool
                    ? (raw ? 'Yes' : 'No') : raw?.toString() ?? '—';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(
                        color: _p.muted, fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      )),
                      const SizedBox(height: 4),
                      Text(value, style: TextStyle(
                        color: _p.secondaryText, fontSize: 12,
                        height: 1.4,
                      )),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }

  Widget _attachments(Map<String, dynamic> request) {
    final items = request['attachments'] is List
        ? request['attachments'] as List : const <dynamic>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final attachment in items)
        if (attachment is Map && attachment['file'] is Map)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Builder(builder: (_) {
              final file = attachment['file'] as Map;
              final id = file['id']?.toString() ?? '';
              final title = (file['originalName'] ?? 'Attachment').toString();
              return Container(
                padding: const EdgeInsets.fromLTRB(11, 5, 6, 5),
                decoration: _card(),
                child: Row(children: [
                  Container(
                    height: 34, width: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _p.unreadBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.description_outlined,
                        color: _p.link, size: 20),
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: Text(title, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _p.secondaryText,
                      fontSize: 11.5, fontWeight: FontWeight.w700))),
                  IconButton(
                    tooltip: 'Download $title',
                    onPressed: _downloadingId != null
                        ? null : () => _download(file),
                    icon: _downloadingId == id
                        ? const SizedBox(height: 17, width: 17,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.download_rounded,
                            color: _p.link, size: 20),
                  ),
                ]),
              );
            }),
          ),
    ]);
  }

  Widget _progress(ApprovalDetailRules rules) {
    final steps = rules.steps.toList();
    steps.sort((a,b) => ((a is Map ? a['stepNumber'] : 0) as num? ?? 0)
      .compareTo((b is Map ? b['stepNumber'] : 0) as num? ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _caption('Approval progress'),
      for (final step in steps)
        if (step is Map)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: _card(),
              child: Row(children: [
                Container(
                  width: 34, height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _p.unreadBackground,
                    shape: BoxShape.circle,
                  ),
                  child: step['status'] == 'APPROVED'
                      ? const Icon(Icons.check_rounded, size: 17,
                          color: Color(0xFF16BE89))
                      : Text('${step['stepNumber'] ?? ''}',
                          style: TextStyle(color: _p.muted,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((step['stepName'] ?? step['name'] ?? 'Review').toString(),
                      style: TextStyle(color: _p.ink, fontSize: 12,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text((step['approver'] is Map
                        ? (step['approver']['displayName'] ?? 'Unknown')
                        : 'Unknown').toString(),
                      style: TextStyle(color: _p.muted, fontSize: 10.5)),
                    if ((step['comment'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(step['comment'].toString(), style: TextStyle(
                        color: _p.secondaryText, fontSize: 11)),
                    ],
                  ],
                )),
                _badge((step['status'] ?? 'WAITING').toString()),
              ]),
            ),
          ),
    ]);
  }

  Widget _reviewPanel(ApprovalDetailRules rules) => Container(
    margin: const EdgeInsets.only(top: 7, bottom: 15),
    padding: const EdgeInsets.all(13),
    decoration: _card(color: _p.unreadBackground),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 7, height: 7,
          decoration: const BoxDecoration(color: AppColors.primary,
            shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text('YOUR REVIEW IS NEEDED', style: TextStyle(
          color: _p.secondaryText, fontSize: 10.5,
          fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 10),
      _decisionDropdown(),
      const SizedBox(height: 10),
      TextField(
        key: const ValueKey('approval-detail-review-comment'),
        controller: _comment,
        enabled: !_busy,
        maxLines: 3,
        maxLength: 5000,
        decoration: _inputDecoration(_decision == 'APPROVE'
            ? 'Comment (optional)' : 'Explain your decision (required)'),
      ),
      const SizedBox(height: 10),
      _primaryButton('Confirm decision', _busy ? null : _confirmDecision,
        icon: Icons.check_rounded),
    ]),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: _p.hintText, fontSize: 11.5),
    filled: true, fillColor: _p.card,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: _p.cardBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: _p.cardBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: _p.link)),
    contentPadding: const EdgeInsets.all(12),
  );

  Widget _primaryButton(String label, VoidCallback? callback,
      {IconData? icon}) => Container(
    height: 44,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.gradientStart, AppColors.gradientEnd]),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: callback,
        borderRadius: BorderRadius.circular(14),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 17),
            const SizedBox(width: 6),
          ],
          Text(label, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w800, fontSize: 12)),
        ]),
      ),
    ),
  );

  Widget _comments(ApprovalDetailRules rules) {
    final items = rules.request['comments'] is List
        ? rules.request['comments'] as List : const <dynamic>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Comments', style: TextStyle(
        color: _p.ink, fontWeight: FontWeight.w800, fontSize: 12)),
      const SizedBox(height: 7),
      for (final item in items)
        if (item is Map)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((item['author'] is Map
                    ? (item['author']['displayName'] ?? 'Unknown') : 'Unknown')
                    .toString(), style: TextStyle(color: _p.secondaryText,
                      fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text((item['content'] ?? '').toString(),
                  style: TextStyle(color: _p.secondaryText, fontSize: 12)),
              ]),
          ),
      if (rules.canComment) ...[
        TextField(
          key: const ValueKey('approval-detail-add-comment'),
          controller: _comment, enabled: !_busy,
          maxLength: 5000, maxLines: 2,
          decoration: _inputDecoration('Add a comment…'),
        ),
        const SizedBox(height: 7),
        Align(alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : _sendComment,
            child: const Text('Send'),
          )),
      ],
    ]);
  }

  Widget _rounds(ApprovalDetailRules rules) {
    final rounds = rules.request['rounds'];
    if (rounds is! List || rounds.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('Earlier review rounds (${rounds.length})',
        style: TextStyle(color: _p.muted, fontSize: 12)),
      children: [
        for (var i = 0; i < rounds.length; i++)
          if (rounds[i] is Map)
            Padding(padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Round ${i + 1}', style: TextStyle(
                    color: _p.secondaryText, fontWeight: FontWeight.w700)),
                  for (final step in (rounds[i]['steps'] is List
                      ? rounds[i]['steps'] as List : const []))
                    if (step is Map)
                      Text('${step['stepName'] ?? 'Review'}: '
                        '${step['status'] ?? ''}'
                        '${step['comment'] == null ? '' : ' — ${step['comment']}'}',
                        style: TextStyle(color: _p.muted, fontSize: 11)),
                ]),
            ),
      ],
    );
  }

  Widget _body(ApprovalDetailRules rules) {
    final item = rules.request;
    final author = item['requester'] is Map
        ? (item['requester']['displayName'] ?? 'Unknown') : 'Unknown';
    return ListView(
      key: const ValueKey('approval-detail-scroll'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Wrap(spacing: 7, runSpacing: 7, children: [
          Text('$author · ${rules.typeName} · v${rules.typeVersion} · '
            '${_date(item['createdAt'])}', style: TextStyle(
              color: _p.muted, fontSize: 10.5, height: 1.35)),
          _badge(rules.status),
        ]),
        const SizedBox(height: 20),
        _caption('My group'),
        _groupDropdown(item),
        const SizedBox(height: 16),
        _requestData(rules),
        _attachments(item),
        const SizedBox(height: 9),
        _progress(rules),
        if (rules.canEditAndSubmit) ...[
          const SizedBox(height: 10),
          _primaryButton('Edit and submit',
              _busy ? null : _reviseAndSubmit, icon: Icons.edit_outlined),
        ],
        if (rules.canAct) _reviewPanel(rules),
        const SizedBox(height: 16),
        _comments(rules),
        const SizedBox(height: 9),
        _rounds(rules),
        if (rules.canCancel) ...[
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('approval-detail-cancel'),
              onPressed: _busy ? null : _cancelRequest,
              icon: const Icon(Icons.cancel_outlined, size: 17),
              label: const Text('Cancel request'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            )),
        ],
        if (_busy) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 11.5,
          )),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final maxHeight = (size.height - keyboard - safe.top - safe.bottom - 26)
        .clamp(180.0, size.height).toDouble();
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 0, 12, keyboard + 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 480),
          child: Material(
            color: _p.panel, elevation: 6,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(25),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 9),
              Container(width: 34, height: 4,
                decoration: BoxDecoration(
                  color: _p.muted.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(3))),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 10, 8, 11),
                child: Row(children: [
                  Container(width: 7, height: 7,
                    decoration: const BoxDecoration(color: Color(0xFF89B0FF),
                      shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text((_request?['title'] ?? 'Approval details')
                      .toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _p.ink,
                      fontSize: 18, fontWeight: FontWeight.w800))),
                  // Match the circular close control used by Request Types
                  // and the other shared modal headers.
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _p.searchBackground,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: 'Close approval details',
                      padding: EdgeInsets.zero,
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, _changed),
                      icon: Icon(Icons.close_rounded,
                        color: _p.muted, size: 18),
                    ),
                  ),
                ]),
              ),
              Divider(height: 1, color: _p.cardBorder),
              Flexible(
                fit: FlexFit.loose,
                child: _loading
                    ? const SizedBox(height: 170,
                        child: Center(child: CircularProgressIndicator()))
                    : _request == null || _user == null
                        ? SizedBox(height: 170, child: Center(
                            child: Column(mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error ?? 'Could not load request',
                                  textAlign: TextAlign.center),
                                TextButton(onPressed: _load,
                                  child: const Text('Retry')),
                              ])))
                        : _body(_rules!),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
