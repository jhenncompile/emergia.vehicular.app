import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Servicio para gestionar vehiculos del usuario.
class VehiculoService {
  final ApiService apiService;

  VehiculoService({required this.apiService});

  Future<Map<String, dynamic>> registrarVehiculo({
    required int usuarioId,
    required String marca,
    required String modelo,
    required String placa,
    required String color,
    required int anio,
    String? tipoCombustible,
    String? detalle,
  }) async {
    try {
      final response = await apiService.post(
        '/api/v1/vehiculos/',
        queryParams: {'usuario_id': usuarioId},
        body: {
          'marca': marca,
          'modelo': modelo,
          'placa': placa,
          'color': color,
          'anio': anio,
          'tipo_combustible': tipoCombustible,
          'detalle': detalle,
          'usuario_id': usuarioId,
        },
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al registrar vehiculo: $e');
    }
  }

  Future<List<Map<String, dynamic>>> obtenerMisVehiculos({
    required int usuarioId,
  }) async {
    final cacheKey = 'vehiculos_cache_$usuarioId';
    try {
      final response = await apiService.get(
        '/api/v1/vehiculos/usuario/$usuarioId',
      );

      List<Map<String, dynamic>> result = [];
      if (response is List) {
        result = List<Map<String, dynamic>>.from(
          response.map((item) => item as Map<String, dynamic>),
        );
      } else if (response is Map<String, dynamic>) {
        result = [response];
      } else {
        throw Exception('Formato de respuesta inesperado');
      }

      // Guardar en caché local
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(result));

      return result;
    } catch (e) {
      // Si falla la red, intentar leer de caché local
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString(cacheKey);
      if (cacheData != null) {
        final List<dynamic> decoded = jsonDecode(cacheData);
        return List<Map<String, dynamic>>.from(
            decoded.map((item) => item as Map<String, dynamic>));
      }
      throw Exception('Error al obtener vehiculos y no hay caché local: $e');
    }
  }

  Future<Map<String, dynamic>> obtenerVehiculo({required int id}) async {
    try {
      final response = await apiService.get('/api/v1/vehiculos/$id');

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Formato de respuesta inesperado');
    } catch (e) {
      throw Exception('Error al obtener vehiculo: $e');
    }
  }

  Future<Map<String, dynamic>> actualizarVehiculo({
    required int vehiculoId,
    required int usuarioId,
    String? placa,
    String? marca,
    String? modelo,
    String? color,
    int? anio,
    String? tipoCombustible,
    String? detalle,
  }) async {
    try {
      final Map<String, dynamic> body = {
        if (placa != null && placa.trim().isNotEmpty) 'placa': placa.trim(),
        if (marca != null && marca.trim().isNotEmpty) 'marca': marca.trim(),
        if (modelo != null && modelo.trim().isNotEmpty) 'modelo': modelo.trim(),
        if (color != null && color.trim().isNotEmpty) 'color': color.trim(),
        if (tipoCombustible != null && tipoCombustible.trim().isNotEmpty)
          'tipo_combustible': tipoCombustible.trim(),
        if (detalle != null && detalle.trim().isNotEmpty)
          'detalle': detalle.trim(),
      };
      if (anio != null) {
        body['anio'] = anio;
      }

      final response = await apiService.put(
        '/api/v1/vehiculos/$vehiculoId',
        queryParams: {'usuario_id': usuarioId},
        body: body,
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al actualizar vehiculo: $e');
    }
  }

  /// El backend actual no expone endpoint para eliminar vehiculos.
  Future<void> eliminarVehiculoNoDisponible() async {
    throw Exception(
      'Eliminar vehiculo no esta disponible en el backend actual.',
    );
  }
}
