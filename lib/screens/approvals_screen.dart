import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/approvals/data/approval_service.dart';
import 'approval_advanced_filters.dart';
import 'approval_filter_dialog.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, this.focusRequestId, this.service});

  /// Allows UI tests to supply read-only approval data.
  final ApprovalService? service;

  /// Optional request ID supplied by the notification deep link.
  final String? focusRequestId;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  late final ApprovalService _approvalService;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String _view = 'All';
  String _sort = 'Default';
  ApprovalAdvancedFilters _advancedFilters = ApprovalAdvancedFilters();
  List<dynamic> _approvalTypes = [];
  String? _currentUserId;
  List<dynamic> _groups = [];
  List<String> _groupOrder = [];
  int _loadVersion = 0;
  
  bool _isLoading = true;
  List<dynamic> _requests = [];
  String? _errorMessage;
  bool _focusedOpened = false;

  @override
  void initState() {
    super.initState();
    _approvalService = widget.service ?? ApprovalService();
    _fetchApprovals();
  }

  Future<void> _fetchApprovals() async {
    final version = ++_loadVersion;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _approvalService.getApprovalRequests();
      // Groups and current user are read-only aids for the page layout.
      // An unavailable optional endpoint must not hide approvals themselves.
      List<dynamic> groups = _groups;
      List<dynamic> types = _approvalTypes;
      String? userId = _currentUserId;
      try {
        groups = await _approvalService.getApprovalGroups();
      } catch (_) {}
      try {
        types = await _approvalService.getApprovalTypes();
      } catch (_) {}
      if (userId == null) {
        try {
          userId = await _approvalService.getCurrentUserId();
        } catch (_) {}
      }
      if (!mounted || version != _loadVersion) return;
      final ids = groups.whereType<Map>()
          .map((group) => group['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty).toList();
      setState(() {
        _requests = requests;
        _groups = groups;
        _approvalTypes = types;
        _currentUserId = userId;
        // Preserve temporary on-screen drag order when refreshing.
        _groupOrder = [
          ..._groupOrder.where(ids.contains),
          ...ids.where((id) => !_groupOrder.contains(id)),
        ];
      });
      if (widget.focusRequestId != null && !_focusedOpened) {
        for (final request in requests) {
          if (request is Map &&
              request['id']?.toString() == widget.focusRequestId) {
            _focusedOpened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showFocusedRequest(request);
            });
            break;
          }
        }
      }
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _loadVersion++;
    _searchController.dispose();
    super.dispose();
  }

  void _showFocusedRequest(dynamic request) {
    final steps = request['steps'] is List ? request['steps'] as List : <dynamic>[];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text((request['title'] ?? 'მოთხოვნა').toString()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('სტატუსი: ${request['status'] ?? '-'}'),
              const SizedBox(height: 12),
              for (final step in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${step is Map ? (step['name'] ?? 'Step') : 'Step'}: '
                    '${step is Map ? (step['status'] ?? '-') : '-'}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('დახურვა'),
          ),
        ],
      ),
    );
  }

  void _handleActionDialog(String requestId, String title) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('განხილვა: $title'),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(
            labelText: 'კომენტარი (არასავალდებულო)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('გაუქმება'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _submitAction(requestId, 'REJECT', commentController.text);
            },
            child: const Text('უარყოფა'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _submitAction(requestId, 'APPROVE', commentController.text);
            },
            child: const Text('დამტკიცება'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAction(String requestId, String action, String comment) async {
    try {
      await _approvalService.performAction(
        requestId: requestId,
        action: action,
        comment: comment.isEmpty ? null : comment,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ოპერაცია წარმატებით შესრულდა')),
        );
        _fetchApprovals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }


  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;
  bool get _dark => Theme.of(context).brightness == Brightness.dark;

  BoxDecoration _panel({double radius = 20}) => BoxDecoration(
    color: _p.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _p.cardBorder),
    boxShadow: [
      BoxShadow(
        color: _p.panelShadow,
        blurRadius: 18,
        offset: const Offset(0, 5),
      ),
    ],
  );

  void _unavailable(String action) {
    // The new header controls are visual placeholders this UI-only phase.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$action — ფუნქციონალი დაემატება შემდეგ ეტაპზე'),
    ));
  }

  Widget _actionButton(String title, IconData icon, {bool primary = false}) {
    final p = _p;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _unavailable(title),
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: primary ? null : p.card,
            gradient: primary
                ? const LinearGradient(colors: [
                    AppColors.gradientStart, AppColors.gradientEnd,
                  ])
                : null,
            border: primary ? null : Border.all(color: p.cardBorder),
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: primary
                    ? AppColors.primary.withValues(alpha: 0.20)
                    : p.cardShadow,
                blurRadius: 9,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: primary ? Colors.white : p.secondaryText),
            const SizedBox(width: 5),
            Text(title, style: TextStyle(
              color: primary ? Colors.white : p.secondaryText,
              fontSize: 10.5, fontWeight: FontWeight.w700,
            )),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(17, 14, 15, 9),
    child: Row(children: [
      Expanded(child: Text('Approvals', style: TextStyle(
        color: _p.ink, fontSize: 23,
        fontWeight: FontWeight.w800, letterSpacing: -0.5,
      ))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: _p.unreadBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _p.link.withValues(alpha: 0.10)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(
            color: AppColors.primary, shape: BoxShape.circle,
          )),
          const SizedBox(width: 6),
          Text('${_requests.length} Total', style: TextStyle(
            color: _p.link, fontSize: 10.5, fontWeight: FontWeight.w700,
          )),
        ]),
      ),
    ]),
  );

  Widget _actions() => SizedBox(
    height: 54,
    child: ListView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
      children: [
        _actionButton('New request', Icons.add_rounded, primary: true),
        const SizedBox(width: 7),
        _actionButton('Request types', Icons.tune_rounded),
        const SizedBox(width: 7),
        _actionButton('New group', Icons.create_new_folder_outlined),
        const SizedBox(width: 7),
        _actionButton('Approval bases', Icons.table_chart_outlined),
      ],
    ),
  );

  static const _quickViews = [
    'All', 'Needs my review', 'My requests', "I'm involved",
  ];
  static const _sortLabels = [
    'Default', 'Created · newest', 'Created · oldest',
    'Title · A to Z', 'Title · Z to A', 'Requester · A to Z',
    'Requester · Z to A', 'Request type · A to Z',
    'Request type · Z to A', 'Status',
  ];
  static const _statusOrder = [
    'DRAFT', 'SUBMITTED', 'PENDING', 'CHANGES_REQUESTED',
    'APPROVED', 'REJECTED', 'CANCELLED',
  ];

  Widget _tabs() => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      itemCount: _quickViews.length,
      separatorBuilder: (_, __) => const SizedBox(width: 3),
      itemBuilder: (context, index) {
        final title = _quickViews[index];
        final active = title == _view;
        return InkWell(
          onTap: () => setState(() => _view = title),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: active ? _p.unreadBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(title, style: TextStyle(
              color: active ? _p.link : _p.muted,
              fontSize: 11, fontWeight: FontWeight.w700,
            )),
          ),
        );
      },
    ),
  );

  List<dynamic> _filterTypes() {
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in _approvalTypes) {
      if (raw is! Map || raw['id'] == null) continue;
      final id = raw['id'].toString();
      byId[id] = {'id': id, 'name': (raw['name'] ?? '').toString(),
        'code': (raw['code'] ?? '').toString()};
    }
    // Include inactive or historical types still referenced by a request.
    for (final raw in _requests) {
      if (raw is! Map) continue;
      final id = raw['approvalTypeId']?.toString();
      if (id == null || id.isEmpty || byId.containsKey(id)) continue;
      byId[id] = {'id': id, 'name': _typeName(raw)};
    }
    final values = byId.values.toList();
    values.sort((a, b) => a['name'].toString().toLowerCase()
        .compareTo(b['name'].toString().toLowerCase()));
    return values;
  }

  List<dynamic> _filterRequesters() {
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in _requests) {
      if (raw is! Map) continue;
      final id = raw['requesterId']?.toString();
      if (id == null || id.isEmpty) continue;
      final requester = raw['requester'];
      if (requester is! Map) continue;
      byId[id] = {'id': id,
        'displayName': (requester['displayName'] ??
            requester['email'] ?? '').toString(),
        'email': (requester['email'] ?? '').toString()};
    }
    final values = byId.values.toList();
    values.sort((a, b) => a['displayName'].toString().toLowerCase()
        .compareTo(b['displayName'].toString().toLowerCase()));
    return values;
  }

  Future<void> _openAdvancedFilters() async {
    final selection = await showDialog<ApprovalAdvancedFilters>(
      context: context,
      builder: (_) => ApprovalFilterDialog(
        initial: _advancedFilters,
        requestTypes: _filterTypes(),
        requesters: _filterRequesters(),
        groups: _groups,
      ),
    );
    if (!mounted || selection == null) return;
    setState(() => _advancedFilters = selection);
  }

  Widget _advancedFilterButton() {
    final active = _advancedFilters.activeCount;
    return IconButton(
      tooltip: 'Filter approvals',
      onPressed: _openAdvancedFilters,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
      icon: Stack(clipBehavior: Clip.none, children: [
        Icon(Icons.filter_list_rounded, size: 19,
            color: active == 0 ? _p.secondaryText : _p.link),
        if (active > 0)
          const Positioned(right: -5, top: -5, child: CircleAvatar(
            radius: 4, backgroundColor: AppColors.primary,
          )),
      ]),
    );
  }

  String get _sortShort {
    switch (_sort) {
      case 'Created · newest': return 'New ↓';
      case 'Created · oldest': return 'Old ↑';
      case 'Title · A to Z': return 'Title A-Z';
      case 'Title · Z to A': return 'Title Z-A';
      case 'Requester · A to Z': return 'Person A-Z';
      case 'Requester · Z to A': return 'Person Z-A';
      case 'Request type · A to Z': return 'Type A-Z';
      case 'Request type · Z to A': return 'Type Z-A';
      case 'Status': return 'Status';
      default: return 'Default';
    }
  }

  Widget _sortMenu() => PopupMenuButton<String>(
    tooltip: 'Sort approvals',
    position: PopupMenuPosition.under,
    onSelected: (value) => setState(() => _sort = value),
    color: _p.card,
    constraints: BoxConstraints(
      minWidth: 225,
      maxWidth: (MediaQuery.sizeOf(context).width - 28)
          .clamp(225.0, 330.0).toDouble(),
      maxHeight: MediaQuery.sizeOf(context).height * 0.65,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(color: _p.cardBorder),
    ),
    itemBuilder: (context) => _sortLabels.map((value) =>
      PopupMenuItem<String>(
        value: value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: value == _sort ? _p.unreadBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Expanded(child: Text(value, style: TextStyle(
              color: value == _sort ? _p.link : _p.secondaryText,
              fontSize: 12, fontWeight: FontWeight.w700,
            ))),
            if (value == _sort)
              Icon(Icons.check_rounded, color: _p.link, size: 18),
          ]),
        ),
      ),
    ).toList(),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.swap_vert_rounded, size: 17,
        color: _sort == 'Default' ? _p.muted : _p.link),
      const SizedBox(width: 4),
      Text(_sortShort, style: TextStyle(
        color: _sort == 'Default' ? _p.secondaryText : _p.link,
        fontSize: 11, fontWeight: FontWeight.w700,
      )),
    ]),
  );

  Widget _toolbar() => Container(
    margin: const EdgeInsets.fromLTRB(14, 6, 14, 12),
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
    decoration: _panel(),
    child: Column(children: [
      _tabs(),
      const SizedBox(height: 5),
      Divider(color: _p.cardBorder, height: 1),
      Row(children: [
        Expanded(child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _search = value),
          textInputAction: TextInputAction.search,
          style: TextStyle(color: _p.ink, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Search approvals',
            hintStyle: TextStyle(color: _p.hintText, fontSize: 11),
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 9,
            ),
            suffixIconConstraints: const BoxConstraints(
              minHeight: 32, minWidth: 32,
            ),
            suffixIcon: _search.isEmpty ? null : IconButton(
              tooltip: 'Clear search',
              padding: EdgeInsets.zero,
              onPressed: () {
                _searchController.clear();
                setState(() => _search = '');
              },
              icon: Icon(Icons.close_rounded, size: 17, color: _p.muted),
            ),
          ),
        )),
        _advancedFilterButton(),
        const SizedBox(width: 9),
        _sortMenu(),
        const SizedBox(width: 11),
      ]),
    ]),
  );

  String _typeName(dynamic req) {
    final snapshot = req['workflowSnapshot'];
    final type = snapshot is Map ? snapshot['type'] : null;
    final fromSnapshot = type is Map ? type['name'] : null;
    final typeEntity = req['approvalType'];
    final fromType = typeEntity is Map ? typeEntity['name'] : null;
    return (fromSnapshot ?? fromType ?? 'Request').toString();
  }

  String _requester(dynamic req) {
    final person = req['requester'];
    if (person is Map) {
      return (person['displayName'] ?? person['email'] ?? 'Unknown').toString();
    }
    return 'Unknown';
  }

  bool _visible(dynamic request) {
    if (request is! Map) return false;
    final user = _currentUserId;
    final steps = request['steps'];
    final stepList = steps is List ? steps : const <dynamic>[];
    final currentReview = user != null && stepList.any((step) =>
        step is Map && step['approverId']?.toString() == user &&
        step['status'] == 'PENDING');
    final involved = user != null &&
        (request['requesterId']?.toString() == user ||
        stepList.any((step) => step is Map &&
            step['approverId']?.toString() == user));
    switch (_view) {
      case 'Needs my review':
        if (!currentReview) return false;
        break;
      case 'My requests':
        if (user == null || request['requesterId']?.toString() != user) {
          return false;
        }
        break;
      case "I'm involved":
        if (!involved) return false;
        break;
    }
    if (!_advancedFilters.matches(request)) return false;
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return true;
    final searchText = [
      request['title']?.toString() ?? '',
      _typeName(request),
      _requester(request),
    ].join(' ').toLowerCase();
    return searchText.contains(query);
  }

  int _dateCompare(dynamic a, dynamic b) {
    final first = DateTime.tryParse(a?.toString() ?? '');
    final second = DateTime.tryParse(b?.toString() ?? '');
    if (first == null) return second == null ? 0 : 1;
    if (second == null) return -1;
    return first.compareTo(second);
  }

  int _position(dynamic req) {
    final layout = req['personalLayout'];
    final value = layout is Map ? layout['position'] : null;
    return value is num ? value.toInt() : 2147483647;
  }

  List<dynamic> _sorted(List<dynamic> items) {
    final sorted = List<dynamic>.of(items);
    sorted.sort((a, b) {
      int c = 0;
      switch (_sort) {
        case 'Created · newest':
          c = _dateCompare(b['createdAt'], a['createdAt']);
          break;
        case 'Created · oldest':
          c = _dateCompare(a['createdAt'], b['createdAt']);
          break;
        case 'Title · A to Z':
          c = (a['title'] ?? '').toString().toLowerCase()
              .compareTo((b['title'] ?? '').toString().toLowerCase());
          break;
        case 'Title · Z to A':
          c = (b['title'] ?? '').toString().toLowerCase()
              .compareTo((a['title'] ?? '').toString().toLowerCase());
          break;
        case 'Requester · A to Z':
          c = _requester(a).toLowerCase()
              .compareTo(_requester(b).toLowerCase());
          break;
        case 'Requester · Z to A':
          c = _requester(b).toLowerCase()
              .compareTo(_requester(a).toLowerCase());
          break;
        case 'Request type · A to Z':
          c = _typeName(a).toLowerCase()
              .compareTo(_typeName(b).toLowerCase());
          break;
        case 'Request type · Z to A':
          c = _typeName(b).toLowerCase()
              .compareTo(_typeName(a).toLowerCase());
          break;
        case 'Status':
          c = _statusOrder.indexOf((a['status'] ?? '').toString())
              .compareTo(_statusOrder.indexOf((b['status'] ?? '').toString()));
          break;
        default:
          c = _position(a).compareTo(_position(b));
      }
      if (c != 0) return c;
      c = _position(a).compareTo(_position(b));
      if (c != 0) return c;
      return _dateCompare(b['createdAt'], a['createdAt']);
    });
    return sorted;
  }

  List<Map<String, dynamic>> _sections() {
    final visible = _requests.where(_visible).toList();
    final byId = <String, Map>{};
    for (final group in _groups) {
      if (group is Map && group['id'] != null) {
        byId[group['id'].toString()] = group;
      }
    }
    final sections = <Map<String, dynamic>>[];
    for (final id in _groupOrder) {
      if (_advancedFilters.groupIds.isNotEmpty &&
          !_advancedFilters.groupIds.contains(id)) continue;
      final group = byId[id];
      if (group == null) continue;
      sections.add({
        'id': id,
        'name': (group['name'] ?? 'Group').toString(),
        'requests': _sorted(visible.where((req) =>
            req['personalLayout'] is Map &&
            req['personalLayout']['groupId']?.toString() == id).toList()),
      });
    }
    final ownedIds = byId.keys.toSet();
    if (_advancedFilters.groupIds.isEmpty ||
        _advancedFilters.groupIds.contains(ApprovalAdvancedFilters.ungrouped)) {
      sections.add({
        'id': 'ungrouped',
        'name': 'Ungrouped',
        'requests': _sorted(visible.where((req) {
          final layout = req['personalLayout'];
          final id = layout is Map ? layout['groupId']?.toString() : null;
          return id == null || !ownedIds.contains(id);
        }).toList()),
      });
    }
    return sections;
  }

  void _reorderGroups(int oldIndex, int newIndex) {
    final count = _groupOrder.length;
    if (oldIndex < 0 || oldIndex >= count) return; // Ungrouped stays last.
    if (newIndex > oldIndex) newIndex--;
    newIndex = newIndex.clamp(0, count - 1).toInt();
    if (oldIndex == newIndex) return;
    setState(() {
      final id = _groupOrder.removeAt(oldIndex);
      _groupOrder.insert(newIndex, id);
    });
    // UI only: nothing is persisted to the backend until functionality phase.
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'SUBMITTED': return 'Submitted';
      case 'APPROVED': return 'Approved';
      case 'PENDING': return 'Pending';
      case 'REJECTED': return 'Rejected';
      case 'CHANGES_REQUESTED': return 'Changes requested';
      case 'CANCELLED': return 'Cancelled';
      case 'DRAFT': return 'Draft';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED': return const Color(0xFF16BE89);
      case 'PENDING': return _p.link;
      case 'REJECTED': return Theme.of(context).colorScheme.error;
      case 'CHANGES_REQUESTED': return const Color(0xFFE2A129);
      default: return _p.secondaryText;
    }
  }

  Widget _statusTag(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _dark ? 0.19 : 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(_statusLabel(status), style: TextStyle(
        color: color, fontSize: 10, fontWeight: FontWeight.w800,
      )),
    );
  }

  String _dateLabel(dynamic input) {
    final date = DateTime.tryParse(input?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _stepsProgress(dynamic request) {
    final raw = request['steps'];
    if (raw is! List || raw.isEmpty) {
      return Text('No active reviewer', style: TextStyle(
        color: _p.muted, fontSize: 10.5, fontWeight: FontWeight.w600,
      ));
    }
    final steps = List<dynamic>.of(raw);
    steps.sort((a, b) => ((a is Map ? a['stepNumber'] : 0) as num? ?? 0)
        .compareTo(((b is Map ? b['stepNumber'] : 0) as num? ?? 0)));
    final approved = steps.where((step) =>
        step is Map && step['status'] == 'APPROVED').length;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ...steps.map((step) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Container(
          height: 7, width: 7,
          decoration: BoxDecoration(
            color: step is Map && step['status'] == 'APPROVED'
                ? const Color(0xFF16BE89) : _p.muted.withValues(alpha: 0.32),
            shape: BoxShape.circle,
          ),
        ),
      )),
      const SizedBox(width: 3),
      Text('$approved/${steps.length}', style: TextStyle(
        color: _p.muted, fontSize: 10, fontWeight: FontWeight.w700,
      )),
    ]);
  }

  Widget _requestCard(dynamic request) {
    final status = (request['status'] ?? 'DRAFT').toString();
    final title = (request['title'] ?? 'Request').toString();
    final id = (request['id'] ?? '').toString();
    final type = _typeName(request);
    final requester = _requester(request);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showFocusedRequest(request),
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
            decoration: _panel(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 34, width: 34,
                  decoration: BoxDecoration(
                    color: _p.unreadBackground,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.description_outlined,
                    size: 19, color: _p.link),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _p.ink,
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(type, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _p.muted, fontSize: 10.5)),
                    const SizedBox(height: 7),
                    _stepsProgress(request),
                  ],
                )),
                const SizedBox(width: 7),
                _statusTag(status),
              ]),
              const SizedBox(height: 13),
              Divider(color: _p.cardBorder, height: 1),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text(requester,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _p.secondaryText,
                    fontSize: 10.5, fontWeight: FontWeight.w700))),
                const SizedBox(width: 7),
                Text(_dateLabel(request['createdAt']), style: TextStyle(
                  color: _p.muted, fontSize: 10,
                  fontWeight: FontWeight.w600,
                )),
                // Preserve the pre-existing approval/rejection action without
                // changing its API or confirmation dialog logic.
                PopupMenuButton<String>(
                  tooltip: 'Approval actions',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: Icon(Icons.more_vert_rounded,
                    color: _p.muted, size: 18),
                  color: _p.card,
                  onSelected: (value) {
                    if (value == 'review') _handleActionDialog(id, title);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'review',
                      child: Text('Review request'),
                    ),
                  ],
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _groupSection(Map<String, dynamic> section, int index) {
    final id = section['id'] as String;
    final name = section['name'] as String;
    final requests = section['requests'] as List<dynamic>;
    final grouped = id != 'ungrouped';
    return Theme(
      key: ValueKey('approval-section-$id'),
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('approval-group-$id-${requests.isEmpty ? 'empty' : 'populated'}'),
        initiallyExpanded: requests.isNotEmpty,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: _p.muted,
        collapsedIconColor: _p.muted,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(children: [
          Flexible(child: Text(name, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _p.ink,
              fontSize: 12, fontWeight: FontWeight.w800))),
          const SizedBox(width: 6),
          Text('${requests.length} ${requests.length == 1 ? 'request' : 'requests'}',
            style: TextStyle(color: _p.muted, fontSize: 10)),
        ]),
        trailing: grouped
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Tooltip(
                  message: 'Drag to reorder on this screen',
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 9,
                      ),
                      child: Icon(Icons.drag_indicator_rounded,
                        color: _p.muted, size: 17),
                    ),
                  ),
                ),
                Icon(Icons.edit_outlined, color: _p.muted, size: 16),
                const SizedBox(width: 8),
                Icon(Icons.delete_outline_rounded,
                  color: _p.muted, size: 17),
                const SizedBox(width: 3),
              ])
            : null,
        children: requests.isEmpty
            ? [Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.fromLTRB(2, 0, 2, 11),
                padding: const EdgeInsets.symmetric(vertical: 17),
                decoration: _panel(radius: 17),
                child: Text('No approvals in this group.',
                  style: TextStyle(color: _p.muted, fontSize: 11)),
              )]
            : requests.map(_requestCard).toList(),
      ),
    );
  }

  Widget _groupList() {
    final sections = _sections();
    return ReorderableListView(
      buildDefaultDragHandles: false,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      onReorder: _reorderGroups,
      children: [
        for (var i = 0; i < sections.length; i++)
          _groupSection(sections[i], i),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _p.page,
    body: SafeArea(
      child: Column(children: [
        _header(),
        _actions(),
        _toolbar(),
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(_errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ))
              : RefreshIndicator(
                  onRefresh: _fetchApprovals,
                  child: _groupList(),
                ),
        ),
      ]),
    ),
  );
}
