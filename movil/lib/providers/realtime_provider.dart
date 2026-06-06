import 'dart:async';

import 'package:flutter/material.dart';

import '../services/realtime_service.dart';
import 'auth_provider.dart';
import 'incidente_provider.dart';

class RealtimeProvider extends ChangeNotifier {
  RealtimeProvider({required this.realtimeService});

  final RealtimeService realtimeService;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  int? _connectedUserId;
  bool _isConnected = false;
  Map<String, dynamic>? _lastEvent;

  bool get isConnected => _isConnected;
  Map<String, dynamic>? get lastEvent => _lastEvent;

  void sync({
    required AuthProvider authProvider,
    required IncidenteProvider incidenteProvider,
  }) {
    if (authProvider.isCheckingAuth) return;

    final userId = authProvider.userId;
    if (!authProvider.isAuthenticated || userId == null) {
      disconnect();
      return;
    }

    if (_connectedUserId == userId) return;

    _connectedUserId = userId;
    _subscription?.cancel();
    _subscription = realtimeService.events.listen((event) {
      _lastEvent = event;
      _isConnected = realtimeService.isConnected;
      _handleIncidentEvent(
        event,
        incidenteProvider,
        userId,
        authProvider.isTecnico,
      );
      notifyListeners();
    });

    realtimeService.connect(usuarioId: userId).then((_) {
      _isConnected = realtimeService.isConnected;
      notifyListeners();
    });
  }

  void _handleIncidentEvent(
    Map<String, dynamic> event,
    IncidenteProvider incidenteProvider,
    int userId,
    bool esTecnico,
  ) {
    final incidentId = _readInt(event['incidente_id']);
    final newStatus = event['estado_nuevo']?.toString();

    if (incidentId != null && newStatus != null && newStatus.isNotEmpty) {
      incidenteProvider.actualizarEstadoLocal(
        id: incidentId,
        estado: newStatus,
      );
    }

    if (_isIncidentEvent(event)) {
      incidenteProvider.cargarMisIncidentes(
        usuarioId: userId,
        esTecnico: esTecnico,
      );
    }
  }

  bool _isIncidentEvent(Map<String, dynamic> event) {
    final type = event['tipo']?.toString() ?? '';
    final realtimeEvent = event['evento']?.toString() ?? '';

    return event['incidente_id'] != null ||
        type.startsWith('incidente_') ||
        type.startsWith('cambio_estado_') ||
        realtimeEvent.contains('incidente') ||
        realtimeEvent.contains('auxilio') ||
        realtimeEvent.contains('servicio') ||
        realtimeEvent.startsWith('taller_');
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> disconnect() async {
    _connectedUserId = null;
    _isConnected = false;
    _lastEvent = null;
    await _subscription?.cancel();
    _subscription = null;
    await realtimeService.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    realtimeService.dispose();
    super.dispose();
  }
}
