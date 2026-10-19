import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_dropdown_theme.dart';

void main() {
  test('selection menu stays exactly as wide as the parent control', () {
    final bounds = AppDropdownTheme.menuBounds(216.0, 260.0);
    expect(bounds.minWidth, 216.0);
    expect(bounds.maxWidth, 216.0);
    expect(bounds.maxHeight, 260.0);
    expect(AppDropdownTheme.menuGap, const Offset(0, 5));
  });

  testWidgets('trigger and popup menu use transparent feedback, with selection',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 210,
            child: AppDropdownTheme(
              child: LayoutBuilder(
                builder: (context, constraints) => PopupMenuButton<String>(
                  tooltip: 'Test dropdown',
                  position: PopupMenuPosition.under,
                  offset: AppDropdownTheme.menuGap,
                  constraints: AppDropdownTheme.menuBounds(
                    constraints.maxWidth, 240,
                  ),
                  onSelected: (value) => selected = value,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'one', child: Text('First choice')),
                    PopupMenuItem(value: 'two', child: Text('Second choice')),
                  ],
                  child: Container(
                    key: const ValueKey('dropdown-field'),
                    alignment: Alignment.centerLeft,
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: const Text('Choose option'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));

    final trigger = find.byType(PopupMenuButton<String>);
    final popup = tester.widget<PopupMenuButton<String>>(trigger);
    expect(popup.constraints!.maxWidth, lessThanOrEqualTo(210));
    expect(popup.constraints!.minWidth, 210);
    expect(popup.offset, const Offset(0, 5));

    final style = Theme.of(tester.element(find.byKey(
      const ValueKey('dropdown-field'),
    )));
    expect(style.splashFactory, NoSplash.splashFactory);
    expect(style.splashColor, Colors.transparent);
    expect(style.highlightColor, Colors.transparent);
    expect(style.hoverColor, Colors.transparent);
    expect(style.focusColor, Colors.transparent);

    await tester.tap(find.byKey(const ValueKey('dropdown-field')));
    await tester.pumpAndSettle();
    expect(find.text('First choice'), findsOneWidget);
    expect(find.text('Second choice'), findsOneWidget);
    final popupTheme = Theme.of(tester.element(find.text('First choice')));
    expect(popupTheme.splashFactory, NoSplash.splashFactory);
    expect(popupTheme.highlightColor, Colors.transparent);

    await tester.tap(find.text('Second choice'));
    await tester.pumpAndSettle();
    expect(selected, 'two');
    expect(tester.takeException(), isNull);
  });
}
