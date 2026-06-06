import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// Servicio para gestionar GPS en tiempo real del técnico.
/// 
/// Responsabilidades:
/// - Solicitar permisos de ubicación
/// - Obtener posición actual del dispositivo
/// - Iniciar tracking continuo con intervalo de 10 segundos
/// - Emitir eventos de cambio de ubicación
class LocationTrackingService {
  final _locationController = StreamController<Position>.broadcast();
  
  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;

  /// Stream de eventos de ubicación actualizada
  Stream<Position> get locationUpdates => _locationController.stream;

  /// Indica si el tracking está activo
  bool get isTracking => _isTracking;

  /// Solicita permisos de ubicación
  Future<bool> requestLocationPermission() async {
    final status = await Geolocator.checkPermission();
    
    if (status == LocationPermission.denied) {
      final newStatus = await Geolocator.requestPermission();
      return newStatus != LocationPermission.denied &&
          newStatus != LocationPermission.deniedForever;
    }
    
    if (status == LocationPermission.deniedForever) {
      return false;
    }
    
    return status == LocationPermission.whileInUse ||
        status == LocationPermission.always;
  }

  /// Obtiene la posición actual del dispositivo
  Future<Position> getCurrentLocation() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        throw Exception('Permisos de ubicación denegados');
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0, // Obtener actualizaciones incluso sin movimiento
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      throw Exception('Error al obtener ubicación: $e');
    }
  }

  /// Inicia el tracking continuo de ubicación (cada 10 segundos)
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        throw Exception('Permisos de ubicación denegados');
      }

      _isTracking = true;

      // Obtener ubicación inicial
      final initialPosition = await getCurrentLocation();
      _locationController.add(initialPosition);

      // Iniciar stream de ubicaciones cada 10 segundos
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0, // Obtener actualizaciones incluso sin movimiento
        ),
      ).listen(
        (Position position) {
          _locationController.add(position);
        },
        onError: (e) {
          _locationController.addError(Exception('Error en tracking: $e'));
        },
      );
    } catch (e) {
      _isTracking = false;
      _locationController.addError(Exception('Error al iniciar tracking: $e'));
    }
  }

  /// Detiene el tracking de ubicación
  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionStream?.cancel();
    _positionStream = null;
  }

  /// Libera recursos
  Future<void> dispose() async {
    await stopTracking();
    await _locationController.close();
  }
}
