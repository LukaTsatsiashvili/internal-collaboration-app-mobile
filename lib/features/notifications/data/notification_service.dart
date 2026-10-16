import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../../../core/network/api_client.dart';

class NotificationInbox {
  const NotificationInbox({required this.items, required this.unreadCount});
  final List<Map<String, dynamic>> items;
  final int unreadCount;
}

/// Uses the existing authenticated API and user-scoped realtime events.
class NotificationService {
  final ApiClient _api = ApiClient();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  IO.Socket? _socket;

  Future<NotificationInbox> getInbox() async {
    final response = await _api.dio.get('/notifications');
    final payload = response.data;
    if (payload is! Map || payload['success'] != true || payload['data'] is! List) {
      throw StateError('შეტყობინებების ჩატვირთვა ვერ მოხერხდა');
    }
    final items = (payload['data'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final meta = payload['meta'];
    final count = meta is Map && meta['unreadCount'] is num
        ? (meta['unreadCount'] as num).toInt()
        : items.where((item) => item['isRead'] != true).length;
    return NotificationInbox(items: items, unreadCount: count);
  }

  Future<void> markRead(String id) async {
    await _api.dio.post('/notifications/${Uri.encodeComponent(id)}/read');
  }

  Future<void> markUnread(String id) async {
    await _api.dio.post('/notifications/${Uri.encodeComponent(id)}/unread');
  }

  Future<void> markAllRead() async {
    await _api.dio.post('/notifications/read-all');
  }

  /// Socket events are invalidation hints; the REST API is the source of truth.
  Future<void> connect(void Function() refresh) async {
    disposeSocket();
    final token = await _storage.read(key: 'access_token');
    if (token == null || token.isEmpty) return;
    final socket = IO.io(Uri.parse(ApiClient.baseUrl).origin, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
      'reconnection': true,
      'auth': {'token': token},
    });
    _socket = socket;
    socket.on('notification:created', (_) => refresh());
    socket.on('notification:updated', (_) => refresh());
    socket.on('connect', (_) => refresh());
    socket.connect();
  }

  void disposeSocket() {
    final socket = _socket;
    _socket = null;
    socket?.disconnect();
    socket?.dispose();
  }
}
