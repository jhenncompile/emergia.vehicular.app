import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para guardar incidentes localmente cuando no hay conexión a internet.
/// Implementa CU-N03: Registrar emergencia sin conexión a internet.
class OfflineIncidenteService {
  static const String _kPendingKey = 'offline_incidentes_pendientes';

  /// Guarda un incidente en la base de datos local como pendiente de sincronización.
  static Future<Map<String, dynamic>> guardarLocalmente({
    required int usuarioId,
    required int vehiculoId,
    required String descripcion,
    required String ubicacion,
    required double latitud,
    required double longitud,
    String? audioPath,
    String? imagenPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existentes = await obtenerPendientes();

    // Generar un ID local temporal negativo para distinguirlo de IDs del servidor
    final idLocal = -(DateTime.now().millisecondsSinceEpoch);

    final incidenteLocal = {
      'id': idLocal,
      'usuario_id': usuarioId,
      'vehiculo_id': vehiculoId,
      'descripcion': descripcion,
      'ubicacion': ubicacion,
      'latitud': latitud,
      'longitud': longitud,
      'audio_path': audioPath,
      'imagen_path': imagenPath,
      'estado': 'pendiente_sync',
      'fecha_reporte': DateTime.now().toIso8601String(),
      'es_local': true,
    };

    existentes.add(incidenteLocal);
    await prefs.setString(_kPendingKey, jsonEncode(existentes));
    return incidenteLocal;
  }

  /// Obtiene la lista de incidentes guardados localmente.
  static Future<List<Map<String, dynamic>>> obtenerPendientes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final lista = jsonDecode(raw) as List;
      return lista.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Cuenta cuántos incidentes hay pendientes de sincronización.
  static Future<int> contarPendientes() async {
    final pendientes = await obtenerPendientes();
    return pendientes.length;
  }

  /// Elimina un incidente local de la lista de pendientes (ya fue sincronizado).
  static Future<void> eliminarPendiente(int idLocal) async {
    final prefs = await SharedPreferences.getInstance();
    final existentes = await obtenerPendientes();
    existentes.removeWhere((inc) => inc['id'] == idLocal);
    await prefs.setString(_kPendingKey, jsonEncode(existentes));
  }

  /// Detecta si el error es de falta de conexión a internet.
  static bool esErrorDeConexion(Object error) {
    final mensaje = error.toString().toLowerCase();
    return mensaje.contains('socketexception') ||
        mensaje.contains('connection refused') ||
        mensaje.contains('failed host lookup') ||
        mensaje.contains('network is unreachable') ||
        mensaje.contains('os error') ||
        mensaje.contains('errno = 111') ||
        mensaje.contains('connection timed out');
  }
}
