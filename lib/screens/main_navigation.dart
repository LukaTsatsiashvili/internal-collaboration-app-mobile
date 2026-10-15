import 'package:flutter/material.dart';
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


  // Floating bottom navigation inspired by the provided Stitch design.
  // Uses the same light/dark palette as the Messages screen.
  Widget _buildFloatingNavigation(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF101827)
        : const Color(0xFFEDF2FE);
    final surface = isDark
        ? const Color(0xFF243149)
        : const Color(0xFFFDFEFF);
    final inactiveIcon = isDark
        ? const Color(0xFF9DADC7)
        : const Color(0xFF778AA5);

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
                color: isDark
                    ? const Color(0xFF34435B)
                    : Colors.white,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.28)
                      : const Color(0xFF7183A3).withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: List.generate(destinations.length, (index) {
                final selected = _currentIndex == index;
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
                                ? const Color(0xFF2465EE)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF2465EE)
                                          .withValues(alpha: isDark ? 0.36 : 0.30),
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
                              onTap: () {
                                setState(() {
                                  _currentIndex = index;
                                });
                              },
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
    final List<Widget> screens = [
      DashboardScreen(
        onToggleTheme: widget.onToggleTheme,
        onChangeLanguage: widget.onChangeLanguage,
        currentLanguage: widget.currentLanguage,
        currentThemeMode: widget.currentThemeMode,
      ),
      const ChatsScreen(),
      const TasksScreen(),
      const ApprovalsScreen(),
      const DriveScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: _buildFloatingNavigation(context),
    );
  }
}

List<Widget> buildGlobalActions(BuildContext context, VoidCallback onToggleTheme, VoidCallback onChangeLanguage, String currentLanguage, ThemeMode currentThemeMode) {
  return [
    IconButton(
      icon: const Icon(Icons.notifications_outlined),
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      },
    ),
    Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 50),
        icon: const CircleAvatar(
          radius: 16,
          backgroundColor: Colors.blueAccent,
          child: Text('ლ', style: TextStyle(color: Colors.white, fontSize: 14)),
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
              Navigator.pushAndRemoveUntil(
                context,
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
        itemBuilder: (BuildContext context) => [
          PopupMenuItem<String>(
            value: 'theme',
            child: Row(children: [
              Icon(currentThemeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode, size: 20),
              const SizedBox(width: 10),
              Text(currentThemeMode == ThemeMode.dark ? 'ნათელი თემა (Light)' : 'მუქი თემა (Dark)'),
            ]),
          ),
          PopupMenuItem<String>(
            value: 'language',
            child: Row(children: [
              const Icon(Icons.language, size: 20),
              const SizedBox(width: 10),
              Text('ენა: ${currentLanguage == 'ka' ? 'ქართული' : 'English'}'),
            ]),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(children: [
              Icon(Icons.logout, size: 20, color: Colors.red),
              SizedBox(width: 10),
              Text('გასვლა (Log Out)', style: TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    ),
  ];
}