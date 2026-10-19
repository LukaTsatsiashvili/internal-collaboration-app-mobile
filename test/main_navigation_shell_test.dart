import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/notifications/data/notification_service.dart';
import 'package:gtex_collab_app/screens/approvals_screen.dart';
import 'package:gtex_collab_app/screens/main_navigation.dart';
import 'package:gtex_collab_app/screens/notifications_screen.dart';
import 'package:gtex_collab_app/screens/tasks_screen.dart';

class FakeShellNotificationService extends NotificationService {
  bool read = false;

  @override
  Future<NotificationInbox> getInbox() async => NotificationInbox(
    items: [
      {
        'id': 'approval-1',
        'type': 'APPROVAL_PENDING',
        'title': 'Review request',
        'body': 'Waiting for your approval',
        'isRead': read,
        'createdAt': '2026-10-19T10:00:00.000Z',
        'targetUrl': '/approvals?request=request-1',
      },
    ],
    unreadCount: read ? 0 : 1,
  );

  @override
  Future<void> markRead(String id) async {
    read = true;
  }

  @override
  Future<void> connect(void Function() refresh) async {}

  @override
  void disposeSocket() {}
}

void main() {
  testWidgets('shell keeps bottom navigation when opening and leaving Inbox',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: MainNavigationScreen(
        onToggleTheme: () {},
        onChangeLanguage: () {},
        currentLanguage: 'ka',
        currentThemeMode: ThemeMode.light,
      ),
    ));
    await tester.pump();
    expect(find.byTooltip('შეტყობინებები'), findsOneWidget);

    await tester.tap(find.byTooltip('შეტყობინებები'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byTooltip('დავალებები'), findsOneWidget);
    expect(find.byTooltip('მთავარი'), findsOneWidget);

    // Switching tabs discards the nested notification route and still
    // renders the one shared floating navigation bar.
    await tester.tap(find.byTooltip('დავალებები'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(find.byType(NotificationsScreen), findsNothing);
    expect(find.byTooltip('მთავარი'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification detail is routed inside a shell, not over its bar',
      (tester) async {
    final notifications = FakeShellNotificationService();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: HeroControllerScope.none(
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Center(child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          NotificationsScreen(service: notifications),
                    ),
                  ),
                  child: const Text('Open notifications'),
                )),
              ),
            ),
          ),
        ),
        bottomNavigationBar: const SizedBox(
          height: 60,
          child: Center(child: Text('Floating navbar')),
        ),
      ),
    ));

    await tester.tap(find.text('Open notifications'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('Floating navbar'), findsOneWidget);

    await tester.tap(find.text('Review request'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(notifications.read, isTrue);
    expect(find.byType(ApprovalsScreen), findsOneWidget);
    expect(find.text('Floating navbar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
