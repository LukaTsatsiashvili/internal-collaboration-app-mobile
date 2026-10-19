import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/approvals/data/approval_service.dart';

/// Read-only Request Types management sheet.
/// New Type / Edit / Activate / Deactivate are visual-only in this iteration.
class RequestTypesSheet extends StatefulWidget {
  const RequestTypesSheet({super.key, required this.service});

  final ApprovalService service;

  @override
  State<RequestTypesSheet> createState() => _RequestTypesSheetState();
}

class _RequestTypesSheetState extends State<RequestTypesSheet> {
  static const statuses = <String>['All Statuses', 'Active', 'Inactive', 'Draft'];
  final TextEditingController _search = TextEditingController();

  String _status = 'All Statuses';
  List<dynamic> _types = [];
  bool _loading = true;
  String? _error;
  int _loadVersion = 0;

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;
  bool get _dark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loadVersion++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.getManagedApprovalTypes();
      if (!mounted || version != _loadVersion) return;
      setState(() => _types = items);
    } on DioException catch (error) {
      if (!mounted || version != _loadVersion) return;
      final message = error.response?.statusCode == 403
          ? 'Request Types-ის სამართავად საჭიროა approvals.configure უფლება.'
          : 'Request Types-ის ჩატვირთვა ვერ მოხერხდა. სცადეთ ხელახლა.';
      setState(() => _error = message);
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() =>
          _error = 'Request Types-ის ჩატვირთვა ვერ მოხერხდა. სცადეთ ხელახლა.');
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  List<dynamic> get _visibleTypes {
    final query = _search.text.trim().toLowerCase();
    final status = _status == 'All Statuses' ? null : _status.toUpperCase();
    return _types.where((entry) {
      if (entry is! Map) return false;
      if (status != null && entry['status']?.toString().toUpperCase() != status) {
        return false;
      }
      return query.isEmpty ||
          (entry['name'] ?? '').toString().toLowerCase().contains(query) ||
          (entry['code'] ?? '').toString().toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Widget _staticButton(String label, {bool primary = false}) {
    final p = _p;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: primary ? 14 : 13, vertical: primary ? 10 : 8),
      decoration: BoxDecoration(
        color: primary ? null : p.card,
        gradient: primary
            ? const LinearGradient(
                colors: [AppColors.gradientStart, AppColors.gradientEnd])
            : null,
        border: primary ? null : Border.all(color: p.cardBorder),
        borderRadius: BorderRadius.circular(primary ? 13 : 14),
        boxShadow: primary
            ? [BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.19),
                blurRadius: 10,
                offset: const Offset(0, 3))]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (primary) ...[
          const Icon(Icons.add_rounded, color: Colors.white, size: 17),
          const SizedBox(width: 5),
        ],
        Text(label, style: TextStyle(
          color: primary ? Colors.white : p.secondaryText,
          fontSize: primary ? 12 : 11,
          fontWeight: FontWeight.w700,
        )),
      ]),
    );
  }

  Widget _statusDropdown() => PopupMenuButton<String>(
    tooltip: 'Request type status',
    position: PopupMenuPosition.under,
    offset: const Offset(0, 5),
    color: _p.card,
    elevation: 10,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(17),
      side: BorderSide(color: _p.cardBorder),
    ),
    constraints: BoxConstraints(
      minWidth: (MediaQuery.sizeOf(context).width - 44)
          .clamp(180.0, 430.0).toDouble(),
      maxHeight: MediaQuery.sizeOf(context).height * 0.48,
    ),
    onSelected: (value) => setState(() => _status = value),
    itemBuilder: (context) => [
      for (final status in statuses)
        PopupMenuItem<String>(
          value: status,
          height: 44,
          child: Row(children: [
            Expanded(child: Text(status, style: TextStyle(
              color: status == _status ? _p.link : _p.secondaryText,
              fontWeight: status == _status
                  ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12,
            ))),
            if (status == _status)
              Icon(Icons.check_rounded, size: 18, color: _p.link),
          ]),
        ),
    ],
    child: Container(
      height: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: _p.searchBackground,
        border: Border.all(color: _p.cardBorder),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(children: [
        Expanded(child: Text(_status, style: TextStyle(
          color: _p.secondaryText,
          fontSize: 12, fontWeight: FontWeight.w600,
        ))),
        Icon(Icons.keyboard_arrow_down_rounded, size: 19, color: _p.muted),
      ]),
    ),
  );

  Color _statusColor(String status) {
    switch (status) {
      case 'ACTIVE':
        return const Color(0xFF16BE89);
      case 'INACTIVE':
        return _p.muted;
      case 'DRAFT':
        return const Color(0xFFE7A52F);
      default:
        return _p.secondaryText;
    }
  }

  Widget _typeCard(dynamic raw) {
    final item = raw as Map;
    final name = (item['name'] ?? 'Request type').toString();
    final status = (item['status'] ?? 'DRAFT').toString().toUpperCase();
    final statusColor = _statusColor(status);
    final number = item['_count'] is Map ? item['_count']['requests'] : null;
    final count = number is num ? number.toInt() : 0;
    final by = item['createdBy'];
    final creator = by is Map ? (by['displayName'] ?? '').toString() : '';
    final code = (item['code'] ?? '').toString();
    final version = (item['version'] ?? 1).toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _p.cardBorder),
        boxShadow: [BoxShadow(
          color: _p.panelShadow,
          blurRadius: 17,
          offset: const Offset(0, 4),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 5,
          children: [
            Text(name, style: TextStyle(
              color: _p.ink, fontSize: 13, fontWeight: FontWeight.w800,
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: _dark ? 0.20 : 0.09),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: statusColor.withValues(alpha: 0.12)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(status[0] + status.substring(1).toLowerCase(),
                  style: TextStyle(color: statusColor,
                    fontSize: 10, fontWeight: FontWeight.w800)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$code · v$version · $count ${count == 1 ? 'request' : 'requests'}'
          '${creator.isEmpty ? '' : ' · Created by $creator'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _p.muted, fontSize: 10.5, fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 13),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          _staticButton('Edit'),
          const SizedBox(width: 7),
          _staticButton(status == 'ACTIVE' ? 'Deactivate' : 'Activate'),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return FractionallySizedBox(
      heightFactor: 0.9,
      alignment: Alignment.bottomCenter,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28)),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 34, height: 4,
            decoration: BoxDecoration(
              color: p.muted.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
            child: Row(children: [
              Expanded(child: Text('Request types', style: TextStyle(
                color: p.ink,
                fontSize: 18, fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ))),
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: p.searchBackground, shape: BoxShape.circle),
                child: IconButton(
                  tooltip: 'Close request types',
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: p.muted, size: 18),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: p.cardBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 15, 19, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: p.ink, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search request types...',
                    hintStyle: TextStyle(color: p.hintText, fontSize: 11.5),
                    prefixIcon: Icon(
                      Icons.search_rounded, color: p.searchIcon, size: 19),
                    suffixIcon: _search.text.isEmpty ? null : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: Icon(Icons.close_rounded, size: 17, color: p.muted),
                    ),
                    filled: true,
                    fillColor: p.searchBackground,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: p.cardBorder)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: p.cardBorder)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: p.link)),
                  ),
                ),
                const SizedBox(height: 10),
                _statusDropdown(),
                const SizedBox(height: 13),
                _staticButton('New type', primary: true),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center,
                            style: TextStyle(color: p.secondaryText,
                              fontSize: 12)),
                          const SizedBox(height: 8),
                          TextButton(onPressed: _load,
                            child: const Text('Retry')),
                        ]),
                      ))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(19, 5, 19, 20),
                          itemCount: _visibleTypes.isEmpty
                              ? 1 : _visibleTypes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 9),
                          itemBuilder: (context, index) {
                            final types = _visibleTypes;
                            if (types.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Center(child: Text(
                                  'No request types found',
                                  style: TextStyle(
                                    color: p.muted, fontSize: 12))),
                              );
                            }
                            return _typeCard(types[index]);
                          },
                        ),
                      ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ]),
      ),
    );
  }
}
