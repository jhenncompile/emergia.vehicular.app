import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../backend_config.dart';

class RealtimeService {
  RealtimeService({String? baseUrl})
    : baseUrl = baseUrl ?? BackendConfig.baseUrl;

  final String baseUrl;
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();

  WebSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int? _usuarioId;
  bool _manualClose = false;

  Stream<Map<String, dynamic>> get events => _eventsController.stream;
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  bool get isConnected => _socket?.readyState == WebSocket.open;

  Future<void> connect({required int usuarioId}) async {
    if (_usuarioId == usuarioId && isConnected) return;

    _manualClose = false;
    _usuarioId = usuarioId;
    _connectionStatusController.add(false);
    await _closeSocket();

    try {
      final socket = await WebSocket.connect(_buildWsUri(usuarioId).toString());
      _socket = socket;
      _connectionStatusController.add(true);
      _startHeartbeat();

      socket.listen(
        _handleMessage,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _connectionStatusController.add(false);
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _manualClose = true;
    _usuarioId = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionStatusController.add(false);
    await _closeSocket();
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventsController.close();
    await _connectionStatusController.close();
  }

  Uri _buildWsUri(int usuarioId) {
    final uri = Uri.parse(baseUrl);
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/$usuarioId',
      query: null,
      fragment: null,
    );
  }

  void _handleMessage(dynamic rawMessage) {
    if (rawMessage == 'pong') return;

    try {
      final decoded = jsonDecode(rawMessage.toString());
      if (decoded is Map<String, dynamic>) {
        _eventsController.add(decoded);
      }
    } catch (_) {
      // Ignore malformed realtime payloads.
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected) {
        _socket?.add('ping');
      }
    });
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket = null;
    _connectionStatusController.add(false);

    if (_manualClose || _usuarioId == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      final userId = _usuarioId;
      if (userId != null) {
        connect(usuarioId: userId);
      }
    });
  }

  Future<void> _closeSocket() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final socket = _socket;
    _socket = null;

    if (socket != null &&
        (socket.readyState == WebSocket.open ||
            socket.readyState == WebSocket.connecting)) {
      await socket.close();
    }
  }
}
