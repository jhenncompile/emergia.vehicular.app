import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../backend_config.dart';

class CalificacionService {
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Envía la calificación del cliente al backend.
  Future<Map<String, dynamic>> enviarCalificacion({
    required int incidenteId,
    required int puntuacion,
    String? comentario,
  }) async {
    final url = Uri.parse('${BackendConfig.baseUrl}/api/v1/calificaciones/');
    final body = jsonEncode({
      'incidente_id': incidenteId,
      'puntuacion': puntuacion,
      if (comentario != null && comentario.isNotEmpty) 'comentario': comentario,
    });

    final response = await http.post(url, headers: await _headers(), body: body);

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    final detail = _extractDetail(response.body);
    throw Exception(detail);
  }

  /// Consulta si ya existe una calificación para un incidente.
  /// Devuelve null si no existe (404).
  Future<Map<String, dynamic>?> obtenerCalificacion(int incidenteId) async {
    final url = Uri.parse(
        '${BackendConfig.baseUrl}/api/v1/calificaciones/incidente/$incidenteId');
    final response = await http.get(url, headers: await _headers());

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) return null;

    final detail = _extractDetail(response.body);
    throw Exception(detail);
  }

  String _extractDetail(String body) {
    try {
      final json = jsonDecode(body);
      return json['detail']?.toString() ?? body;
    } catch (_) {
      return body;
    }
  }
}
