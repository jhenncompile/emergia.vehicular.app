import 'dart:async';

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_notification_service.dart';
import '../services/realtime_service.dart';
import 'auth_provider.dart';
import 'incidente_provider.dart';
import '../screens/calificacion/calificacion_screen.dart';

class RealtimeProvider extends ChangeNotifier {
  RealtimeProvider({required this.realtimeService});

  final RealtimeService realtimeService;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  StreamSubscription<bool>? _statusSubscription;
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

    if (_connectedUserId == userId && _isConnected) return;

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

    _statusSubscription?.cancel();
    _statusSubscription = realtimeService.connectionStatus.listen((isConnected) {
      _isConnected = isConnected;
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
      
      // Auto-abrir pantalla de calificación si es cliente y el incidente finalizó
      if (!esTecnico && (newStatus.toLowerCase() == 'finalizado' || newStatus.toLowerCase() == 'completado')) {
        Future.delayed(const Duration(milliseconds: 500), () {
          final context = navigatorKey.currentContext;
          if (context != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CalificacionScreen(
                  incidenteId: incidentId,
                ),
              ),
            );
          }
        });
      }
    }

    // Mostrar notificacion push local
    final title = event['titulo']?.toString();
    final body = event['mensaje']?.toString();

    if (title != null && title.isNotEmpty && body != null && body.isNotEmpty) {
      LocalNotificationService().showNotification(
        id: incidentId ?? DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
        payload: incidentId?.toString(),
      );
    } else if (incidentId != null && newStatus != null && newStatus.isNotEmpty) {
      LocalNotificationService().showNotification(
        id: incidentId,
        title: 'Actualización de Incidente',
        body: 'El incidente #$incidentId ahora está: $newStatus',
        payload: incidentId.toString(),
      );
    }

    if (event['tipo'] == 'ubicacion_tecnico' && incidentId != null) {
      final lat = _readDouble(event['latitud']);
      final lng = _readDouble(event['longitud']);
      if (lat != null && lng != null) {
        incidenteProvider.actualizarUbicacionTecnico(incidentId, lat, lng);
      }
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

  double? _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> disconnect() async {
    _connectedUserId = null;
    _isConnected = false;
    _lastEvent = null;
    await _subscription?.cancel();
    _subscription = null;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    await realtimeService.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _statusSubscription?.cancel();
    realtimeService.dispose();
    super.dispose();
  }
}
