import 'package:flutter/material.dart';
import '../services/notificacion_service.dart';

class NotificacionProvider extends ChangeNotifier {
  final NotificacionService notificacionService;

  List<Map<String, dynamic>> _notificacionesNoLeidas = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _countNoLeidas = 0;

  NotificacionProvider({required this.notificacionService});

  // Getters
  List<Map<String, dynamic>> get notificacionesNoLeidas =>
      _notificacionesNoLeidas;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get countNoLeidas => _countNoLeidas;

  /// Registrar token de Firebase al iniciar la app
  Future<void> registrarTokenDispositivo({
    required int usuarioId,
    required String tokenFCM,
    required String plataforma,
  }) async {
    try {
      await notificacionService.registrarTokenDispositivo(
        usuarioId: usuarioId,
        tokenFCM: tokenFCM,
        plataforma: plataforma,
      );
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> cargarNotificacionesNoLeidas({required int usuarioId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _notificacionesNoLeidas = await notificacionService
          .obtenerNotificacionesNoLeidas(usuarioId: usuarioId);
      _countNoLeidas = _notificacionesNoLeidas.length;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cargarHistorialNotificaciones({required int usuarioId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _notificacionesNoLeidas = await notificacionService
          .obtenerHistorialNotificaciones(usuarioId: usuarioId);
      _countNoLeidas = _notificacionesNoLeidas.where((n) => n['leido'] != true).length;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Marcar notificación como leída
  Future<bool> marcarComoLeida({
    required int notificacionId,
    int usuarioId = 0,
  }) async {
    try {
      await notificacionService.marcarComoLeida(
        notificacionId: notificacionId,
        usuarioId: usuarioId,
      );

      // Remover de no leídas
      _notificacionesNoLeidas.removeWhere((n) => n['id'] == notificacionId);
      _countNoLeidas = _notificacionesNoLeidas.length;

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Marcar todas las notificaciones como leídas
  Future<bool> marcarTodasComoLeidas() async {
    try {
      for (var notificacion in _notificacionesNoLeidas) {
        await notificacionService.marcarComoLeida(
          notificacionId: notificacion['id'],
        );
      }

      _notificacionesNoLeidas = [];
      _countNoLeidas = 0;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void limpiar() {
    _notificacionesNoLeidas = [];
    _countNoLeidas = 0;
    _errorMessage = null;
  }
}
