import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../../../core/network/api_client.dart';

class ChatService {
  final ApiClient _apiClient = ApiClient();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static IO.Socket? _socket;

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

  Future<void> initSocket(Function(dynamic) onMessageReceived) async {
    if (_socket != null && _socket!.connected) return;

    String? token = await _secureStorage.read(key: 'access_token');

    _socket = IO.io(Uri.parse(ApiClient.baseUrl).origin, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'auth': {'token': token},
    });

    _socket?.on('message:created', (data) => onMessageReceived(data));
    _socket?.on('message:updated', (data) => onMessageReceived(data));
    _socket?.on('message:deleted', (data) => onMessageReceived(data));
  }

  void joinConversation(String conversationId) {
    if (_socket != null && _socket!.connected) {
      _socket?.emit('conversation:join', conversationId);
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
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
