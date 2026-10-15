// lib/main.dart
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';

import 'features/auth/data/presentation/splash_screen.dart';

void main() {
  runApp(const InternalCollaborationApp());
}

class InternalCollaborationApp extends StatefulWidget {
  const InternalCollaborationApp({super.key});

  @override
  State<InternalCollaborationApp> createState() =>
      _InternalCollaborationAppState();
}

class _InternalCollaborationAppState extends State<InternalCollaborationApp> {
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
