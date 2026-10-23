import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/chat/data/chat_service.dart';
import 'package:gtex_collab_app/screens/chats_screen.dart';

class ConversationCardsStub extends ChatService {
  bool online = true;

  @override
  Future<List<dynamic>> getConversations() async => [
        {
          'id': 'room-a',
          'type': 'DIRECT',
          'name': null,
          // Prod includes unread reactions in unreadCount. The messages
          // badge must show ONLY unreadMessageCount.
          'unreadMessageCount': 2,
          'unreadReactionCount': 3,
          'unreadCount': 5,
          'updatedAt': '2026-10-23T08:00:00Z',
          'members': [
            {
              'userId': 'self',
              'user': {'id': 'self', 'displayName': 'Me'}
            },
            {
              'userId': 'peer',
              'user': {
                'id': 'peer',
                'displayName': 'Online colleague',
                'isOnline': online,
                'lastSeenAt': '2026-10-22T08:00:00Z',
              }
            }
          ],
          'messages': [
            {
              'id': 'last',
              'content': 'Hello there',
              'createdAt': '2026-10-23T08:00:00Z'
            }
          ],
        },
      ];
}

class ReceiptChatStub extends ChatService {
  final List<Map<String, dynamic>> history = [
    {
      'id': 'unread-1',
      'conversationId': 'room-a',
      'content': 'Please review',
      'senderId': 'peer',
      'createdAt': '2026-10-23T08:00:00Z',
      'attachments': <dynamic>[],
      'receipts': [
        {'userId': 'self', 'readAt': null}
      ],
    },
  ];
  int marks = 0;
  Function(dynamic)? socketCallback;

  @override
  Future<List<dynamic>> getMessages(String conversationId) async =>
      history.map((message) => Map<String, dynamic>.from(message)).toList();

  @override
  Future<void> initSocket(Function(dynamic) callback) async {
    socketCallback = callback;
  }

  @override
  void joinConversation(String conversationId) {}

  @override
  void disposeSocket() => socketCallback = null;

  @override
  Future<void> markConversationRead(String conversationId) async {
    expect(conversationId, 'room-a');
    marks++;
    for (final item in history) {
      final receipts = item['receipts'] as List?;
      for (final receipt in receipts ?? []) {
        if (receipt is Map && receipt['userId'] == 'self') {
          receipt['readAt'] = '2026-10-23T08:02:00Z';
        }
      }
    }
  }
}

void main() {
  testWidgets('badge excludes unread reactions and dot uses server presence',
      (tester) async {
    final service = ConversationCardsStub();
    await tester.pumpWidget(MaterialApp(
      home: ChatsScreen(
        service: service,
        loadCurrentUserId: () async => 'self',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('5'), findsNothing);
    expect(find.byKey(const ValueKey('chat-online-room-a')), findsOneWidget);

    service.online = false;
    await tester.pumpWidget(MaterialApp(
      home: ChatsScreen(
        key: const ValueKey('offline-list'),
        service: service,
        loadCurrentUserId: () async => 'self',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-online-room-a')), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('opening a chat acknowledges unread incoming receipts',
      (tester) async {
    final service = ReceiptChatStub();
    await tester.pumpWidget(MaterialApp(
      home: ChatDetailScreen(
        conversationId: 'room-a',
        chatName: 'Direct',
        service: service,
        loadCurrentUserId: () async => 'self',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Please review'), findsOneWidget);
    expect(service.marks, 1);

    // New incoming messages are acknowledged only while the chat is shown.
    service.history.add({
      'id': 'unread-2',
      'conversationId': 'room-a',
      'content': 'Second unread',
      'senderId': 'peer',
      'createdAt': '2026-10-23T08:01:00Z',
      'attachments': <dynamic>[],
      'receipts': [
        {'userId': 'self', 'readAt': null}
      ],
    });
    service.socketCallback?.call(service.history.last);
    await tester.pumpAndSettle();
    expect(find.text('Second unread'), findsOneWidget);
    expect(service.marks, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('own sent message does not create a read acknowledgment',
      (tester) async {
    final service = ReceiptChatStub();
    service.history
      ..clear()
      ..add({
        'id': 'mine',
        'conversationId': 'room-a',
        'content': 'Sent by me',
        'senderId': 'self',
        'createdAt': '2026-10-23T08:00:00Z',
        'attachments': <dynamic>[],
        'receipts': <dynamic>[],
      });
    await tester.pumpWidget(MaterialApp(
      home: ChatDetailScreen(
        conversationId: 'room-a',
        chatName: 'Direct',
        service: service,
        loadCurrentUserId: () async => 'self',
      ),
    ));
    await tester.pumpAndSettle();
    expect(service.marks, 0);
  });
}
