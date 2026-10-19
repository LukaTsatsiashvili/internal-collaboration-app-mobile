import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/dashboard/data/dashboard_service.dart';
import 'package:gtex_collab_app/features/notifications/data/notification_service.dart';
import 'package:gtex_collab_app/screens/dashboard_screen.dart';

class FakeDashboardData extends DashboardService {
  @override
  Future<Map<String, dynamic>?> getUserProfile() async => {
    'firstName': 'Alex',
  };

  @override
  Future<Map<String, dynamic>> getDashboardMetrics() async => {
    'activeTasks': '3', 'pendingApprovals': '2',
  };
}

class FakeUpdates extends NotificationService {
  FakeUpdates(this.items);
  final List<Map<String, dynamic>> items;
  VoidCallback? refresh;
  int reads = 0;

  @override
  Future<NotificationInbox> getInbox() async => NotificationInbox(
    items: items.map((item) => Map<String, dynamic>.from(item)).toList(),
    unreadCount: items.where((item) => item['isRead'] != true).length,
  );

  @override
  Future<void> connect(void Function() callback) async {
    refresh = callback;
  }

  @override
  void disposeSocket() {}

  void showRead(String id) {
    for (final item in items) {
      if (item['id'] == id) item['isRead'] = true;
    }
    reads++;
    refresh?.call();
  }
}

Map<String, dynamic> update(String id, {bool read = false}) => {
  'id': id,
  'type': 'APPROVAL_REVIEW_NEEDED',
  'title': 'A request needs your review',
  'body': 'Purchase laptop',
  'createdAt': '2026-10-19T10:00:00.000Z',
  'isRead': read,
  'targetUrl': '/approvals?request=request-1',
};

Future<void> showDashboard(WidgetTester tester, FakeUpdates service,
    List<DashboardQuickAction> actions) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: DashboardScreen(
      onToggleTheme: () {},
      onChangeLanguage: () {},
      currentLanguage: 'ka',
      currentThemeMode: ThemeMode.light,
      dashboardService: FakeDashboardData(),
      notificationService: service,
      onQuickAction: actions.add,
    ),
  ));
  // An unread pulse is intentionally repeating; never pumpAndSettle here.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 70));
}

void main() {
  testWidgets('three quick actions reuse their exact destination intents',
      (tester) async {
    final actions = <DashboardQuickAction>[];
    await showDashboard(tester, FakeUpdates([]), actions);

    expect(find.text('ჯგუფის შექმნა'), findsNothing);
    await tester.tap(find.text('ახალი დავალება'));
    await tester.tap(find.text('მოთხოვნის შექმნა'));
    await tester.tap(find.text('საუბრის დაწყება'));
    expect(actions, [
      DashboardQuickAction.task,
      DashboardQuickAction.request,
      DashboardQuickAction.conversation,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metric cards open Tasks and Approvals without quick-create',
      (tester) async {
    final openedTabs = <int>[];
    final quickActions = <DashboardQuickAction>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DashboardScreen(
        onToggleTheme: () {},
        onChangeLanguage: () {},
        currentLanguage: 'ka',
        currentThemeMode: ThemeMode.light,
        dashboardService: FakeDashboardData(),
        notificationService: FakeUpdates([]),
        onNavigateToModule: openedTabs.add,
        onQuickAction: quickActions.add,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final taskCard = find.byKey(
      const ValueKey('dashboard-active-tasks-card'),
    );
    final approvalCard = find.byKey(
      const ValueKey('dashboard-pending-approvals-card'),
    );
    expect(taskCard, findsOneWidget);
    expect(approvalCard, findsOneWidget);
    expect(tester.widget<InkWell>(taskCard).onTap, isNotNull);
    expect(tester.widget<InkWell>(approvalCard).onTap, isNotNull);

    await tester.tap(taskCard);
    await tester.tap(approvalCard);
    expect(openedTabs, [2, 3]);
    expect(quickActions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard displays only newest four backend updates',
      (tester) async {
    final updates = FakeUpdates([
      update('1', read: true),
      update('2', read: true),
      update('3', read: true),
      update('4', read: true),
      update('5', read: true),
    ]);
    await showDashboard(tester, updates, []);
    await tester.drag(find.byType(ListView).first,
        const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboard-latest-updates')),
      findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-update-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-update-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-update-5')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-read-dot')),
      findsNWidgets(4));
    expect(find.byKey(const ValueKey('dashboard-unread-dot')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-open-inbox')),
      findsOneWidget);
  });

  testWidgets('unread dot pulses, then becomes static after read event',
      (tester) async {
    final updates = FakeUpdates([update('1')]);
    await showDashboard(tester, updates, []);
    await tester.drag(find.byType(ListView).first,
        const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('dashboard-unread-dot')),
        findsOneWidget);
    updates.showRead('1');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboard-unread-dot')),
        findsNothing);
    expect(find.byKey(const ValueKey('dashboard-read-dot')), findsOneWidget);
    expect(updates.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty updates state shows the web-aligned message',
      (tester) async {
    await showDashboard(tester, FakeUpdates([]), []);
    await tester.drag(find.byType(ListView).first,
        const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text("You're all caught up."), findsOneWidget);
  });
}
