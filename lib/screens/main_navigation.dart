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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'მთავარი'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'ჩათები'),
          NavigationDestination(icon: Icon(Icons.task_outlined), selectedIcon: Icon(Icons.task), label: 'დავალებები'),
          NavigationDestination(icon: Icon(Icons.approval_outlined), selectedIcon: Icon(Icons.approval), label: 'მოთხოვნები'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Drive'),
        ],
      ),
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