import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';

/// Stitch-inspired notification inbox.
/// The three existing sample notifications are intentionally unchanged.
/// Read All and the category tabs remain presentation-only until their
/// behaviour is implemented in a separate task.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: palette.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 13),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.card,
                shape: BoxShape.circle,
                border: Border.all(color: palette.cardBorder),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Back',
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: palette.secondaryText,
                  size: 20,
                ),
                onPressed: () {
                  Navigator.of(context).maybePop();
                },
              ),
            ),
          ),
        ),
        centerTitle: true,
        title: Text(
          'Notifications',
          style: TextStyle(
            color: palette.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 13),
            child: Center(
              child: TextButton(
                // Preserve the existing no-op action.
                onPressed: () {},
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 33),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  backgroundColor: isDark
                      ? palette.searchBackground
                      : const Color(0xFFF0F5FF),
                  side: BorderSide(color: palette.cardBorder),
                  shape: const StadiumBorder(),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Read All',
                  style: TextStyle(
                    color: palette.link,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(55),
          child: Container(
            height: 55,
            width: double.infinity,
            alignment: Alignment.topCenter,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: palette.cardBorder),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _filterPill(
                    palette: palette,
                    title: 'All (3)',
                    selected: true,
                  ),
                  const SizedBox(width: 8),
                  _filterPill(
                    palette: palette,
                    title: 'Unread (2)',
                    selected: false,
                  ),
                  const SizedBox(width: 8),
                  _filterPill(
                    palette: palette,
                    title: 'Mentions',
                    selected: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [palette.page, palette.page]
                : [palette.page, const Color(0xFFEDF9F5)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 25),
          children: [
            _buildNotificationItem(
              icon: Icons.task_alt_rounded,
              color: const Color(0xFF16BE89),
              title: 'დავალება განახლდა',
              description:
                  'გიორგიმ შეცვალა დავალების სტატუსი: API სერვისის ოპტიმიზაცია.',
              time: '15 წუთის წინ',
              isRead: false,
              context: context,
            ),
            const SizedBox(height: 11),
            _buildNotificationItem(
              icon: Icons.assignment_turned_in_outlined,
              color: const Color(0xFF4385F7),
              title: 'ახალი დამტკიცების ნაბიჯი',
              description:
                  'თქვენ გევალებათ აღჭურვილობის შეძენის მოთხოვნის განხილვა.',
              time: '2 საათის წინ',
              isRead: false,
              context: context,
            ),
            const SizedBox(height: 11),
            _buildNotificationItem(
              icon: Icons.chat_bubble_outline_rounded,
              color: const Color(0xFFF2A52C),
              title: 'ახალი მითითება (Mention)',
              description: 'ნინომ დაგგაკოთ არხში: #IT დეპარტამენტი.',
              time: 'გუშინ',
              isRead: true,
              context: context,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPill({
    required AppPalette palette,
    required String title,
    required bool selected,
  }) {
    // Deliberately decorative: filters are not implemented in this UI task.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : palette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? AppColors.primary : palette.cardBorder,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 7,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Text(
        title,
        style: TextStyle(
          color: selected ? Colors.white : palette.secondaryText,
          fontSize: 11,
          height: 1.1,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNotificationItem({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required String time,
    required bool isRead,
    required BuildContext context,
  }) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 15, 13, 15),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.panelShadow,
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.19 : 0.085),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 13,
                    height: 1.26,
                    fontWeight: isRead ? FontWeight.w700 : FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.secondaryText,
                    fontSize: 11.5,
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 12,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isRead) ...[
            const SizedBox(width: 7),
            Container(
              margin: const EdgeInsets.only(top: 3),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
