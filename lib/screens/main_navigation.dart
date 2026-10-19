import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../core/theme/app_dropdown_theme.dart';
import 'dashboard_screen.dart';
import 'chats_screen.dart';
import 'tasks_screen.dart';
import 'approvals_screen.dart';
import 'drive_screen.dart';
import 'notifications_screen.dart';
import 'package:gtex_collab_app/features/auth/data/presentation/login_screen.dart';
import 'package:gtex_collab_app/features/auth/data/auth_service.dart';

class MainNavigationScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final String currentLanguage;
  final ThemeMode currentThemeMode;

  const MainNavigationScreen({
    super.key,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.currentLanguage,
    required this.currentThemeMode,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  DashboardQuickAction? _pendingQuickAction;
  int _quickActionLaunchId = 0;
  int _tabNavigationVersion = 0;
  int? _notificationDestinationIndex;

  /// A notification can show another module within the current shell stack.
  /// Update only the selected bottom tab, not the navigator's root/key:
  /// replacing the navigator here would destroy the opened detail route.
  void _setNotificationDestination(int? index) {
    if (!mounted || _currentIndex != 0) return;
    if (index != null && (index < 1 || index > 3)) return;
    if (_notificationDestinationIndex == index) return;
    setState(() => _notificationDestinationIndex = index);
  }

  /// Normal tab navigation (including dashboard metric cards) replaces the
  /// current stack with that module's root, without opening New Task/Request.
  void _navigateToTab(int index) {
    if (!mounted || index < 0 || index > 4) return;
    setState(() {
      _currentIndex = index;
      _pendingQuickAction = null;
      _notificationDestinationIndex = null;
      _tabNavigationVersion++;
    });
  }

  void _launchFromDashboard(DashboardQuickAction action) {
    setState(() {
      _pendingQuickAction = action;
      _notificationDestinationIndex = null;
      _quickActionLaunchId++;
      _currentIndex = switch (action) {
        DashboardQuickAction.conversation => 1,
        DashboardQuickAction.task => 2,
        DashboardQuickAction.request => 3,
      };
    });
  }


  // Floating bottom navigation inspired by the provided Stitch design.
  // Uses the same light/dark palette as the Messages screen.
  Widget _buildFloatingNavigation(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final background = palette.page;
    final surface = palette.navigation;
    final inactiveIcon = palette.navigationInactive;

    const destinations = <IconData>[
      Icons.grid_view_rounded,
      Icons.chat_bubble_outline_rounded,
      Icons.task_outlined,
      Icons.approval_outlined,
      Icons.folder_outlined,
    ];
    const selectedDestinations = <IconData>[
      Icons.grid_view_rounded,
      Icons.chat_bubble_rounded,
      Icons.task_rounded,
      Icons.approval_rounded,
      Icons.folder_rounded,
    ];
    const labels = <String>[
      'მთავარი',
      'ჩათები',
      'დავალებები',
      'მოთხოვნები',
      'Drive',
    ];

    return ColoredBox(
      color: background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Container(
            height: 72,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: palette.navigationBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.navigationShadow,
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: List.generate(destinations.length, (index) {
                final selected =
                    (_notificationDestinationIndex ?? _currentIndex) == index;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: labels[index],
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label: labels[index],
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: Theme.of(context).brightness == Brightness.dark
                                            ? 0.36
                                            : 0.30,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () => _navigateToTab(index),
                              child: Center(
                                child: Icon(
                                  selected
                                      ? selectedDestinations[index]
                                      : destinations[index],
                                  size: 25,
                                  color: selected ? Colors.white : inactiveIcon,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Remember the source navigator generation. An old notification Future
    // must not overwrite the selected tab if the user has since navigated.
    final sourceTabVersion = _tabNavigationVersion;
    final sourceQuickActionVersion = _quickActionLaunchId;
    final List<Widget> screens = [
      DashboardScreen(
        onToggleTheme: widget.onToggleTheme,
        onChangeLanguage: widget.onChangeLanguage,
        currentLanguage: widget.currentLanguage,
        currentThemeMode: widget.currentThemeMode,
        onQuickAction: _launchFromDashboard,
        onNavigateToModule: _navigateToTab,
        onNotificationDestinationChanged: (index) {
          if (sourceTabVersion != _tabNavigationVersion ||
              sourceQuickActionVersion != _quickActionLaunchId) {
            return;
          }
          _setNotificationDestination(index);
        },
      ),
      ChatsScreen(
        key: ValueKey('chat-$_quickActionLaunchId'),
        openCreateOnStart:
            _pendingQuickAction == DashboardQuickAction.conversation,
      ),
      TasksScreen(
        key: ValueKey('tasks-$_quickActionLaunchId'),
        openCreateOnStart:
            _pendingQuickAction == DashboardQuickAction.task,
      ),
      ApprovalsScreen(
        key: ValueKey('approvals-$_quickActionLaunchId'),
        openCreateOnStart:
            _pendingQuickAction == DashboardQuickAction.request,
      ),
      const DriveScreen(),
    ];

    return Scaffold(
      // All secondary routes (Inbox, task/approval details and chats) are
      // pushed inside this navigator, never above MainNavigationScreen.
      // The floating navigation bar therefore stays visible and usable.
      // Changing tabs replaces only this navigator's stack with the chosen
      // root. Include language/theme to keep root widgets in sync when the
      // app's appearance is changed from the Dashboard profile controls.
      body: HeroControllerScope.none(
        // The root MaterialApp already owns a HeroController; never attach
        // the same controller to this nested body navigator.
        child: Navigator(
          key: ValueKey<String>(
            'app-shell-$_currentIndex-$_quickActionLaunchId-'
            '$_tabNavigationVersion-${widget.currentLanguage}-'
            '${widget.currentThemeMode}',
          ),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => screens[_currentIndex],
          ),
        ),
      ),
      bottomNavigationBar: _buildFloatingNavigation(context),
    );
  }
}

// Dashboard actions keep the original notification and profile callbacks.
// Only the buttons and popup menu items are styled to match the app theme.
PopupMenuItem<String> _profileMenuItem(
  BuildContext context, {
  required String value,
  required IconData icon,
  required String title,
  required String subtitle,
  bool destructive = false,
}) {
  final palette = Theme.of(context).extension<AppPalette>()!;
  final accent = destructive ? Theme.of(context).colorScheme.error : palette.link;
  return PopupMenuItem<String>(
    value: value,
    height: 66,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Container(
          width: 39,
          height: 39,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: destructive ? accent : palette.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: palette.secondaryText,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          color: palette.muted,
          size: 18,
        ),
      ],
    ),
  );
}

List<Widget> buildGlobalActions(
  BuildContext context,
  VoidCallback onToggleTheme,
  VoidCallback onChangeLanguage,
  String currentLanguage,
  ThemeMode currentThemeMode, {
  ValueChanged<int?>? onNotificationDestinationChanged,
}) {
  final palette = Theme.of(context).extension<AppPalette>()!;
  return [
    Padding(
      padding: const EdgeInsets.only(right: 9),
      child: Container(
        width: 39,
        height: 39,
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.cardBorder),
          boxShadow: [
            BoxShadow(
              color: palette.cardShadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: NotificationBellButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NotificationsScreen(
                onDestinationChanged: onNotificationDestinationChanged,
              )),
            );
          },
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(right: 14),
      child: AppDropdownTheme(
        child: PopupMenuButton<String>(
        tooltip: 'პროფილის მენიუ',
        offset: const Offset(0, 46),
        elevation: 9,
        color: palette.panel,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(minWidth: 254, maxWidth: 286),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(21),
          side: BorderSide(color: palette.cardBorder),
        ),
        onSelected: (value) async {
          if (value == 'theme') {
            onToggleTheme();
          } else if (value == 'language') {
            onChangeLanguage();
          } else if (value == 'logout') {
            // ვასრულებთ ბექენდ და ლოკალურ გასვლას
            final AuthService authService = AuthService();
            await authService.logout();

            if (context.mounted) {
              // ვასუფთავებთ მთელ ნავიგაციის ისტორიას და ვბრუნდებით ლოგინზე
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => LoginScreen(
                    onToggleTheme: onToggleTheme,
                    onChangeLanguage: onChangeLanguage,
                    currentLanguage: currentLanguage,
                    currentThemeMode: currentThemeMode,
                  ),
                ),
                (route) => false,
              );
            }
          }
        },
        itemBuilder: (popupContext) => [
          _profileMenuItem(
            popupContext,
            value: 'language',
            icon: Icons.translate_rounded,
            title: 'ენის შეცვლა',
            subtitle: 'ქართული / English',
          ),
          _profileMenuItem(
            popupContext,
            value: 'theme',
            icon: Theme.of(popupContext).brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            title: 'თემის შეცვლა',
            subtitle: 'Light / Dark',
          ),
          _profileMenuItem(
            popupContext,
            value: 'logout',
            icon: Icons.logout_rounded,
            title: 'გასვლა',
            subtitle: 'სისტემიდან გასვლა',
            destructive: true,
          ),
        ],
        child: Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.20),
                blurRadius: 9,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.account_circle_outlined,
            color: Colors.white,
            size: 23,
          ),
        ),
        ),
      ),
    ),
  ];
}
