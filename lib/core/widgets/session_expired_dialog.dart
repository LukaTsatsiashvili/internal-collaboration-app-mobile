import 'package:flutter/material.dart';

/// One consistent, non-dismissible explanation for a genuinely expired session.
Future<void> showSessionExpiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.lock_clock_outlined, size: 32),
        title: const Text('სესია დასრულდა'),
        content: const Text(
          'თქვენი სესია დასრულდა. უსაფრთხოების მიზნით, '
          'გთხოვთ ხელახლა შეხვიდეთ სისტემაში.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ავტორიზაციის გვერდზე გადასვლა'),
          ),
        ],
      ),
    ),
  );
}
