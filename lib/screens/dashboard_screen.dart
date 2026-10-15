import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/dashboard/data/dashboard_service.dart';
import 'main_navigation.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final String currentLanguage;
  final ThemeMode currentThemeMode;

  const DashboardScreen({
    super.key,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.currentLanguage,
    required this.currentThemeMode,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();

  bool _isLoading = true;
  String _userName = 'მომხმარებელი';
  String _activeTasksCount = '...';
  String _pendingApprovalsCount = '...';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
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
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
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
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricCard(
                          'მოლოდინში დამტკიცება',
                          _pendingApprovalsCount,
                          Icons.assignment_turned_in_outlined,
                          AppColors.primary,
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
                      () {},
                      primary: true,
                    ),
                  ),
                  Expanded(
                    child: _buildActionButton(
                      context,
                      Icons.post_add_rounded,
                      'მოთხოვნის შექმნა',
                      () {},
                    ),
                  ),
                  Expanded(
                    child: _buildActionButton(
                      context,
                      Icons.group_add_outlined,
                      'ჯგუფის შექმნა',
                      () {},
                      purple: true,
                    ),
                  ),
                ],
              ),
            ),
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
    Color accent,
  ) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
