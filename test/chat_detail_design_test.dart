import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_colors.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/core/theme/app_theme_extensions.dart';
import 'package:gtex_collab_app/features/chat/data/chat_service.dart';
import 'package:gtex_collab_app/screens/chats_screen.dart';

class DesignChatService extends ChatService {
  final sent = <String>[];

  @override
  Future<List<dynamic>> getMessages(String id) async => [
        {
          'id': 'incoming',
          'conversationId': id,
          'content': 'A message from colleague',
          'senderId': 'colleague',
          'sender': {'id': 'colleague', 'displayName': 'System Administrator'},
          'createdAt': '2026-10-23T07:00:00Z',
          'attachments': <dynamic>[],
        },
        {
          'id': 'outgoing',
          'conversationId': id,
          'content': 'My reply',
          'senderId': 'me',
          'sender': {'id': 'me', 'displayName': 'Me'},
          'createdAt': '2026-10-23T07:01:00Z',
          'attachments': <dynamic>[],
        },
      ];

  @override
  Future<void> initSocket(Function(dynamic) onMessageReceived) async {}

  @override
  void joinConversation(String id) {}

  @override
  void disposeSocket() {}

  @override
  Future<void> sendMessageHttp(
    String conversationId,
    String text, {
    String? replyToMessageId,
    List<String>? attachmentIds,
  }) async {
    sent.add(text);
  }
}

Future<void> showChat(
  WidgetTester tester,
  ThemeData theme,
  DesignChatService service, {
  bool isGroup = false,
  bool isOnline = true,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: ChatDetailScreen(
      conversationId: 'room',
      chatName: 'System Administrator',
      isOnline: isOnline,
      isGroup: isGroup,
      service: service,
      loadCurrentUserId: () async => 'me',
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final mode in [Brightness.light, Brightness.dark]) {
    testWidgets('chat redesign preserves actions and palette in $mode',
        (tester) async {
      final service = DesignChatService();
      final palette =
          mode == Brightness.light ? AppPalette.light : AppPalette.dark;
      await showChat(
        tester, mode == Brightness.light ? AppTheme.light : AppTheme.dark,
        service,
      );

      expect(find.byKey(const ValueKey('chat-detail-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-detail-back')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-detail-contact-name')),
          findsOneWidget);
      expect(find.text('Active now'), findsNothing);
      expect(find.text('Offline'), findsNothing);
      expect(find.byKey(const ValueKey('chat-detail-online-dot')),
          findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byKey(const ValueKey('chat-detail-attach')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-detail-send')), findsOneWidget);

      // The divider belongs below the input, next to the shell navigation.
      final composer = tester.widget<Container>(
          find.byKey(const ValueKey('chat-detail-composer-area')));
      final composerDecoration = composer.decoration! as BoxDecoration;
      final composerBorder = composerDecoration.border! as Border;
      expect(composerBorder.top, BorderSide.none);
      expect(composerBorder.bottom.color, palette.cardBorder);

      // There must be no separate panel fill behind the input: the
      // message list and composer share this one uninterrupted canvas.
      expect(composerDecoration.color, isNull);
      expect(composerDecoration.gradient, isNull);
      final canvas = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('chat-detail-canvas')));
      final background = (canvas.decoration as BoxDecoration).gradient!
          as LinearGradient;
      expect(background.colors, [
        palette.page,
        palette.unreadBackground.withValues(alpha: 0.65),
        palette.page,
      ]);

      final incoming = tester.widget<Container>(
          find.byKey(const ValueKey('chat-bubble-incoming')));
      final outgoing = tester.widget<Container>(
          find.byKey(const ValueKey('chat-bubble-outgoing')));
      final incomingDecoration = incoming.decoration! as BoxDecoration;
      final outgoingDecoration = outgoing.decoration! as BoxDecoration;
      expect(incomingDecoration.color, palette.card);
      expect(outgoingDecoration.gradient, isA<LinearGradient>());
      expect((outgoingDecoration.gradient! as LinearGradient).colors,
          [AppColors.gradientStart, AppColors.gradientEnd]);

      await tester.enterText(
          find.byKey(const ValueKey('chat-detail-message-input')),
          'UI retains send behavior');
      await tester.tap(find.byKey(const ValueKey('chat-detail-send')));
      await tester.pump();
      expect(service.sent, ['UI retains send behavior']);

      await tester.longPress(find.text('A message from colleague'));
      await tester.pumpAndSettle();
      expect(find.text('პასუხის გაცემა (Reply)'), findsOneWidget);
      await tester.tap(find.text('პასუხის გაცემა (Reply)'));
      await tester.pumpAndSettle();
      expect(find.text('პასუხი: System Administrator'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow phone keeps composer and actions within screen',
      (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await showChat(tester, AppTheme.light, DesignChatService());
    expect(find.byKey(const ValueKey('chat-detail-composer-area')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat-detail-send')), findsOneWidget);
    await tester.longPress(find.text('A message from colleague'));
    await tester.pumpAndSettle();
    expect(find.text('პასუხის გაცემა (Reply)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline peer keeps a clean single-line header', (tester) async {
    await showChat(
      tester, AppTheme.dark, DesignChatService(), isOnline: false,
    );
    expect(find.byKey(const ValueKey('chat-detail-contact-name')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat-detail-online-dot')), findsNothing);
    expect(find.text('Active now'), findsNothing);
    expect(find.text('Offline'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group header uses the group label instead of person status',
      (tester) async {
    await showChat(tester, AppTheme.light, DesignChatService(), isGroup: true);
    expect(find.text('ჯგუფური საუბარი'), findsOneWidget);
    expect(find.text('Active now'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
