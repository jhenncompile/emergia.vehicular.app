import 'api_service.dart';

class NotificacionService {
  final ApiService apiService;

  NotificacionService({required this.apiService});

  Future<Map<String, dynamic>> registrarTokenDispositivo({
    required int usuarioId,
    required String tokenFCM,
    required String plataforma,
  }) async {
    try {
      final response = await apiService.post(
        '/api/v1/notificaciones/tokens',
        body: {
          'usuario_id': usuarioId,
          'token_fcm': tokenFCM,
          'plataforma': plataforma,
        },
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al registrar token: $e');
    }
  }

  Future<List<Map<String, dynamic>>> obtenerNotificacionesNoLeidas({
    required int usuarioId,
  }) async {
    try {
      final response = await apiService.get(
        '/api/v1/notificaciones/usuario/$usuarioId/pendientes',
      );

      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => item as Map<String, dynamic>),
        );
      }
      if (response is Map<String, dynamic>) {
        return [response];
      }
      throw Exception('Formato de respuesta inesperado');
    } catch (e) {
      throw Exception('Error al obtener notificaciones: $e');
    }
  }

  Future<List<Map<String, dynamic>>> obtenerHistorialNotificaciones({
    required int usuarioId,
  }) async {
    try {
      final response = await apiService.get(
        '/api/v1/notificaciones/usuario/$usuarioId/historial',
      );

      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => item as Map<String, dynamic>),
        );
      }
      if (response is Map<String, dynamic>) {
        return [response];
      }
      throw Exception('Formato de respuesta inesperado');
    } catch (e) {
      throw Exception('Error al obtener historial notificaciones: $e');
    }
  }

  Future<Map<String, dynamic>> marcarComoLeida({
    required int notificacionId,
    int usuarioId = 0,
  }) async {
    try {
      final response = await apiService.patch(
        '/api/v1/notificaciones/$notificacionId/leer',
        queryParams: {'usuario_id': usuarioId},
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al marcar notificacion como leida: $e');
    }
  }
}
