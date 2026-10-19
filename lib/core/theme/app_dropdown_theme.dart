import 'package:flutter/material.dart';

/// Shared visual behavior for selection dropdowns across the mobile app.
///
/// Scope these overrides to the dropdown rather than to the global app
/// ThemeData: other buttons must keep their existing touch feedback.
/// PopupMenuButton also captures this inherited theme for its popup route.
class AppDropdownTheme extends StatelessWidget {
  const AppDropdownTheme({super.key, required this.child});

  final Widget child;

  static const Offset menuGap = Offset(0, 5);

  /// An overlay never becomes wider than its own full-width trigger.
  /// Only use this for actual selection fields; an icon's context menu is a
  /// separate control and needs room to show readable actions.
  static BoxConstraints menuBounds(double parentWidth, double maxHeight) =>
      BoxConstraints(
        minWidth: parentWidth,
        maxWidth: parentWidth,
        maxHeight: maxHeight,
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
      ),
      child: child,
    );
  }
}
