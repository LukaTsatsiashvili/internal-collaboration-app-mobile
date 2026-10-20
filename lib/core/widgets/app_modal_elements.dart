import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme_extensions.dart';

/// Common modal chrome, matching the New Task and New Group headers.
/// Kept separate from business logic so Drive dialogs share the same style.
class AppModalHeader extends StatelessWidget {
  const AppModalHeader({
    super.key,
    required this.title,
    required this.onClose,
  });

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>()!;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF89B0FF),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: p.card,
          shape: const CircleBorder(),
          child: Tooltip(
            message: 'Close',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onClose,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(
                  Icons.close_rounded,
                  size: 19,
                  color: p.muted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The same centered gradient action used in the Tasks modal footer.
/// Width is supplied by the parent to suit both short and long labels.
class AppModalPrimaryButton extends StatelessWidget {
  const AppModalPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.52,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          gradient: const LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
          boxShadow: [
            if (enabled)
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.20),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(23),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
