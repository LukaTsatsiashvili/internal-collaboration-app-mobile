
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../core/widgets/load_error_state.dart';
import '../features/people/data/people_service.dart';
import 'people_filter_dialog.dart';

typedef PeopleLinkLauncher = Future<bool> Function(Uri uri);

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, this.service, this.launchLink});
  final PeopleService? service;
  final PeopleLinkLauncher? launchLink;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen>
    with WidgetsBindingObserver {
  late final PeopleService _service;
  final _searchController = TextEditingController();
  Timer? _debounce;
  int _request = 0;
  bool _loading = true;
  String? _error;
  String _search = '';
  PeopleFilters _filters = const PeopleFilters();
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _departments = [];

  AppPalette get p => Theme.of(context).extension<AppPalette>()!;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PeopleService();
    WidgetsBinding.instance.addObserver(this);
    _loadDepartments();
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load(silent: true));
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final data = await _service.getDepartments();
      if (mounted) setState(() => _departments = data);
    } catch (_) {
      // The directory still works when department options are unavailable.
    }
  }

  Future<void> _load({bool silent = false}) async {
    final id = ++_request;
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final people = await _service.getPeople(
        query: _search, departmentId: _filters.departmentId,
        role: _filters.role, status: _filters.status,
      );
      if (!mounted || id != _request) return;
      setState(() { _people = people; _error = null; });
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() => _error = loadErrorDescription(e));
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  void _changeSearch(String value) {
    setState(() => _search = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_load(silent: true));
    });
  }

  Future<void> _filter() async {
    if (_departments.isEmpty) unawaited(_loadDepartments());
    final next = await showDialog<PeopleFilters>(
      context: context,
      builder: (_) => PeopleFilterDialog(
        initial: _filters, departments: _departments),
    );
    if (!mounted || next == null) return;
    setState(() => _filters = next);
    await _load();
  }

  Future<void> _openContact(String scheme, String value) async {
    final path = scheme == 'tel'
        ? value.replaceAll(RegExp(r'[^0-9+]'), '') : value.trim();
    if (path.isEmpty) return;
    final uri = Uri(scheme: scheme, path: path);
    try {
      final success = widget.launchLink != null
          ? await widget.launchLink!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success && mounted) _contactError();
    } catch (_) {
      if (mounted) _contactError();
    }
  }

  void _contactError() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('შესაბამისი აპლიკაცია ვერ გაიხსნა.')));

  String _departmentName(String? id) {
    for (final d in _departments) {
      if (d['id'] == id) return (d['name'] ?? '').toString();
    }
    return 'Department';
  }

  String _roleName(String? role) => switch (role) {
    'EMPLOYEE' => 'Employee',
    'MANAGER' => 'Manager',
    'AUDITOR' => 'Auditor',
    'SYSTEM_ADMIN' => 'System administrator',
    _ => 'Role',
  };

  Widget _chip(String text, VoidCallback remove, {bool blue = false}) =>
      Material(
        color: blue ? p.unreadBackground : p.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: remove,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: p.cardBorder),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 6,
                color: blue ? p.link : AppColors.success),
              const SizedBox(width: 5),
              Text(text, style: TextStyle(fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: blue ? p.link : p.secondaryText)),
              const SizedBox(width: 6),
              Icon(Icons.close_rounded, size: 12, color: p.muted),
            ]),
          ),
        ),
      );

  Widget _chips() {
    if (_filters.activeCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          if (_filters.departmentId != null) ...[
            _chip(_departmentName(_filters.departmentId), () {
              setState(() => _filters = _filters.withDepartment(null));
              unawaited(_load());
            }, blue: true),
            const SizedBox(width: 7),
          ],
          if (_filters.role != null) ...[
            _chip(_roleName(_filters.role), () {
              setState(() => _filters = _filters.withRole(null));
              unawaited(_load());
            }, blue: true),
            const SizedBox(width: 7),
          ],
          if (_filters.status != null)
            _chip(_filters.status == 'ACTIVE' ? 'Active' : 'Inactive', () {
              setState(() => _filters = _filters.withStatus(null));
              unawaited(_load());
            }),
        ]),
      ),
    );
  }

  Widget _toolbar() => Row(children: [
    Expanded(child: Container(
      height: 47,
      decoration: BoxDecoration(
        // Match the single-layer rounded search field from Messages.
        color: p.searchBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        key: const ValueKey('people-search'),
        controller: _searchController,
        onChanged: _changeSearch,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: p.ink, fontSize: 13),
        decoration: InputDecoration(
          // The shared ThemeData fills inputs by default, which creates a
          // second rectangular surface inside our rounded search container.
          filled: false,
          hintText: 'Search people...',
          hintStyle: TextStyle(color: p.hintText, fontSize: 12),
          prefixIcon: Icon(Icons.search_rounded, color: p.searchIcon, size: 19),
          suffixIcon: _search.isEmpty ? null : IconButton(
            tooltip: 'Clear search',
            icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
            onPressed: () { _searchController.clear(); _changeSearch(''); },
          ),
          border: InputBorder.none, enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          isDense: true,
        ),
      ),
    )),
    const SizedBox(width: 9),
    Material(
      color: p.card,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        key: const ValueKey('people-filter-open'),
        borderRadius: BorderRadius.circular(15),
        onTap: _filter,
        child: Container(
          width: 48, height: 47,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: p.cardBorder),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Icon(Icons.filter_list_rounded, size: 21,
              color: _filters.activeCount > 0 ? p.link : p.secondaryText),
            if (_filters.activeCount > 0)
              const Positioned(right: 10, top: 8,
                child: CircleAvatar(radius: 3,
                  backgroundColor: AppColors.primary)),
          ]),
        ),
      ),
    ),
  ]);

  Widget _contact({
    required Key key, required IconData icon, required String value,
    required VoidCallback onTap,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(width: 24, height: 24,
            decoration: BoxDecoration(
              color: p.unreadBackground,
              borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 14, color: p.link)),
          const SizedBox(width: 9),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.secondaryText, fontSize: 11.5))),
        ]),
      ),
    ),
  );

  Widget _person(Map<String, dynamic> user, int index) {
    final id = (user['id'] ?? index).toString();
    final rawName = (user['displayName'] ?? '').toString().trim();
    final name = rawName.isEmpty
        ? ((user['firstName'] ?? '').toString() + ' ' +
            (user['lastName'] ?? '').toString()).trim()
        : rawName;
    final email = (user['email'] ?? '').toString().trim();
    final phone = (user['phone'] ?? '').toString().trim();
    final department = user['department'] is Map
        ? (user['department']['name'] ?? '').toString() : '';
    final job = (user['jobTitle'] ?? '').toString().trim();
    final roles = user['roles'] is List ? user['roles'] as List : const [];
    final subtitle = job.isNotEmpty ? job
        : roles.isNotEmpty ? _roleName(roles.first.toString()) : 'Employee';
    final inactive = user['status'] == 'INACTIVE';
    final accent = [
      AppColors.primary, AppColors.gradientEnd,
      const Color(0xFF14AA9A), const Color(0xFF7560D7),
    ][index % 4];

    return Container(
      key: ValueKey('people-card-' + id),
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: p.card, borderRadius: BorderRadius.circular(21),
        border: Border.all(color: p.cardBorder),
        boxShadow: [BoxShadow(color: p.cardShadow,
          blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            height: 45, width: 45,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.person_outline_rounded,
              size: 25, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink,
                  fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(subtitle, style: TextStyle(
                    color: p.secondaryText, fontSize: 11)),
                  if (department.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.unreadBackground,
                        borderRadius: BorderRadius.circular(14)),
                      child: Text(department, style: TextStyle(
                        color: p.secondaryText, fontSize: 10,
                        fontWeight: FontWeight.w600)),
                    ),
                  if (inactive)
                    Text('Inactive', style: TextStyle(
                      color: p.muted, fontSize: 10)),
                ],
              ),
            ],
          )),
        ]),
        if (email.isNotEmpty || phone.isNotEmpty) ...[
          const SizedBox(height: 14),
          Divider(color: p.cardBorder, height: 1),
          const SizedBox(height: 11),
          if (email.isNotEmpty)
            _contact(
              key: ValueKey('people-email-' + id),
              icon: Icons.mail_outline_rounded,
              value: email, onTap: () => _openContact('mailto', email)),
          if (email.isNotEmpty && phone.isNotEmpty)
            const SizedBox(height: 8),
          if (phone.isNotEmpty)
            _contact(
              key: ValueKey('people-phone-' + id),
              icon: Icons.phone_outlined,
              value: phone, onTap: () => _openContact('tel', phone)),
        ],
      ]),
    );
  }

  Widget _list() {
    if (_loading && _people.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _people.isEmpty) {
      return AppLoadErrorViewport(description: _error, onRetry: _load);
    }
    final list = RefreshIndicator(
      onRefresh: _load,
      child: _people.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 85),
                Icon(Icons.people_outline_rounded,
                  size: 43, color: p.muted),
                const SizedBox(height: 14),
                Center(child: Text('No people match the selected filters',
                  style: TextStyle(color: p.secondaryText, fontSize: 12))),
              ],
            )
          : ListView.builder(
              keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 17),
              itemCount: _people.length,
              itemBuilder: (_, i) => _person(_people[i], i),
            ),
    );
    if (_error == null) return list;
    return Column(children: [
      AppLoadErrorNotice(onRetry: _load),
      const SizedBox(height: 8),
      Expanded(child: list),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: p.page,
    body: SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('People', key: const ValueKey('people-header'),
                  style: TextStyle(color: p.ink, fontSize: 23,
                    fontWeight: FontWeight.w800, letterSpacing: -0.75)),
              ]),
          ),
        ),
        Expanded(child: Container(
          margin: const EdgeInsets.fromLTRB(15, 0, 15, 12),
          padding: const EdgeInsets.fromLTRB(12, 13, 12, 0),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(children: [
            _toolbar(),
            _chips(),
            const SizedBox(height: 13),
            Expanded(child: _list()),
          ]),
        )),
      ]),
    ),
  );
}
