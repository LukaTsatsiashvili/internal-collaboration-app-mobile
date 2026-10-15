// lib/main.dart
import 'package:flutter/material.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
