import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/notifications/data/notification_service.dart';
import 'package:gtex_collab_app/screens/notifications_screen.dart';

class FakeNotificationService extends NotificationService {
  final List<Map<String, dynamic>> data = [
    {
      'id': 'task-1',
      'type': 'TASK_ASSIGNED',
      'title': 'Task from server',
      'body': 'Assigned to you',
      'isRead': false,
      'createdAt': '2026-10-16T10:00:00.000Z',
    },
    {
      'id': 'mention-2',
      'type': 'MENTION',
      'title': 'Mention from server',
      'body': 'Mentioned you',
      'isRead': false,
      'createdAt': '2026-10-16T10:00:00.000Z',
    },
    {
      'id': 'approval-3',
      'type': 'APPROVAL_PENDING',
      'title': 'Approval from server',
      'body': 'Waiting for review',
      'isRead': true,
      'createdAt': '2026-10-16T10:00:00.000Z',
    },
  ];

  @override
  Future<NotificationInbox> getInbox() async => NotificationInbox(
        items: data.map((item) => Map<String, dynamic>.from(item)).toList(),
        unreadCount: data.where((item) => item['isRead'] != true).length,
      );

  @override
  Future<void> connect(void Function() refresh) async {}

  @override
  void disposeSocket() {}

  @override
  Future<void> markRead(String id) async {
    data.firstWhere((item) => item['id'] == id)['isRead'] = true;
  }

  @override
  Future<void> markUnread(String id) async {
    data.firstWhere((item) => item['id'] == id)['isRead'] = false;
  }

  @override
  Future<void> markAllRead() async {
    for (final item in data) {
      item['isRead'] = true;
    }
  }
}

void main() {
  testWidgets('shows server notifications and filters without sample data', (tester) async {
    final service = FakeNotificationService();
    await tester.pumpWidget(
      MaterialApp(home: NotificationsScreen(service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('All (3)'), findsOneWidget);
    expect(find.text('Unread (2)'), findsOneWidget);
    expect(find.text('Task from server'), findsOneWidget);
    expect(find.text('Mention from server'), findsOneWidget);
    expect(find.text('Approval from server'), findsOneWidget);

    await tester.tap(find.text('Unread (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Task from server'), findsOneWidget);
    expect(find.text('Approval from server'), findsNothing);

    await tester.tap(find.text('Mentions'));
    await tester.pumpAndSettle();
    expect(find.text('Mention from server'), findsOneWidget);
    expect(find.text('Task from server'), findsNothing);
  });

  testWidgets('Dashboard Latest Update automatically marks selected item read',
      (tester) async {
    final service = FakeNotificationService();
    await tester.pumpWidget(MaterialApp(
      home: NotificationsScreen(
        service: service,
        openNotificationId: 'task-1',
      ),
    ));
    await tester.pumpAndSettle();
    expect(service.data.first['isRead'], isTrue);
    expect(service.data[1]['isRead'], isFalse);
    expect(find.text('Unread (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read and unread statuses use the service', (tester) async {
    final service = FakeNotificationService();
    await tester.pumpWidget(
      MaterialApp(home: NotificationsScreen(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Task from server'));
    await tester.pumpAndSettle();
    expect(service.data.first['isRead'], true);
    expect(find.text('Unread (1)'), findsOneWidget);

    await tester.longPress(find.text('Task from server'));
    await tester.pumpAndSettle();
    expect(service.data.first['isRead'], false);
    expect(find.text('Unread (2)'), findsOneWidget);

    await tester.tap(find.text('Read All'));
    await tester.pumpAndSettle();
    expect(service.data.every((item) => item['isRead'] == true), true);
    expect(find.text('Unread (0)'), findsOneWidget);
  });
}
