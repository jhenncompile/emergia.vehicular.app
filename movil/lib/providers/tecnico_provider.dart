import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/incidente_service.dart';
import '../services/location_tracking_service.dart';
import '../services/tracking_service.dart';

/// Provider que gestiona el incidente activo del técnico en tiempo real.
/// 
/// Responsabilidades:
/// - Garantizar que el técnico solo tenga 1 incidente activo (en_camino o en_atencion)
/// - Sincronizar ubicación GPS cada 10 segundos
/// - Mostrar distancia, ETA y ruta al incidente
/// - Detectar llegada automática y marcar manual si es necesario
/// - Emitir notificaciones de cambios de estado
class TecnicoProvider extends ChangeNotifier {
  final IncidenteService incidenteService;
  final LocationTrackingService locationService;
  final TrackingService trackingService;

  // Estado del incidente activo
  Map<String, dynamic>? _incidenteActivo;
  double _distanciaActual = 0.0;
  double _etaMinutos = 0.0;
  Position? _ubicacionActual;
  RutaResponse? _rutaActual;
  
  // Estado del tracking
  bool _isTracking = false;
  bool _llego = false;
  String? _errorMessage;
  String _estadoConexion = 'desconectado'; // desconectado, conectando, conectado

  // Streams y timers
  StreamSubscription<Position>? _locationSubscription;
  Timer? _trackingTimer;
  
  // Configuración
  static const double distanciaLlegadaMetros = 100.0;
  static const int intervaloTrackingSegundos = 10;

  TecnicoProvider({
    required this.incidenteService,
    required this.locationService,
    required this.trackingService,
  });

  // === GETTERS ===
  Map<String, dynamic>? get incidenteActivo => _incidenteActivo;
  double get distanciaActual => _distanciaActual;
  double get etaMinutos => _etaMinutos;
  Position? get ubicacionActual => _ubicacionActual;
  RutaResponse? get rutaActual => _rutaActual;
  bool get isTracking => _isTracking;
  bool get llego => _llego;
  String? get errorMessage => _errorMessage;
  String get estadoConexion => _estadoConexion;

  /// Carga el incidente activo del técnico (debe haber solo 1 en estado en_camino o en_atencion)
  Future<void> cargarIncidenteActivo({required int usuarioId}) async {
    try {
      _errorMessage = null;
      final incidentes = await incidenteService.obtenerIncidentesTecnico();
      
      // Filtrar incidentes activos (no finalizados)
      final activos = incidentes.where((i) {
        final estado = i['estado'] as String? ?? '';
        return estado != 'finalizado' && estado != 'cancelado';
      }).toList();

      if (activos.isEmpty) {
        _incidenteActivo = null;
        _llego = false;
      } else if (activos.length == 1) {
        _incidenteActivo = activos.first;
        _llego = false;
      } else {
        // ERROR: Múltiples incidentes activos (no debería pasar)
        _errorMessage = 'Error: Múltiples incidentes activos. Contacte al administrador.';
        _incidenteActivo = activos.first; // Usar el primero por defecto
      }
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al cargar incidente activo: $e';
      notifyListeners();
    }
  }

  /// Inicia el tracking en tiempo real del técnico
  Future<void> iniciarTracking() async {
    if (_isTracking || _incidenteActivo == null) return;

    try {
      _isTracking = true;
      _estadoConexion = 'conectando';
      _errorMessage = null;
      notifyListeners();

      // Iniciar tracking de ubicación
      await locationService.startTracking();

      // Obtener ubicación inicial y ruta
      _ubicacionActual = await locationService.getCurrentLocation();
      await _actualizarRuta();
      notifyListeners();

      // Escuchar cambios de ubicación cada 10 segundos
      _locationSubscription = locationService.locationUpdates.listen(
        (position) async {
          _ubicacionActual = position;
          await _procesarUbicacion(position);
        },
        onError: (e) {
          _errorMessage = 'Error en tracking de ubicación: $e';
          notifyListeners();
        },
      );

      _estadoConexion = 'conectado';
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al iniciar tracking: $e';
      _isTracking = false;
      _estadoConexion = 'desconectado';
      notifyListeners();
    }
  }

