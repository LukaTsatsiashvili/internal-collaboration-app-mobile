import 'package:flutter/material.dart';

import 'app_theme_extensions.dart';

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


/// Tasks-style compact selection control for narrow dialogs.
///
/// Unlike DropdownButton, this uses the same bounded PopupMenuButton design
/// as New Task: selected-row background, a checkmark, and no tap highlight.
/// The menu is exactly as wide as its trigger, never the full dialog width.
class AppSelectDropdown<T> extends StatelessWidget {
  const AppSelectDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label = 'Choose option',
    this.height = 42,
    this.fontSize = 11.5,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String label;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>()!;
    final selectedIndex = items.indexWhere((item) => item.value == value);
    final selectedChild = selectedIndex < 0
        ? Text(label, overflow: TextOverflow.ellipsis)
        : items[selectedIndex].child;

    return AppDropdownTheme(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final menuWidth = constraints.maxWidth;
          final menuHeight = (MediaQuery.sizeOf(context).height * 0.38)
              .clamp(150.0, 320.0)
              .toDouble();
          return PopupMenuButton<int>(
            key: ValueKey('app-select-dropdown-$label'),
            tooltip: label,
            enabled: onChanged != null,
            position: PopupMenuPosition.under,
            offset: AppDropdownTheme.menuGap,
            padding: EdgeInsets.zero,
            elevation: 12,
            color: p.card,
            constraints: AppDropdownTheme.menuBounds(menuWidth, menuHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(19),
              side: BorderSide(color: p.cardBorder),
            ),
            onSelected: (index) => onChanged?.call(items[index].value),
            itemBuilder: (context) => [
              for (var i = 0; i < items.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  height: 49,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: i == selectedIndex
                          ? p.unreadBackground
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: DefaultTextStyle(
                            style: TextStyle(
                              color: p.ink,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            child: items[i].child,
                          ),
                        ),
                        if (i == selectedIndex) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.check_rounded, color: p.link, size: 15),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
            child: Container(
              height: height,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: p.cardBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle(
                      style: TextStyle(
                        color: p.ink,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: selectedChild,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: p.muted,
                    size: 17,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
