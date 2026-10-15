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

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // მცირე შეყოვნება (ލოგოს გამოჩენისთვის ან სესიის შესამოწმებლად)
    await Future.delayed(const Duration(seconds: 1));

    bool isLoggedIn = await _authService.checkSession();

    if (!mounted) return;

    if (isLoggedIn) {
      // თუ სესია აქტიურია, გადავდივართ მთავარ გვერდზე
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
    } else {
      // თუ ტოკენი არ არის ან გაუვიდა ვადა, მივდივართ ლოგინზე
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
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hub, size: 80, color: Colors.blue),
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('იტვირთება სივრცე...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}