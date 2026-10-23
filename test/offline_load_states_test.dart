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

DioException disconnected(String path) => DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.connectionError,
      message: 'SocketException: private transport detail must stay hidden',
    );

class OfflineInbox extends NotificationService {
  bool online = false;
  int requests = 0;

  @override
  Future<NotificationInbox> getInbox() async {
    requests++;
    if (!online) throw disconnected('/notifications');
    return const NotificationInbox(
      items: [
        {
          'id': 'notice-1',
          'type': 'MENTION',
          'title': 'Server notification',
          'body': 'A new update',
          'isRead': true,
          'createdAt': '2026-10-20T10:00:00Z',
        }
      ],
      unreadCount: 0,
    );
  }

  @override
  Future<void> connect(void Function() refresh) async {}

  @override
  void disposeSocket() {}
}

class DashboardDataStub extends DashboardService {
  @override
  Future<Map<String, dynamic>?> getUserProfile() async =>
      {'firstName': 'Tester'};

  @override
  Future<Map<String, dynamic>> getDashboardMetrics() async =>
      {'activeTasks': '2', 'pendingApprovals': '1'};
}

class OfflineMessages extends ChatService {
  bool online = false;
  int listRequests = 0;
  int messageRequests = 0;

  @override
  Future<List<dynamic>> getConversations() async {
    listRequests++;
    if (!online) throw disconnected('/conversations');
    return [];
  }

  @override
  Future<List<dynamic>> getMessages(String conversationId) async {
    messageRequests++;
    if (!online) throw disconnected('/conversations/$conversationId/messages');
    return [];
  }

  @override
  Future<void> initSocket(Function(dynamic) onMessageReceived) async {}

  @override
  void joinConversation(String conversationId) {}

  @override
  void disposeSocket() {}
}

MaterialApp app(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: child);

void main() {
  test('Dio failures are presented as friendly, safe text', () {
    expect(
      loadErrorDescription(disconnected('/notifications')),
      'შეამოწმეთ ინტერნეტკავშირი და სცადეთ ხელახლა.',
    );
    expect(
      loadErrorDescription(disconnected('/notifications')),
      isNot(contains('SocketException')),
    );
  });

  testWidgets('Notifications offline shows shared card; Retry restores data',
      (tester) async {
    final service = OfflineInbox();
    await tester.pumpWidget(app(NotificationsScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    expect(find.text('ინფორმაციის ჩატვირთვა ვერ მოხერხდა'), findsOneWidget);
    expect(find.text('შეტყობინებები არ მოიძებნა'), findsNothing);
    expect(service.requests, 1);

    service.online = true;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pumpAndSettle();

    expect(service.requests, 2);
    expect(find.text('Server notification'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Latest Updates card handles Dio offline and successful Retry',
      (tester) async {
    final service = OfflineInbox();
    await tester.pumpWidget(app(DashboardScreen(
      onToggleTheme: () {},
      onChangeLanguage: () {},
      currentLanguage: 'ka',
      currentThemeMode: ThemeMode.light,
      dashboardService: DashboardDataStub(),
      notificationService: service,
    )));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dashboard-latest-updates')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    expect(find.text('Server notification'), findsNothing);

    service.online = true;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pumpAndSettle();

    expect(find.text('Server notification'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Messages list shows offline error, then correct empty state',
      (tester) async {
    final service = OfflineMessages();
    await tester.pumpWidget(app(ChatsScreen(
      service: service,
      loadCurrentUserId: () async => 'user-1',
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    expect(find.text('No conversations yet'), findsNothing);

    service.online = true;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pumpAndSettle();

    expect(service.listRequests, 2);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat messages load error and Retry without leaving the chat',
      (tester) async {
    final service = OfflineMessages();
    await tester.pumpWidget(app(ChatDetailScreen(
      conversationId: 'chat-1',
      chatName: 'Team',
      service: service,
      loadCurrentUserId: () async => 'user-1',
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    service.online = true;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pumpAndSettle();

    expect(service.messageRequests, 2);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsNothing);
    expect(find.text('დაიწყეთ საუბარი...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
