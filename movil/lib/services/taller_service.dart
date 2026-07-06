import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Servicio para gestionar talleres disponibles
class TallerService {
  final ApiService apiService;

  TallerService({required this.apiService});

  /// Obtener talleres activos (Todos disponibles)
  /// GET /api/v1/talleres/activos
  Future<List<Map<String, dynamic>>> obtenerTalleresActivos({
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final response = await apiService.get(
        '/api/v1/talleres/activos',
        queryParams: {'skip': skip, 'limit': limit},
      );

      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => item as Map<String, dynamic>),
        );
      } else if (response is Map<String, dynamic>) {
        return [response];
      } else {
        throw Exception('Formato de respuesta inesperado');
      }
    } catch (e) {
      throw Exception('Error al obtener talleres activos: $e');
    }
  }

  /// Directorio: catálogo de especialidades disponibles
  /// GET /api/v1/taller-config/especialidades
  Future<List<Map<String, dynamic>>> obtenerEspecialidades() async {
    try {
      final response = await apiService.get('/api/v1/taller-config/especialidades');

      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => item as Map<String, dynamic>),
        );
      }
      throw Exception('Formato de respuesta inesperado');
    } catch (e) {
      throw Exception('Error al obtener especialidades: $e');
    }
  }

  /// Directorio: talleres recomendados por especialidad (solo consulta)
  /// GET /api/v1/talleres/directorio
  Future<List<Map<String, dynamic>>> obtenerDirectorioPorEspecialidad({
    required int especialidadId,
    double? latitud,
    double? longitud,
  }) async {
    try {
      final response = await apiService.get(
        '/api/v1/talleres/directorio',
        queryParams: {
          'especialidad_id': especialidadId,
          if (latitud != null) 'latitud': latitud,
          if (longitud != null) 'longitud': longitud,
        },
      );

      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => item as Map<String, dynamic>),
        );
      }
      throw Exception('Formato de respuesta inesperado');
    } catch (e) {
      throw Exception('Error al obtener el directorio de talleres: $e');
    }
  }

  /// Obtener un taller específico
  /// GET /api/v1/talleres/{id}
  Future<Map<String, dynamic>> obtenerTaller({required int tallerId}) async {
    try {
      final response = await apiService.get('/api/v1/talleres/$tallerId');

      if (response is Map<String, dynamic>) {
        return response;
      } else {
        throw Exception('Respuesta inesperada del servidor');
      }
    } catch (e) {
      throw Exception('Error al obtener taller: $e');
    }
  }

  /// Buscar talleres por nombre o ciudad
  /// GET /api/v1/talleres/buscar?query={query}
  Future<List<Map<String, dynamic>>> buscarTalleres({
    required String query,
  }) async {
    try {
      final response = await apiService.get(
        '/api/v1/talleres/buscar',
        queryParams: {'query': query},
      );

      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => item as Map<String, dynamic>),
        );
      } else if (response is Map<String, dynamic>) {
        return [response];
      } else {
        throw Exception('Formato de respuesta inesperado');
      }
    } catch (e) {
      throw Exception('Error al buscar talleres: $e');
    }
  }

  /// Obtener talleres cercanos al usuario (FUTURO: requiere geolocalización)
  /// ESTA FUNCIONALIDAD SE IMPLEMENTARÁ EN LA PRÓXIMA VERSIÓN
  /// TODO: Requiere:
  /// - Obtener ubicación actual del usuario (geolocator package)
  /// - Calcular distancia entre usuario y talleres
  /// - Ordenar por proximidad
  /// - Mostrar talleres más cercanos al incidente reportado
  ///
  /// Cuando se implemente, se verá algo como:
  /// POST /api/v1/talleres/cercanos
  /// {
  ///   "latitud": -17.389...,
  ///   "longitud": -66.163...,
  ///   "radio_km": 5
  /// }
  Future<List<Map<String, dynamic>>> obtenerTalleresCercanos({
    required double latitud,
    required double longitud,
    double radioKm = 5.0,
  }) async {
    try {
      debugPrint('⚠️ ACTUALIZACIÓN NO DISPONIBLE');
      debugPrint(
        'La funcionalidad de búsqueda de talleres cercanos se implementará en la próxima versión.',
      );
      debugPrint(
        'Requiere integración con servicios de geolocalización y cálculo de distancias.',
      );
      debugPrint(
        'Por ahora, usa obtenerTalleresActivos() para ver todos los talleres disponibles.',
      );
      return [];
    } catch (e) {
      throw Exception('Error al obtener talleres cercanos: $e');
    }
  }

  /// Obtener servicios ofrecidos por un taller
  /// GET /api/v1/talleres/{id}/servicios
  Future<List<Map<String, dynamic>>> obtenerServiciosTaller({
    required int tallerId,
  }) async {
    try {
      final response = await apiService.get(
        '/api/v1/talleres/$tallerId/servicios',
      );

      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => item as Map<String, dynamic>),
        );
      } else if (response is Map<String, dynamic>) {
        return [response];
      } else {
        throw Exception('Formato de respuesta inesperado');
      }
    } catch (e) {
      throw Exception('Error al obtener servicios del taller: $e');
    }
  }
}
