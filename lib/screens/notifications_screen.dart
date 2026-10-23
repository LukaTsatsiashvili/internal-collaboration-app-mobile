import 'package:flutter/material.dart';

import '../features/notifications/data/notification_service.dart';
import '../features/tasks/data/task_service.dart';
import '../features/chat/data/chat_service.dart';
import 'task_details_sheet.dart';
import 'chats_screen.dart';
import 'approvals_screen.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../core/widgets/load_error_state.dart';


class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.service,
    this.openNotificationId,
    this.onDestinationChanged,
  });

  /// Optional injection for isolated widget tests.
  final NotificationService? service;
  /// Open a Latest Updates item using Inbox's existing read/deep-link flow.
  final String? openNotificationId;
  /// The shell highlights the linked module while its details are visible.
  /// Null restores the original tab when the details are dismissed.
  final ValueChanged<int?>? onDestinationChanged;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  late final NotificationService _service;
  List<Map<String, dynamic>> _items = [];
  int _unreadCount = 0;
  int _requestVersion = 0;
  bool _loading = true;
  bool _markingAll = false;
  String? _busyId;
  String? _error;
  String _filter = 'all';
  bool _initialNotificationOpened = false;

  List<Map<String, dynamic>> get _visibleItems {
    if (_filter == 'unread') {
      return _items.where((item) => item['isRead'] != true).toList();
    }
    if (_filter == 'mentions') {
      return _items.where((item) => item['type'] == 'MENTION').toList();
    }
    return _items;
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NotificationService();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _service.connect(() {
        if (mounted) _load(silent: true);
      });
    } catch (_) {
      // The REST inbox still works when the socket is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  @override
  void dispose() {
    _requestVersion++;
    WidgetsBinding.instance.removeObserver(this);
    _service.disposeSocket();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final version = ++_requestVersion;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final inbox = await _service.getInbox();
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _items = inbox.items;
        _unreadCount = inbox.unreadCount;
        _error = null;
      });
      if (!_initialNotificationOpened && widget.openNotificationId != null) {
        for (final item in inbox.items) {
          if (item['id']?.toString() == widget.openNotificationId) {
            _initialNotificationOpened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _open(item);
            });
            break;
          }
        }
      }
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = loadErrorDescription(error);
      });
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _readAll() async {
    if (_markingAll || _unreadCount == 0) return;
    setState(() => _markingAll = true);
    try {
      await _service.markAllRead();
      await _load(silent: true);
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  /// Long-press toggles read/unread without changing the card layout.
  Future<void> _toggleRead(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty || _busyId != null) return;
    setState(() => _busyId = id);
    try {
      if (item['isRead'] == true) {
        await _service.markUnread(id);
      } else {
        await _service.markRead(id);
      }
      await _load(silent: true);
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty || _busyId != null) return;
    setState(() => _busyId = id);
    bool highlighted = false;
    void highlight(int tab) {
      widget.onDestinationChanged?.call(tab);
      highlighted = true;
    }
    try {
      if (item['isRead'] != true) await _service.markRead(id);
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      final url = item['targetUrl']?.toString();
      if (url == null || url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      if (uri.path == '/tasks') {
        final taskId = uri.queryParameters['task'];
        if (taskId == null || taskId.isEmpty) return;
        final service = TaskService();
        List<dynamic> groups = [];
        try {
          groups = await service.getTaskGroups();
        } catch (_) {
          // The task remains accessible without the personal groups list.
        }
        if (!mounted) return;
        highlight(2); // Tasks
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          clipBehavior: Clip.none,
          builder: (_) => TaskDetailsSheet(
            taskId: taskId, service: service, groups: groups,
          ),
        );
      } else if (uri.path == '/chat') {
        final conversationId = uri.queryParameters['conversation'];
        if (conversationId == null || conversationId.isEmpty) return;
        final chats = await ChatService().getConversations();
        Map<dynamic, dynamic>? selected;
        for (final chat in chats) {
          if (chat is Map && chat['id']?.toString() == conversationId) {
            selected = chat;
            break;
          }
        }
        if (selected == null) throw StateError('საუბარი მიუწვდომელია');
        if (!mounted) return;
        highlight(1); // Messages
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ChatDetailScreen(
            conversationId: conversationId,
            chatName: (selected!['name'] ?? selected['title'] ?? 'Messages').toString(),
          ),
        ));
      } else if (uri.path == '/approvals') {
        final requestId = uri.queryParameters['request'];
        if (requestId == null || requestId.isEmpty || !mounted) return;
        highlight(3); // Approvals
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ApprovalsScreen(focusRequestId: requestId),
        ));
      }
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      // Back from any detail (or a failed navigation) restores the previous
      // bottom-tab highlight; reading status stays managed by the Inbox API.
      if (highlighted) widget.onDestinationChanged?.call(null);
      if (mounted) {
        setState(() => _busyId = null);
        _load(silent: true);
      }
    }
  }

  static IconData _iconFor(String type) {
    if (type.startsWith('TASK_')) return Icons.task_alt_rounded;
    if (type.startsWith('APPROVAL_')) return Icons.assignment_turned_in_outlined;
    if (type == 'MESSAGE' || type == 'MESSAGE_REACTION' || type == 'MENTION') {
      return Icons.chat_bubble_outline_rounded;
    }
    return Icons.notifications_none_rounded;
  }

  static Color _colorFor(String type) {
    if (type.startsWith('TASK_')) return const Color(0xFF16BE89);
    if (type.startsWith('APPROVAL_')) return const Color(0xFF4385F7);
    if (type == 'MESSAGE' || type == 'MESSAGE_REACTION' || type == 'MENTION') {
      return const Color(0xFFF2A52C);
    }
    return const Color(0xFF4385F7);
  }

  static String _timeFor(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final ago = DateTime.now().difference(date);
    if (ago.isNegative || ago.inMinutes < 1) return 'ახლახან';
    if (ago.inMinutes < 60) return '${ago.inMinutes} წუთის წინ';
    if (ago.inHours < 24) return '${ago.inHours} საათის წინ';
    if (ago.inDays == 1) return 'გუშინ';
    if (ago.inDays < 7) return '${ago.inDays} დღის წინ';
    return '${date.day.toString().padLeft(2, '0')}.' +
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: palette.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 13),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.card,
                shape: BoxShape.circle,
                border: Border.all(color: palette.cardBorder),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Back',
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: palette.secondaryText,
                  size: 20,
                ),
                onPressed: () {
                  Navigator.of(context).maybePop();
                },
              ),
            ),
          ),
        ),
        centerTitle: true,
        title: Text(
          'Notifications',
          style: TextStyle(
            color: palette.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 13),
            child: Center(
              child: TextButton(
                 onPressed: _markingAll || _unreadCount == 0 ? null : _readAll,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 33),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  backgroundColor: isDark
                      ? palette.searchBackground
                      : const Color(0xFFF0F5FF),
                  side: BorderSide(color: palette.cardBorder),
                  shape: const StadiumBorder(),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Read All',
                  style: TextStyle(
                    color: palette.link,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(55),
          child: Container(
            height: 55,
            width: double.infinity,
            alignment: Alignment.topCenter,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: palette.cardBorder),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _filterPill(
                    palette: palette,
                    title: 'All (${_items.length})',
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _filterPill(
                    palette: palette,
                    title: 'Unread ($_unreadCount)',
                    selected: _filter == 'unread',
                    onTap: () => setState(() => _filter = 'unread'),
                  ),
                  const SizedBox(width: 8),
                  _filterPill(
                    palette: palette,
                    title: 'Mentions',
                    selected: _filter == 'mentions',
                    onTap: () => setState(() => _filter = 'mentions'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [palette.page, palette.page]
                : [palette.page, const Color(0xFFEDF9F5)],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: () => _load(silent: true),
          child: _error != null && _items.isEmpty && !_loading
              ? AppLoadErrorViewport(
                  description: _error,
                  onRetry: () => _load(),
                )
              : ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 25),
            children: [
              if (_error != null && _items.isNotEmpty) ...[
                AppLoadErrorNotice(onRetry: () => _load(silent: true)),
                const SizedBox(height: 12),
              ],
              if (_loading && _items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_visibleItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('შეტყობინებები არ მოიძებნა')),
                )
              else
                for (final item in _visibleItems) ...[
                  _buildNotificationItem(
                    icon: _iconFor((item['type'] ?? '').toString()),
                    color: _colorFor((item['type'] ?? '').toString()),
                    title: (item['title'] ?? '').toString(),
                    description: (item['body'] ?? '').toString(),
                    time: _timeFor(item['createdAt']),
                    isRead: item['isRead'] == true,
                    context: context,
                    onTap: () => _open(item),
                    onLongPress: () => _toggleRead(item),
                  ),
                  const SizedBox(height: 11),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterPill({
    required AppPalette palette,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : palette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? AppColors.primary : palette.cardBorder,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 7,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Text(
        title,
        style: TextStyle(
          color: selected ? Colors.white : palette.secondaryText,
          fontSize: 11,
          height: 1.1,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      ),
    );
  }

  Widget _buildNotificationItem({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required String time,
    required bool isRead,
    required BuildContext context,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 15, 13, 15),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.panelShadow,
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.19 : 0.085),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 13,
                    height: 1.26,
                    fontWeight: isRead ? FontWeight.w700 : FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.secondaryText,
                    fontSize: 11.5,
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 12,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isRead) ...[
            const SizedBox(width: 7),
            Container(
              margin: const EdgeInsets.only(top: 3),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton>
    with WidgetsBindingObserver {
  final NotificationService _service = NotificationService();
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _service.connect(() {
        if (mounted) _refresh();
      });
    } catch (_) {
      // A socket outage must never disable the notification button.
    }
  }

  Future<void> _refresh() async {
    try {
      final inbox = await _service.getInbox();
      if (mounted) setState(() => _unread = inbox.unreadCount);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.disposeSocket();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'შეტყობინებები',
          padding: EdgeInsets.zero,
          onPressed: widget.onPressed,
          icon: Icon(Icons.notifications_none_rounded, color: palette.ink, size: 22),
        ),
        if (_unread > 0)
          Positioned(
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.all(Radius.circular(9)),
                ),
                child: Text(
                  _unread > 99 ? '99+' : '$_unread',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
