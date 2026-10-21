import 'package:flutter/material.dart';
import '../auth_service.dart';
import 'login_screen.dart';
import 'package:gtex_collab_app/screens/main_navigation.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final String currentLanguage;
  final ThemeMode currentThemeMode;

  const SplashScreen({
    super.key,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.currentLanguage,
    required this.currentThemeMode,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();
  bool _unavailable = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _unavailable = false;
    });

    StartupSessionStatus result;
    try {
      result = await _authService.checkSession();
    } catch (_) {
      result = StartupSessionStatus.unavailable;
    }
    if (!mounted) return;

    if (result == StartupSessionStatus.unavailable) {
      setState(() {
        _checking = false;
        _unavailable = true;
      });
      return;
    }

    if (result == StartupSessionStatus.authenticated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainNavigationScreen(
            onToggleTheme: widget.onToggleTheme,
            onChangeLanguage: widget.onChangeLanguage,
            currentLanguage: widget.currentLanguage,
            currentThemeMode: widget.currentThemeMode,
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          onToggleTheme: widget.onToggleTheme,
          onChangeLanguage: widget.onChangeLanguage,
          currentLanguage: widget.currentLanguage,
          currentThemeMode: widget.currentThemeMode,
          showExpiredMessage: result == StartupSessionStatus.expired,
        ),
      ),
    );
  }

  Future<void> _signOutOffline() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          onToggleTheme: widget.onToggleTheme,
          onChangeLanguage: widget.onChangeLanguage,
          currentLanguage: widget.currentLanguage,
          currentThemeMode: widget.currentThemeMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_unavailable ? Icons.wifi_off_rounded : Icons.hub,
                    size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 22),
                if (_unavailable) ...[
                  const Text('სერვერთან დაკავშირება ვერ მოხერხდა',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  const Text(
                    'შეამოწმეთ ინტერნეტი და სცადეთ ხელახლა. '
                    'თქვენი სესია არ გაუქმებულა.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _checking ? null : _initializeApp,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ხელახლა ცდა'),
                  ),
                  TextButton(
                    onPressed: _checking ? null : _signOutOffline,
                    child: const Text('სხვა ანგარიშით შესვლა'),
                  ),
                ] else ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  const Text('იტვირთება სივრცე...'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
