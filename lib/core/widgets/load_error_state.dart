import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme_extensions.dart';

/// Turn transport errors into a short, safe explanation for the end user.
/// Never render DioException.toString(), URLs or response payloads in the UI.
String loadErrorDescription(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'შეამოწმეთ ინტერნეტკავშირი და სცადეთ ხელახლა.';
      case DioExceptionType.badCertificate:
        return 'სერვერთან უსაფრთხო კავშირი ვერ დამყარდა.';
      case DioExceptionType.badResponse:
        if (error.response?.statusCode == 401 ||
            error.response?.statusCode == 403) {
          return 'გადაამოწმეთ ავტორიზაცია და სცადეთ ხელახლა.';
        }
        if ((error.response?.statusCode ?? 0) >= 500) {
          return 'სერვერი დროებით მიუწვდომელია. სცადეთ მოგვიანებით.';
        }
        return 'მოთხოვნა ვერ შესრულდა. სცადეთ ხელახლა.';
      case DioExceptionType.cancel:
        return 'მოთხოვნა შეწყდა. სცადეთ ხელახლა.';
      default:
        return 'კავშირი ვერ დამყარდა. სცადეთ ხელახლა.';
    }
  }
  return 'მონაცემების მიღება ვერ მოხერხდა. სცადეთ ხელახლა.';
}

/// Reusable error surface for REST-driven modules. Compact mode fits within
/// the dashboard latest-updates card without changing its layout.
class AppLoadErrorState extends StatelessWidget {
  const AppLoadErrorState({
    super.key,
    required this.onRetry,
    this.description,
    this.compact = false,
  });

  final VoidCallback onRetry;
  final String? description;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      key: const ValueKey('app-load-error-state'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 22,
        vertical: compact ? 18 : 32,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.cardBorder),
        borderRadius: BorderRadius.circular(compact ? 16 : 22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 44 : 54,
            height: compact ? 44 : 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.unreadBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.cloud_off_outlined,
              size: compact ? 23 : 28,
              color: palette.link,
            ),
          ),
          SizedBox(height: compact ? 10 : 15),
          Text(
            'ინფორმაციის ჩატვირთვა ვერ მოხერხდა',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.ink,
              fontSize: compact ? 12.5 : 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            description ?? 'შეამოწმეთ კავშირი და სცადეთ ხელახლა.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.secondaryText,
              fontSize: compact ? 11 : 12.5,
              height: 1.4,
            ),
          ),
          SizedBox(height: compact ? 10 : 17),
          FilledButton.icon(
            key: const ValueKey('app-load-error-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('ხელახლა ცდა'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 38),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Place the shared error card in the available module viewport instead of
/// leaving it at the top of a short, empty list. The scroll view remains
/// usable on compact devices and supports a parent RefreshIndicator.
class AppLoadErrorViewport extends StatelessWidget {
  const AppLoadErrorViewport({
    super.key,
    required this.onRetry,
    this.description,
    this.compact = false,
  });

  final VoidCallback onRetry;
  final String? description;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight
                ? (constraints.maxHeight - 28).clamp(0.0, double.infinity)
                : 0,
          ),
          child: Center(
            child: AppLoadErrorState(
              onRetry: onRetry,
              description: description,
              compact: compact,
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-blocking notice while previously loaded records remain visible.
class AppLoadErrorNotice extends StatelessWidget {
  const AppLoadErrorNotice({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      key: const ValueKey('app-load-error-notice'),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: palette.unreadBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 19, color: palette.link),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'განახლება ვერ მოხერხდა',
              style: TextStyle(color: palette.ink, fontSize: 11.5),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('ხელახლა ცდა'),
          ),
        ],
      ),
    );
  }
}
