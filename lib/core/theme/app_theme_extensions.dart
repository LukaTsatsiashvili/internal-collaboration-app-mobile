import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantic colors shared by every screen, independent of widget layout.
/// Always access through Theme.of(context).extension<AppPalette>()!.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color page;
  final Color panel;
  final Color card;
  final Color cardBorder;
  final Color searchBackground;
  final Color ink;
  final Color muted;
  final Color secondaryText;
  final Color previewText;
  final Color hintText;
  final Color searchIcon;
  final Color link;
  final Color navigation;
  final Color navigationInactive;
  final Color navigationBorder;
  final Color cardShadow;
  final Color panelShadow;
  final Color navigationShadow;
  final Color unreadBackground;

  const AppPalette({
    required this.page,
    required this.panel,
    required this.card,
    required this.cardBorder,
    required this.searchBackground,
    required this.ink,
    required this.muted,
    required this.secondaryText,
    required this.previewText,
    required this.hintText,
    required this.searchIcon,
    required this.link,
    required this.navigation,
    required this.navigationInactive,
    required this.navigationBorder,
    required this.cardShadow,
    required this.panelShadow,
    required this.navigationShadow,
    required this.unreadBackground,
  });

  // The previously approved Messages and bottom navigation light palette.
  static const AppPalette light = AppPalette(
    page: Color(0xFFEDF2FE),
    panel: Color(0xFFFAFCFF),
    card: Color(0xFFFEFEFF),
    cardBorder: Color(0xFFF2F5FB),
    searchBackground: Color(0xFFFCFDFE),
    ink: Color(0xFF151F36),
    muted: Color(0xFF8998B2),
    secondaryText: Color(0xFF687995),
    previewText: Color(0xFF8392A9),
    hintText: Color(0xFFA2AEC1),
    searchIcon: Color(0xFFB3C0D5),
    link: AppColors.primary,
    navigation: Color(0xFFFDFEFF),
    navigationInactive: Color(0xFF778AA5),
    navigationBorder: Colors.white,
    cardShadow: Color(0x0B53657F),
    panelShadow: Color(0x177183A3),
    navigationShadow: Color(0x267183A3),
    unreadBackground: Color(0xFFE8F0FF),
  );

  // Match the existing Messages dark theme throughout the app.
  static const AppPalette dark = AppPalette(
    page: Color(0xFF101827),
    panel: Color(0xFF192437),
    card: Color(0xFF243149),
    cardBorder: Color(0xFF32415A),
    searchBackground: Color(0xFF202C41),
    ink: Color(0xFFF4F7FF),
    muted: Color(0xFF9DADC7),
    secondaryText: Color(0xFFAABAD3),
    previewText: Color(0xFFB2C0D6),
    hintText: Color(0xFF95A6C0),
    searchIcon: Color(0xFF98AAC7),
    link: Color(0xFF84B0FF),
    navigation: Color(0xFF243149),
    navigationInactive: Color(0xFF9DADC7),
    navigationBorder: Color(0xFF34435B),
    cardShadow: Color(0x2E000000),
    panelShadow: Color(0x3D000000),
    navigationShadow: Color(0x47000000),
    unreadBackground: Color(0xFF283C5B),
  );

  @override
  AppPalette copyWith({
    Color? page,
    Color? panel,
    Color? card,
    Color? cardBorder,
    Color? searchBackground,
    Color? ink,
    Color? muted,
    Color? secondaryText,
    Color? previewText,
    Color? hintText,
    Color? searchIcon,
    Color? link,
    Color? navigation,
    Color? navigationInactive,
    Color? navigationBorder,
    Color? cardShadow,
    Color? panelShadow,
    Color? navigationShadow,
    Color? unreadBackground,
  }) {
    return AppPalette(
      page: page ?? this.page,
      panel: panel ?? this.panel,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      searchBackground: searchBackground ?? this.searchBackground,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      secondaryText: secondaryText ?? this.secondaryText,
      previewText: previewText ?? this.previewText,
      hintText: hintText ?? this.hintText,
      searchIcon: searchIcon ?? this.searchIcon,
      link: link ?? this.link,
      navigation: navigation ?? this.navigation,
      navigationInactive: navigationInactive ?? this.navigationInactive,
      navigationBorder: navigationBorder ?? this.navigationBorder,
      cardShadow: cardShadow ?? this.cardShadow,
      panelShadow: panelShadow ?? this.panelShadow,
      navigationShadow: navigationShadow ?? this.navigationShadow,
      unreadBackground: unreadBackground ?? this.unreadBackground,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      page: blend(page, other.page),
      panel: blend(panel, other.panel),
      card: blend(card, other.card),
      cardBorder: blend(cardBorder, other.cardBorder),
      searchBackground: blend(searchBackground, other.searchBackground),
      ink: blend(ink, other.ink),
      muted: blend(muted, other.muted),
      secondaryText: blend(secondaryText, other.secondaryText),
      previewText: blend(previewText, other.previewText),
      hintText: blend(hintText, other.hintText),
      searchIcon: blend(searchIcon, other.searchIcon),
      link: blend(link, other.link),
      navigation: blend(navigation, other.navigation),
      navigationInactive: blend(navigationInactive, other.navigationInactive),
      navigationBorder: blend(navigationBorder, other.navigationBorder),
      cardShadow: blend(cardShadow, other.cardShadow),
      panelShadow: blend(panelShadow, other.panelShadow),
      navigationShadow: blend(navigationShadow, other.navigationShadow),
      unreadBackground: blend(unreadBackground, other.unreadBackground),
    );
  }
}
