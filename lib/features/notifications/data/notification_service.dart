import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/realtime_client.dart';

class NotificationInbox {
  const NotificationInbox({required this.items, required this.unreadCount});
  final List<Map<String, dynamic>> items;
  final int unreadCount;
}

/// Uses the existing authenticated API and user-scoped realtime events.
class NotificationService {
  NotificationService({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;
  final List<void Function()> _cancelRealtime = [];

  Future<NotificationInbox> getInbox() async {
    final response = await _dio.get('/notifications');
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
    await _dio.post('/notifications/${Uri.encodeComponent(id)}/read',
        data: const <String, dynamic>{});
  }

  Future<void> markUnread(String id) async {
    await _dio.post('/notifications/${Uri.encodeComponent(id)}/unread',
        data: const <String, dynamic>{});
  }

  Future<void> markAllRead() async {
    await _dio.post('/notifications/read-all',
        data: const <String, dynamic>{});
  }

  /// Production notification events invalidate the REST inbox. Multiple
  /// screens can subscribe without disconnecting one another.
  Future<void> connect(void Function() refresh) async {
    disposeSocket();
    final realtime = RealtimeClient.instance;
    for (final event in [
      'notification:created',
      'notification:updated',
      'connect',
    ]) {
      _cancelRealtime.add(realtime.listen(event, (_) => refresh()));
    }
  }

  void disposeSocket() {
    for (final cancel in _cancelRealtime) {
      cancel();
    }
    _cancelRealtime.clear();
  }

}
