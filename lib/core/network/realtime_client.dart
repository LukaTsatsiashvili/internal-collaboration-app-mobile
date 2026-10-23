import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'api_client.dart';
import 'auth_session.dart';

/// One authenticated Socket.IO connection shared by every visible module.
///
/// Events are invalidation hints: modules still fetch authoritative records
/// from the production REST API after reconnecting or when needed.
class RealtimeClient with WidgetsBindingObserver {
  RealtimeClient._();

  static final RealtimeClient instance = RealtimeClient._();

  final Map<int, ({String event, void Function(dynamic) callback})> _listeners = {};
  final Map<String, int> _conversationRooms = {};
  final Set<String> _wiredEvents = {};
  int _nextId = 0;
  int _epoch = 0;
  IO.Socket? _socket;
  String? _socketToken;
  Future<void>? _pendingSync;
  bool _recoveringAuth = false;
  bool _foreground = true;
  Timer? _checkTimer;
  Timer? _heartbeatTimer;
  int _checkCount = 0;

  void Function() listen(String event, void Function(dynamic) callback) {
    final first = _listeners.isEmpty;
    final id = ++_nextId;
    _listeners[id] = (event: event, callback: callback);
    if (first) {
      WidgetsBinding.instance.addObserver(this);
      _checkCount = 0;
      _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_foreground) return;
        unawaited(_sync());
        // The prod deadline worker writes notifications directly to the DB
        // and does not emit Socket.IO events. Reconcile them once per minute.
        if ((++_checkCount).isEven) _dispatch('notification:reconcile', null);
      });
    }
    if (event != 'connect' && event != 'notification:reconcile') {
      _wireEvent(event);
    }
    unawaited(_sync());
    return () {
      _listeners.remove(id);
      if (_listeners.isEmpty) {
        ++_epoch;
        _checkTimer?.cancel();
        _checkTimer = null;
        WidgetsBinding.instance.removeObserver(this);
        _conversationRooms.clear();
        _closeSocket();
      }
    };
  }

  void Function() joinConversation(String id) {
    _conversationRooms.update(id, (count) => count + 1, ifAbsent: () => 1);
    if (_socket?.connected == true) _socket!.emit('conversation:join', id);
    return () {
      final count = _conversationRooms[id];
      if (count == null) return;
      if (count <= 1) {
        _conversationRooms.remove(id);
      } else {
        _conversationRooms[id] = count - 1;
      }
    };
  }

  void _dispatch(String event, dynamic value) {
    for (final listener in List.of(_listeners.values)) {
      if (listener.event == event) listener.callback(value);
    }
  }

  void _wireEvent(String event) {
    final socket = _socket;
    if (socket == null || !_wiredEvents.add(event)) return;
    socket.on(event, (dynamic value) => _dispatch(event, value));
  }

  bool _expiresSoon(String token) {
    try {
      final pieces = token.split('.');
      if (pieces.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(pieces[1]))),
      );
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return false;
      return exp.toInt() * 1000 <=
          DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sync() {
    if (_pendingSync != null) return _pendingSync!;
    final pending = _performSync();
    _pendingSync = pending;
    pending.whenComplete(() {
      if (identical(_pendingSync, pending)) _pendingSync = null;
    });
    return pending;
  }

  Future<void> _performSync() async {
    final epoch = _epoch;
    if (!_foreground || _listeners.isEmpty) return;
    try {
      var token = await AuthSession.instance.getAccessToken();
      if (token == null || token.isEmpty) return;
      if (_expiresSoon(token)) {
        final result = await ApiClient().refreshSession();
        if (result != AuthRefreshResult.refreshed) return;
        token = await AuthSession.instance.getAccessToken();
      }
      if (epoch != _epoch || !_foreground || _listeners.isEmpty ||
          token == null || token.isEmpty) return;

      if (_socket != null && _socketToken == token) {
        if (_socket!.disconnected) _socket!.connect();
        return;
      }
      _closeSocket();
      _socketToken = token;
      final socket = IO.io(
        Uri.parse(ApiClient.baseUrl).origin,
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': false,
          'forceNew': true,
          'reconnection': true,
          'auth': {'token': token},
        },
      );
      _socket = socket;
      socket.onConnect((_) {
        _heartbeatTimer?.cancel();
        // The production Presence key expires after 90 seconds without a
        // heartbeat. A stable WebSocket alone does not refresh that TTL.
        socket.emit('presence:heartbeat');
        _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (identical(_socket, socket) && socket.connected) {
            socket.emit('presence:heartbeat');
          }
        });
        for (final room in _conversationRooms.keys) {
          socket.emit('conversation:join', room);
        }
        _dispatch('connect', null);
      });
      socket.onConnectError((dynamic error) {
        // A server-side authorization rejection is not a transport outage.
        if (error.toString().toLowerCase().contains('unauthorized')) {
          unawaited(_recoverAuthentication(socket));
        }
      });
      socket.onDisconnect((dynamic reason) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        // The prod server explicitly closes sockets at JWT expiry.
        if (reason == 'io server disconnect') {
          unawaited(_recoverAuthentication(socket));
        }
      });
      for (final event in _listeners.values.map((item) => item.event).toSet()) {
        if (event != 'connect' && event != 'notification:reconcile') {
          _wireEvent(event);
        }
      }
      socket.connect();
    } catch (_) {
      // Keep REST working during an outage or when secure storage is locked.
      // The periodic check and app-resume callback will reconnect later.
    }
  }

  Future<void> _recoverAuthentication(IO.Socket rejectedSocket) async {
    if (_recoveringAuth || !identical(rejectedSocket, _socket) ||
        _listeners.isEmpty) return;
    _recoveringAuth = true;
    try {
      final result = await ApiClient().refreshSession();
      if (result == AuthRefreshResult.refreshed &&
          identical(rejectedSocket, _socket)) {
        _closeSocket();
        await _performSync();
      }
    } finally {
      _recoveringAuth = false;
    }
  }

  void _closeSocket() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final socket = _socket;
    _socket = null;
    _socketToken = null;
    _wiredEvents.clear();
    socket?.disconnect();
    socket?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _foreground = false;
      _closeSocket();
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(_sync());
    }
  }
}