  /// Detiene el tracking en tiempo real
  Future<void> detenerTracking() async {
    _isTracking = false;
    _estadoConexion = 'desconectado';
    await _locationSubscription?.cancel();
    await locationService.stopTracking();
    notifyListeners();
  }

  /// Procesa una actualización de ubicación
  Future<void> _procesarUbicacion(Position position) async {
    if (_incidenteActivo == null) return;

    try {
      // Obtener coordenadas del incidente
      final latIncidente = _incidenteActivo!['latitud'] as double?;
      final lonIncidente = _incidenteActivo!['longitud'] as double?;
      
      if (latIncidente == null || lonIncidente == null) return;

      // Enviar ubicación al backend
      final response = await incidenteService.enviarUbicacionTecnico(
        incidenteId: _incidenteActivo!['id'] as int,
        latitud: position.latitude,
        longitud: position.longitude,
      );

      // Actualizar distancia
      if (response['distancia_metros'] is num) {
        _distanciaActual = (response['distancia_metros'] as num).toDouble();
      }

      // Verificar si llegó automáticamente
      if (response['llego_automaticamente'] == true) {
        _llego = true;
        if (response['estado_nuevo'] != null) {
          _incidenteActivo!['estado'] = response['estado_nuevo'];
        }
      }

      // Actualizar ruta si cambió significativamente la posición
      if (_debemosActualizarRuta()) {
        await _actualizarRuta();
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al procesar ubicación: $e';
      notifyListeners();
    }
  }

  /// Verifica si debemos actualizar la ruta (cada 30 segundos aprox)
  bool _debemosActualizarRuta() {
    // Actualizar ruta cada vez para mantener ETA actualizado
    return true;
  }

  /// Actualiza la ruta desde ubicación actual al incidente
  Future<void> _actualizarRuta() async {
    if (_incidenteActivo == null) return;

    try {
      final ruta = await trackingService.obtenerRuta(
        incidenteId: _incidenteActivo!['id'] as int,
      );
      _rutaActual = ruta;
      
      if (ruta.duracionMinutos > 0) {
        _etaMinutos = ruta.duracionMinutos;
      }
    } catch (e) {
      // No actualizar error message aquí, solo log
      // _errorMessage = 'Error al obtener ruta: $e';
    }
  }

  /// Marca la llegada manual del técnico (respaldo si no se detecta automáticamente)
  Future<void> marcarLlegada() async {
    if (_incidenteActivo == null) return;

    try {
      _errorMessage = null;
      await incidenteService.marcarLlegadaTecnico(
        incidenteId: _incidenteActivo!['id'] as int,
      );
      
      _llego = true;
      _incidenteActivo!['estado'] = 'en_atencion';
      
      // Detener tracking automáticamente
      await detenerTracking();
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al marcar llegada: $e';
      notifyListeners();
    }
  }

  Future<void> finalizarIncidente() async {
    if (_incidenteActivo == null) return;
    try {
      _errorMessage = null;
      await incidenteService.finalizarIncidente(
        incidenteId: _incidenteActivo!['id'] as int,
      );
      _incidenteActivo!['estado'] = 'finalizado';
      await detenerTracking();
      _incidenteActivo = null; // Clear active incident
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al finalizar incidente: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelarIncidente(String motivo) async {
    if (_incidenteActivo == null) return;
    try {
      _errorMessage = null;
      await incidenteService.cancelarIncidente(
        incidenteId: _incidenteActivo!['id'] as int,
        motivo: motivo,
      );
      _incidenteActivo!['estado'] = 'cancelado';
      await detenerTracking();
      _incidenteActivo = null; // Clear active incident
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al cancelar incidente: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Descarga todo y limpia recursos
  @override
  Future<void> dispose() async {
    await detenerTracking();
    await locationService.dispose();
    _trackingTimer?.cancel();
    super.dispose();
  }

  /// Verifica si el técnico está cerca del incidente (< 100m)
  bool estaCerca() {
    return _distanciaActual < distanciaLlegadaMetros;
  }

  /// Obtiene el botón de acción que debe mostrar (llegada manual si aplica)
  bool puedeMarcarLlegada() {
    return _incidenteActivo != null && 
           _incidenteActivo!['estado'] == 'en_camino' &&
           !_llego;
  }
}
