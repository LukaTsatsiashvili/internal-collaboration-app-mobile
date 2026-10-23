import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/realtime_client.dart';

class ChatService {
  final ApiClient _apiClient = ApiClient();
  final List<void Function()> _socketSubscriptions = [];
  void Function()? _leaveConversation;

  Future<void> addReaction(String messageId, String emoji) async {
    try {
      await _apiClient.dio.post(
        '/messages/$messageId/reactions',
        data: {'emoji': emoji},
      );
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ?? 'რეაქციის შენახვა ვერ მოხერხდა',
      );
    }
  }

  Future<List<dynamic>> getUsers() async {
    try {
      final response = await _apiClient.dio.get('/users');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ??
            'თანამშრომლების ჩატვირთვა ვერ მოხერხდა',
      );
    }
    return [];
  }

  Future<Map<String, dynamic>?> createConversation({
    required bool isGroup,
    String? title,
    required List<String> memberIds,
  }) async {
    try {
      final conversationType = isGroup ? 'GROUP' : 'DIRECT';

      final payload = {
        'type': conversationType,
        if (title != null && title.isNotEmpty) 'name': title,
        'memberIds': memberIds,
      };

      final response = await _apiClient.dio.post(
        '/conversations',
        data: payload,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (response.data['success'] == true) {
          return response.data['data'];
        }
      }
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ?? 'საუბრის შექმნა ვერ მოხერხდა',
      );
    } catch (e) {
      throw Exception('საუბრის შექმნა ვერ მოხერხდა: $e');
    }
    return null;
  }

  Future<List<dynamic>> getConversations() async {
    try {
      final response = await _apiClient.dio.get('/conversations');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
    } on DioException {
      rethrow;
    }
    throw StateError('ჩათების მონაცემები არასწორი ფორმატით დაბრუნდა');
  }

  /// Persist the read state on prod (including the message receipt rows).
  /// Merely opening the chat must not clear a badge only on this device.
  Future<void> markConversationRead(String conversationId) async {
    await _apiClient.dio.post(
      '/conversations/${Uri.encodeComponent(conversationId)}/read',
      data: const <String, dynamic>{'all': true},
    );
  }

  Future<List<dynamic>> getMessages(String conversationId) async {
    try {
      final response = await _apiClient.dio.get(
        '/conversations/$conversationId/messages',
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as List<dynamic>;
      }
    } on DioException {
      rethrow;
    }
    throw StateError('შეტყობინებები არასწორი ფორმატით დაბრუნდა');
  }

  // 🔹 ფაილის ატვირთვა სერვერზე (/files ენდპოინტზე)
  Future<String?> uploadFile(String filePath, String fileName) async {
    try {
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _apiClient.dio.post('/files', data: formData);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.data['success'] == true) {
          return response
              .data['data']['id']; // აბრუნებს ფაილის უნიკალურ UUID-ს[cite: 4]
        }
      }
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ?? 'ფაილის ატვირთვა ვერ მოხერხდა',
      );
    }
    return null;
  }

  // 🔹 შეტყობინების გაგზავნა (attachmentIds მხარდაჭერით)[cite: 4, 7]
  Future<void> sendMessageHttp(
    String conversationId,
    String content, {
    String? replyToMessageId,
    List<String>? attachmentIds,
  }) async {
    try {
      final data = <String, dynamic>{
        'content': content,
        'replyToMessageId': ?replyToMessageId,
        if (attachmentIds != null && attachmentIds.isNotEmpty)
          'attachmentIds': attachmentIds,
      };

      await _apiClient.dio.post(
        '/conversations/$conversationId/messages',
        data: data,
      );
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ?? 'შეტყობინება ვერ გაიგზავნა',
      );
    }
  }

  /// Listen to the production room events. The shared connection survives
  /// other screens subscribing and reconnects when the access token rotates.
  Future<void> initSocket(Function(dynamic) onMessageReceived) async {
    if (_socketSubscriptions.isNotEmpty) return;
    final realtime = RealtimeClient.instance;
    _socketSubscriptions.addAll([
      realtime.listen('message:created', onMessageReceived),
      realtime.listen('message:updated', onMessageReceived),
      realtime.listen('message:deleted', (data) {
        if (data is Map) {
          onMessageReceived({...data, '__realtimeDeleted': true});
        }
      }),
      for (final event in [
        'message:reaction-updated',
        'message:pin-updated',
        'message:receipt-updated',
        'conversation:read-updated',
      ])
        realtime.listen(event, (data) {
          if (data is Map) {
            onMessageReceived({...data, '__realtimeRefresh': true});
          }
        }),
      realtime.listen('connect', (_) =>
          onMessageReceived({'__realtimeRefresh': true})),
    ]);
  }

  /// A new conversation might not have been in the server's initial rooms.
  /// Room joins must also be replayed after a reconnect.
  void joinConversation(String conversationId) {
    _leaveConversation?.call();
    _leaveConversation = RealtimeClient.instance.joinConversation(conversationId);
  }

  /// The list view does not receive message events through REST; refresh the
  /// server-ordered list when the room's messages or membership change.
  void watchConversations(void Function() onChanged) {
    if (_socketSubscriptions.isNotEmpty) return;
    final realtime = RealtimeClient.instance;
    for (final event in [
      'connect',
      'message:created',
      'message:updated',
      'message:deleted',
      'conversation:updated',
      'conversation:removed',
      'conversation:read-updated',
      'message:receipt-updated',
      'presence:updated',
    ]) {
      _socketSubscriptions.add(realtime.listen(event, (_) => onChanged()));
    }
  }

  Future<void> editMessage(String messageId, String content) async {
    try {
      await _apiClient.dio.patch(
        '/messages/$messageId',
        data: {'content': content},
      ); // PATCH მეთოდი რედაქტირებისთვის[cite: 4, 7]
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ??
            'შეტყობინების რედაქტირება ვერ მოხერხდა',
      );
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _apiClient.dio.delete(
        '/messages/$messageId',
        data: {}, // ცარიელი სხეული application/json მოთხოვნის დასაკმაყოფილებლად
      );
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error']['message'] ??
            'შეტყობინების წაშლა ვერ მოხერხდა',
      );
    }
  }

  void disposeSocket() {
    _leaveConversation?.call();
    _leaveConversation = null;
    for (final cancel in _socketSubscriptions) {
      cancel();
    }
    _socketSubscriptions.clear();
  }
}
