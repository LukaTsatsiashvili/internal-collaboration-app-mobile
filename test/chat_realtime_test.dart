import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/chat/data/chat_service.dart';
import 'package:gtex_collab_app/screens/chats_screen.dart';

class LiveChatStub extends ChatService {
  dynamic Function(dynamic)? onEvent;
  final List<Map<String, dynamic>> history = [
    {
      'id': 'old',
      'conversationId': 'room-1',
      'content': 'Earlier',
      'senderId': 'user-a',
      'createdAt': '2026-10-23T07:00:00.000Z',
      'attachments': <dynamic>[],
    },
  ];
  int historyLoads = 0;
  String? joined;

  @override
  Future<List<dynamic>> getMessages(String conversationId) async {
    historyLoads++;
    return history.map((message) => Map<String, dynamic>.from(message)).toList();
  }

  @override
  Future<void> initSocket(Function(dynamic) callback) async {
    onEvent = callback;
  }

  @override
  void joinConversation(String conversationId) {
    joined = conversationId;
  }

  @override
  void disposeSocket() {
    onEvent = null;
  }

  void emit(Map<String, dynamic> data) => onEvent?.call(data);
}

void main() {
  testWidgets('incoming chat messages arrive without a manual refresh', (tester) async {
    final service = LiveChatStub();
    await tester.pumpWidget(MaterialApp(
      home: ChatDetailScreen(
        conversationId: 'room-1',
        chatName: 'My chat',
        service: service,
        loadCurrentUserId: () async => 'user-me',
      ),
    ));
    await tester.pumpAndSettle();
    expect(service.joined, 'room-1');
    expect(find.text('Earlier'), findsOneWidget);

    service.emit({
      'id': 'new',
      'conversationId': 'room-1',
      'content': 'Just received',
      'senderId': 'user-a',
      'createdAt': '2026-10-23T07:01:00.000Z',
      'attachments': <dynamic>[],
    });
    await tester.pump();
    expect(find.text('Just received'), findsOneWidget);
    expect(service.historyLoads, 1);

    // A duplicate delivery updates, not appends, the same message.
    service.emit({
      'id': 'new',
      'conversationId': 'room-1',
      'content': 'Edited live',
    });
    await tester.pump();
    expect(find.text('Just received'), findsNothing);
    expect(find.text('Edited live'), findsOneWidget);

    service.emit({
      'id': 'elsewhere',
      'conversationId': 'room-2',
      'content': 'Not this room',
    });
    await tester.pump();
    expect(find.text('Not this room'), findsNothing);

    service.emit({
      'id': 'new',
      'conversationId': 'room-1',
      '__realtimeDeleted': true,
    });
    await tester.pump();
    expect(find.text('Edited live'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconnecting recovers messages missed while offline', (tester) async {
    final service = LiveChatStub();
    await tester.pumpWidget(MaterialApp(
      home: ChatDetailScreen(
        conversationId: 'room-1',
        chatName: 'My chat',
        service: service,
        loadCurrentUserId: () async => 'user-me',
      ),
    ));
    await tester.pumpAndSettle();
    service.history.add({
      'id': 'missed',
      'conversationId': 'room-1',
      'content': 'Missed during outage',
      'senderId': 'user-a',
      'createdAt': '2026-10-23T07:02:00.000Z',
      'attachments': <dynamic>[],
    });
    service.emit({'__realtimeRefresh': true});
    await tester.pumpAndSettle();

    expect(service.historyLoads, 2);
    expect(find.text('Missed during outage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
