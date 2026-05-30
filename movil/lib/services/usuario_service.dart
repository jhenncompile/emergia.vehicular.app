import 'api_service.dart';

/// Servicio de usuario para funcionalidades expuestas al cliente movil.
class UsuarioService {
  final ApiService apiService;

  UsuarioService({required this.apiService});

  Future<Map<String, dynamic>> obtenerPerfil() async {
    try {
      final response = await apiService.get('/api/v1/usuarios/me');

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al obtener perfil: $e');
    }
  }

  Future<Map<String, dynamic>> actualizarPerfil({
    String? nombre,
    String? apellido,
    String? telefono,
    String? direccion,
    String? ciudad,
  }) async {
    try {
      final response = await apiService.put(
        '/api/v1/usuarios/me',
        body: {
          if (_texto(nombre) != null) 'nombre': _texto(nombre),
          'apellido': _texto(apellido),
          'telefono': _texto(telefono),
          'ciudad': _texto(ciudad),
          'direccion': _texto(direccion),
        },
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al actualizar perfil: $e');
    }
  }

  Future<Map<String, dynamic>> solicitarRecuperacionContrasena({
    required String correo,
  }) async {
    try {
      final response = await apiService.post(
        '/api/v1/auth/forgot-password',
        body: {'correo': correo},
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al solicitar recuperacion de contrasena: $e');
    }
  }

  String? _texto(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
