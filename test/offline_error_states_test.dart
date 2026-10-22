import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/core/widgets/load_error_state.dart';
import 'package:gtex_collab_app/features/chat/data/chat_service.dart';
import 'package:gtex_collab_app/features/dashboard/data/dashboard_service.dart';
import 'package:gtex_collab_app/features/notifications/data/notification_service.dart';
import 'package:gtex_collab_app/screens/chats_screen.dart';
import 'package:gtex_collab_app/screens/dashboard_screen.dart';
import 'package:gtex_collab_app/screens/notifications_screen.dart';

DioException offline() => DioException(
  requestOptions: RequestOptions(path: '/notifications'),
  type: DioExceptionType.connectionError,
  message: 'Sensitive network address must not appear in the UI',
);

class OfflineInbox extends NotificationService {
  bool connected = false;
  int calls = 0;
  List<Map<String, dynamic>> items = [];
  void Function()? onRefresh;

  @override
  Future<NotificationInbox> getInbox() async {
    calls++;
    if (!connected) throw offline();
    return NotificationInbox(
      items: items,
      unreadCount: items.where((i) => i['isRead'] != true).length,
    );
  }

  @override
  Future<void> connect(void Function() refresh) async {
    onRefresh = refresh;
  }

  @override
  void disposeSocket() {
    onRefresh = null;
  }
}

class OfflineDashboard extends DashboardService {
  @override
  Future<Map<String, dynamic>?> getUserProfile() async => {'name': 'User'};

  @override
  Future<Map<String, dynamic>> getDashboardMetrics() async =>
      {'activeTasks': '0', 'pendingApprovals': '0'};
}

class OfflineMetrics extends DashboardService {
  bool connected = false;

  @override
  Future<Map<String, dynamic>?> getUserProfile() async => {'name': 'User'};

  @override
  Future<Map<String, dynamic>> getDashboardMetrics() async {
    if (!connected) throw offline();
    return {'activeTasks': '4', 'pendingApprovals': '2'};
  }
}

class OfflineChats extends ChatService {
  bool connected = false;
  int calls = 0;

  @override
  Future<List<dynamic>> getConversations() async {
    calls++;
    if (!connected) throw offline();
    return [];
  }

  @override
  Future<List<dynamic>> getMessages(String conversationId) async {
    calls++;
    if (!connected) throw offline();
    return [];
  }

  @override
  Future<List<dynamic>> getUsers() async {
    calls++;
    if (!connected) throw offline();
    return [];
  }

  @override
  Future<void> initSocket(Function(dynamic) onMessageReceived) async {}

  @override
  void joinConversation(String conversationId) {}

  @override
  void disposeSocket() {}
}

void main() {
  test('network failure displays a localized safe description', () {
    final description = loadErrorDescription(offline());
    expect(description, contains('ინტერნეტკავშირი'));
    expect(description, isNot(contains('Sensitive network address')));
    expect(
      loadErrorDescription(StateError('internal details')),
      isNot(contains('internal details')),
    );
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('error component supports light and dark themes', (tester) async {
      var retried = false;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AppLoadErrorState(onRetry: () => retried = true),
        ),
      ));
      expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
      expect(retried, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Notifications offline error switches to true empty state on Retry',
      (tester) async {
    final inbox = OfflineInbox();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: NotificationsScreen(service: inbox),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    expect(find.text('შეტყობინებები არ მოიძებნა'), findsNothing);

    inbox.connected = true;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(inbox.calls, greaterThanOrEqualTo(2));
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(find.text('შეტყობინებები არ მოიძებნა'), findsOneWidget);
  });

  testWidgets('Notifications preserves cached records after a refresh fails',
      (tester) async {
    final inbox = OfflineInbox()
      ..connected = true
      ..items = [
        {
          'id': 'saved-1',
          'type': 'MENTION',
          'title': 'Previously loaded mention',
          'body': 'Already received',
          'createdAt': '2026-10-21T10:00:00Z',
          'isRead': false,
        },
      ];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: NotificationsScreen(service: inbox),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Previously loaded mention'), findsOneWidget);

    inbox.connected = false;
    inbox.onRefresh?.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Previously loaded mention'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-load-error-notice')), findsOneWidget);

    inbox.connected = true;
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('app-load-error-notice')),
      matching: find.text('ხელახლა ცდა'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Previously loaded mention'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-load-error-notice')), findsNothing);
  });

  testWidgets('Dashboard metrics show offline Error rather than zero',
      (tester) async {
    final metrics = OfflineMetrics();
    final inbox = OfflineInbox()..connected = true;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DashboardScreen(
        onToggleTheme: () {},
        onChangeLanguage: () {},
        currentLanguage: 'ka',
        currentThemeMode: ThemeMode.light,
        dashboardService: metrics,
        notificationService: inbox,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('dashboard-active-tasks-card')), findsNothing);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);

    metrics.connected = true;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-active-tasks-card')), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('Latest Updates shows a compact offline Retry card',
      (tester) async {
    final inbox = OfflineInbox();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DashboardScreen(
        onToggleTheme: () {},
        onChangeLanguage: () {},
        currentLanguage: 'ka',
        currentThemeMode: ThemeMode.light,
        dashboardService: OfflineDashboard(),
        notificationService: inbox,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('dashboard-latest-updates')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    inbox.connected = true;
    // Latest Updates is below the dashboard metric cards; scroll it into
    // the test viewport before performing a real hit-tested tap.
    final retry = find.byKey(const ValueKey('app-load-error-retry'));
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(find.text("You're all caught up."), findsOneWidget);
  });

  testWidgets('Messages list shows Retry and does not mistake offline for empty',
      (tester) async {
    final chats = OfflineChats();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: ChatsScreen(
        service: chats,
        loadCurrentUserId: () async => 'user-1',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    expect(find.text('No conversations yet'), findsNothing);
    chats.connected = true;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(chats.calls, 2);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('New conversation distinguishes unavailable colleagues from no results',
      (tester) async {
    final chats = OfflineChats();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => NewConversationDialog(service: chats),
          ),
          child: const Text('Open dialogue'),
        )),
      ),
    ));
    await tester.tap(find.text('Open dialogue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    expect(find.text('No colleagues found'), findsNothing);
    chats.connected = true;
    final retry = find.byKey(const ValueKey('app-load-error-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(find.text('No colleagues found'), findsOneWidget);
  });

  testWidgets('Message detail shows Retry instead of pretending chat is empty',
      (tester) async {
    final chats = OfflineChats();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: ChatDetailScreen(
        conversationId: 'conversation-1',
        chatName: 'Chat',
        service: chats,
        loadCurrentUserId: () async => 'user-1',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    expect(find.text('დაიწყეთ საუბარი...'), findsNothing);
    chats.connected = true;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(chats.calls, 2);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(find.text('დაიწყეთ საუბარი...'), findsOneWidget);
  });
}
