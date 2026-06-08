import 'dart:async';
import 'dart:math' show sqrt, sin, cos, atan2;
import 'api_service.dart';

/// Modelo de respuesta cuando el técnico actualiza su ubicación
class LocationTecnicoResponse {
  final double distanciaMetros;
  final bool llegoAutomaticamente;
  final String estadoNuevo;
  final bool puedeMarcarManual;
  final String mensaje;

  LocationTecnicoResponse({
    required this.distanciaMetros,
    required this.llegoAutomaticamente,
    required this.estadoNuevo,
    required this.puedeMarcarManual,
    required this.mensaje,
  });

  factory LocationTecnicoResponse.fromJson(Map<String, dynamic> json) {
    return LocationTecnicoResponse(
      distanciaMetros: (json['distancia_metros'] as num?)?.toDouble() ?? 0.0,
      llegoAutomaticamente: json['llego_automaticamente'] as bool? ?? false,
      estadoNuevo: json['estado_nuevo'] as String? ?? '',
      puedeMarcarManual: json['puede_marcar_manual'] as bool? ?? false,
      mensaje: json['mensaje'] as String? ?? '',
    );
  }
}

/// Modelo de respuesta para marcar llegada manual
class MarcarLlegadaResponse {
  final String estado;
  final DateTime? fechaLlegadaTecnico;
  final String mensaje;

  MarcarLlegadaResponse({
    required this.estado,
    required this.fechaLlegadaTecnico,
    required this.mensaje,
  });

  factory MarcarLlegadaResponse.fromJson(Map<String, dynamic> json) {
    return MarcarLlegadaResponse(
      estado: json['estado'] as String? ?? '',
      fechaLlegadaTecnico: json['fecha_llegada_tecnico'] != null
          ? DateTime.parse(json['fecha_llegada_tecnico'] as String)
          : null,
      mensaje: json['mensaje'] as String? ?? '',
    );
  }
}

/// Modelo para los pasos de la ruta
class RutaPaso {
  final String instruccion;
  final double distanciaMetros;
  final double duracionSegundos;

  RutaPaso({
    required this.instruccion,
    required this.distanciaMetros,
    required this.duracionSegundos,
  });

  factory RutaPaso.fromJson(Map<String, dynamic> json) {
    return RutaPaso(
      instruccion: json['instruction'] as String? ?? '',
      distanciaMetros: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duracionSegundos: (json['duration'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Modelo de respuesta para obtener ruta
class RutaResponse {
  final double distanciaKm;
  final double duracionMinutos;
  final Map<String, dynamic>? geometry; // GeoJSON geometry
  final List<RutaPaso> pasos;
  final String? error;

  RutaResponse({
    required this.distanciaKm,
    required this.duracionMinutos,
    required this.geometry,
    required this.pasos,
    this.error,
  });

  factory RutaResponse.fromJson(Map<String, dynamic> json) {
    final pasosList = json['pasos'] as List? ?? [];
    return RutaResponse(
      distanciaKm: (json['distancia_km'] as num?)?.toDouble() ?? 0.0,
      duracionMinutos: (json['duracion_minutos'] as num?)?.toDouble() ?? 0.0,
      geometry: json['geometry'] as Map<String, dynamic>?,
      pasos: pasosList
          .map((paso) => RutaPaso.fromJson(paso as Map<String, dynamic>))
          .toList(),
      error: json['error'] as String?,
    );
  }
}

/// Servicio para gestionar el tracking del técnico.
/// 
/// Responsabilidades:
/// - Enviar ubicación actual al backend cada 10 segundos
/// - Recibir notificaciones de llegada automática vía WebSocket
/// - Marcar llegada manual si es necesario
/// - Obtener ruta desde ubicación actual al incidente
class TrackingService {
  final ApiService apiService;
  
  TrackingService({required this.apiService});

  /// Envía la ubicación actual del técnico al backend
  /// Retorna información sobre distancia y si llegó automáticamente
  Future<LocationTecnicoResponse> enviarUbicacion({
    required int incidenteId,
    required double latitud,
    required double longitud,
  }) async {
    try {
      final response = await apiService.post(
        '/api/v1/incidentes/$incidenteId/ubicacion-tecnico',
        body: {
          'latitud': latitud,
          'longitud': longitud,
        },
      );

      if (response is Map<String, dynamic>) {
        return LocationTecnicoResponse.fromJson(response);
      }
      
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al enviar ubicación: $e');
    }
  }

  /// Marca la llegada manual del técnico al incidente
  Future<MarcarLlegadaResponse> marcarLlegada({
    required int incidenteId,
  }) async {
    try {
      final response = await apiService.patch(
        '/api/v1/incidentes/$incidenteId/marcar-llegada',
        body: {},
      );

      if (response is Map<String, dynamic>) {
        return MarcarLlegadaResponse.fromJson(response);
      }
      
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al marcar llegada: $e');
    }
  }

  /// Obtiene la ruta recomendada desde la ubicación actual al incidente
  Future<RutaResponse> obtenerRuta({
    required int incidenteId,
  }) async {
    try {
      final response = await apiService.get(
        '/api/v1/incidentes/$incidenteId/ruta-tecnico',
      );

      if (response is Map<String, dynamic>) {
        return RutaResponse.fromJson(response);
      }
      
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al obtener ruta: $e');
    }
  }

  /// Calcula la distancia en metros entre dos puntos usando la fórmula Haversine
  /// (Utilidad local si necesita hacer cálculos en el cliente)
  double calcularDistanciaHaversine({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const R = 6371000; // Radio de la tierra en metros
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * (3.141592653589793 / 180);
  }
}
