import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/dashboard/data/dashboard_service.dart';
import '../features/notifications/data/notification_service.dart';
import '../core/widgets/load_error_state.dart';
import 'notifications_screen.dart';
import 'main_navigation.dart';

enum DashboardQuickAction { task, request, conversation }

class DashboardScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final String currentLanguage;
  final ThemeMode currentThemeMode;
  final void Function(DashboardQuickAction action)? onQuickAction;
  /// Navigate to an existing module (without opening a creation modal).
  final ValueChanged<int>? onNavigateToModule;
  /// Keeps the floating nav in sync with a notification's details screen.
  final ValueChanged<int?>? onNotificationDestinationChanged;
  final DashboardService? dashboardService;
  final NotificationService? notificationService;

  const DashboardScreen({
    super.key,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.currentLanguage,
    required this.currentThemeMode,
    this.onQuickAction,
    this.onNavigateToModule,
    this.onNotificationDestinationChanged,
    this.dashboardService,
    this.notificationService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final DashboardService _dashboardService;
  late final NotificationService _notificationService;
  late final AnimationController _unreadPulse;
  late final Animation<double> _pulseOpacity;
  List<Map<String, dynamic>> _latestUpdates = [];
  bool _updatesLoading = true;
  String? _updatesError;
  int _updatesVersion = 0;

  bool _isLoading = true;
  String _userName = 'მომხმარებელი';
  String _activeTasksCount = '...';
  String _pendingApprovalsCount = '...';

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _notificationService = widget.notificationService ?? NotificationService();
    _unreadPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _pulseOpacity = Tween<double>(begin: 0.48, end: 1.0).animate(
      CurvedAnimation(parent: _unreadPulse, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addObserver(this);
    _loadDashboardData();
    _loadUpdates();
    _connectUpdates();
  }

  Future<void> _connectUpdates() async {
    try {
      await _notificationService.connect(() {
        if (mounted) _loadUpdates(silent: true);
      });
    } catch (_) {
      // The dashboard is still usable if the realtime socket is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadUpdates(silent: true);
  }

  @override
  void dispose() {
    _updatesVersion++;
    WidgetsBinding.instance.removeObserver(this);
    _notificationService.disposeSocket();
    _unreadPulse.dispose();
    super.dispose();
  }

  Future<void> _loadUpdates({bool silent = false}) async {
    final version = ++_updatesVersion;
    if (!silent && mounted) setState(() => _updatesLoading = true);
    try {
      // The web dashboard shows the first four server-ordered notifications.
      final inbox = await _notificationService.getInbox();
      if (!mounted || version != _updatesVersion) return;
      final latest = inbox.items.take(4).toList(growable: false);
      setState(() {
        _latestUpdates = latest;
        _updatesError = null;
      });
      if (latest.any((n) => n['isRead'] != true)) {
        if (!_unreadPulse.isAnimating) _unreadPulse.repeat(reverse: true);
      } else {
        _unreadPulse.stop();
        _unreadPulse.value = 1;
      }
    } catch (error) {
      if (!mounted || version != _updatesVersion) return;
      setState(() => _updatesError = loadErrorDescription(error));
    } finally {
      if (mounted && version == _updatesVersion) {
        setState(() => _updatesLoading = false);
      }
    }
  }

  Future<void> _refreshDashboard() async {
    await Future.wait<void>([
      _loadDashboardData(),
      _loadUpdates(silent: true),
    ]);
  }

  Future<void> _openInbox({String? notificationId}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NotificationsScreen(
        openNotificationId: notificationId,
        onDestinationChanged: widget.onNotificationDestinationChanged,
      ),
    ));
    if (mounted) await _loadUpdates(silent: true);
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final profile = await _dashboardService.getUserProfile();
      final metrics = await _dashboardService.getDashboardMetrics();

      if (mounted) {
        setState(() {
          if (profile != null) {
            _userName = profile['firstName'] ?? profile['name'] ?? profile['email'] ?? 'მომხმარებელი';
          }
          _activeTasksCount = metrics['activeTasks'] ?? '0';
          _pendingApprovalsCount = metrics['pendingApprovals'] ?? '0';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        titleSpacing: 14,
        title: Text(
          'Dashboard',
          style: TextStyle(
            color: palette.ink,
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.65,
          ),
        ),
        actions: buildGlobalActions(
          context,
          widget.onToggleTheme,
          widget.onChangeLanguage,
          widget.currentLanguage,
          widget.currentThemeMode,
          onNotificationDestinationChanged:
              widget.onNotificationDestinationChanged,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 24),
          children: [
            Text(
              'მოგესალმებით, $_userName!',
              style: TextStyle(
                color: palette.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.45,
              ),
            ),
            const SizedBox(height: 21),
            _isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 42),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'აქტიური დავალებები',
                          _activeTasksCount,
                          Icons.task_alt_rounded,
                          const Color(0xFFEAA229),
                          onTap: () => widget.onNavigateToModule?.call(2),
                          cardKey: const ValueKey('dashboard-active-tasks-card'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricCard(
                          'მოლოდინში დამტკიცება',
                          _pendingApprovalsCount,
                          Icons.assignment_turned_in_outlined,
                          AppColors.primary,
                          onTap: () => widget.onNavigateToModule?.call(3),
                          cardKey: const ValueKey('dashboard-pending-approvals-card'),
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 22),
            _sectionTitle('სწრაფი ქმედებები'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(6, 13, 6, 12),
              decoration: _panelDecoration(palette),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildActionButton(
                      context,
                      Icons.add_task_rounded,
                      'ახალი დავალება',
                      () => widget.onQuickAction?.call(DashboardQuickAction.task),
                      primary: true,
                    ),
                  ),
                  Expanded(
                    child: _buildActionButton(
                      context,
                      Icons.post_add_rounded,
                      'მოთხოვნის შექმნა',
                      () => widget.onQuickAction?.call(DashboardQuickAction.request),
                    ),
                  ),
                  Expanded(
                    child: _buildActionButton(
                      context,
                      Icons.chat_bubble_outline_rounded,
                      'საუბრის დაწყება',
                      () => widget.onQuickAction?.call(DashboardQuickAction.conversation),
                      purple: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 23),
            _latestUpdatesSection(palette),
            const SizedBox(height: 23),
            _sectionTitle('სისტემური სტატუსი'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: _panelDecoration(palette),
              child: Column(
                children: [
                  _buildActivityItem(
                    'ბექენდ სერვერთან კავშირი',
                    'აქტიური (Online)',
                    const Color(0xFF13BE88),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.7,
                    color: palette.cardBorder,
                  ),
                  _buildActivityItem(
                    'რეალურ დროში სოკეტები',
                    'დაკავშირებულია',
                    const Color(0xFF4385F7),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _updateDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _updateDot(AppPalette palette, bool unread) {
    if (!unread) {
      return Container(
        key: const ValueKey('dashboard-read-dot'),
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: palette.muted.withValues(alpha: 0.30),
          shape: BoxShape.circle,
        ),
      );
    }
    // Only unread items pulse. On reading, the server-backed isRead flag
    // swaps this for a static neutral dot; permanent selections are unaffected.
    return FadeTransition(
      key: const ValueKey('dashboard-unread-dot'),
      opacity: _pulseOpacity,
      child: Container(
        width: 12, height: 12,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.32),
              blurRadius: 10,
              spreadRadius: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _latestUpdatesSection(AppPalette palette) {
    return Container(
      key: const ValueKey('dashboard-latest-updates'),
      decoration: _panelDecoration(palette),
      padding: const EdgeInsets.fromLTRB(14, 17, 14, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('Latest updates', style: TextStyle(
              color: palette.ink, fontSize: 17,
              fontWeight: FontWeight.w800, letterSpacing: -0.35,
            ))),
            TextButton(
              key: const ValueKey('dashboard-open-inbox'),
              onPressed: () => _openInbox(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Open inbox', style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800,
                  )),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
              style: TextButton.styleFrom(
                foregroundColor: palette.link,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 36),
              ),
            ),
          ]),
          const SizedBox(height: 13),
          if (_updatesLoading && _latestUpdates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_updatesError != null && _latestUpdates.isEmpty)
            AppLoadErrorState(
              compact: true,
              description: _updatesError,
              onRetry: () => _loadUpdates(),
            )
          else if (_latestUpdates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text("You're all caught up.",
                style: TextStyle(color: palette.muted, fontSize: 12)),
            )
          else ...[
            if (_updatesError != null) ...[
              AppLoadErrorNotice(onRetry: () => _loadUpdates(silent: true)),
              const SizedBox(height: 10),
            ],
            for (final item in _latestUpdates) ...[
              Semantics(
                button: true,
                label: '${item['title'] ?? 'Update'}',
                child: GestureDetector(
                  key: ValueKey('dashboard-update-${item['id']}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: item['id'] == null
                      ? null
                      : () => _openInbox(
                          notificationId: item['id'].toString()),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(13, 14, 12, 14),
                    decoration: BoxDecoration(
                      color: palette.panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: palette.cardBorder.withValues(alpha: 0.50)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: _updateDot(palette, item['isRead'] != true),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (item['title'] ?? 'Update').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5, color: palette.ink,
                                fontWeight: item['isRead'] == true
                                    ? FontWeight.w600 : FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text((item['body'] ?? '').toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.secondaryText,
                                fontSize: 11.5, height: 1.25,
                              ),
                            ),
                          ],
                        )),
                        const SizedBox(width: 7),
                        Text(_updateDate(item['createdAt']),
                          style: TextStyle(
                            color: palette.muted, fontSize: 9.5,
                          )),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration(AppPalette palette) {
    return BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: palette.cardBorder),
      boxShadow: [
        BoxShadow(
          color: palette.panelShadow,
          blurRadius: 19,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Text(
      title,
      style: TextStyle(
        color: palette.ink,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color accent, {
    required VoidCallback onTap,
    required Key cardKey,
  }) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: cardKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: Container(
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
      decoration: _panelDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.075),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.35 : 0.18),
                  ),
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              Icon(
                Icons.north_east_rounded,
                size: 16,
                color: palette.muted.withValues(alpha: 0.45),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            value,
            style: TextStyle(
              color: palette.ink,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.secondaryText,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool primary = false,
    bool purple = false,
  }) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = purple ? const Color(0xFF7561EE) : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 49,
                height: 49,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: primary
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.gradientStart,
                            AppColors.gradientEnd,
                          ],
                        )
                      : null,
                  color: primary
                      ? null
                      : accent.withValues(alpha: isDark ? 0.17 : 0.055),
                  shape: BoxShape.circle,
                  border: primary
                      ? null
                      : Border.all(
                          color: accent.withValues(
                            alpha: isDark ? 0.31 : 0.12,
                          ),
                        ),
                  boxShadow: primary
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: primary ? Colors.white : accent,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.secondaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityItem(
    String title,
    String subtitle,
    Color indicatorColor,
  ) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: indicatorColor.withValues(alpha: isDark ? 0.16 : 0.075),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: indicatorColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: indicatorColor.withValues(alpha: 0.30),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: indicatorColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: indicatorColor.withValues(alpha: isDark ? 0.16 : 0.085),
            ),
            child: Icon(Icons.check_rounded, color: indicatorColor, size: 15),
          ),
        ],
      ),
    );
  }
}
