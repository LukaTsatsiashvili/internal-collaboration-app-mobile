// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';

import 'features/auth/data/presentation/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the phone's top status indicators visible, but hide its bottom
  // Android navigation bar to give the Flutter app more usable space.
  await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
  runApp(const InternalCollaborationApp());
}

class InternalCollaborationApp extends StatefulWidget {
  const InternalCollaborationApp({super.key});

  @override
  State<InternalCollaborationApp> createState() =>
      _InternalCollaborationAppState();
}

class _InternalCollaborationAppState extends State<InternalCollaborationApp>
    with WidgetsBindingObserver {
  bool _keyboardWasVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _restoreImmersiveMode();
  }

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final keyboardVisible = views.any((view) => view.viewInsets.bottom > 0);
    if (_keyboardWasVisible && !keyboardVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreImmersiveMode();
      });
    }
    _keyboardWasVisible = keyboardVisible;
  }

  void _restoreImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
  }

  ThemeMode _themeMode = ThemeMode.dark;
  String _currentLanguage = 'ka';

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  void _changeLanguage() {
    setState(() {
      _currentLanguage = _currentLanguage == 'ka' ? 'en' : 'ka';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Internal Collaboration',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: SplashScreen(
        onToggleTheme: _toggleTheme,
        onChangeLanguage: _changeLanguage,
        currentLanguage: _currentLanguage,
        currentThemeMode: _themeMode,
      ),
    );
  }
}
