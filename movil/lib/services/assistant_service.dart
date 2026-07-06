import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../backend_config.dart';

/// Servicio del Assistant (chatbot auxiliar) para el cliente.
///
/// Consume el endpoint stateless `/api/v1/assistant/chat`. El backend resuelve
/// el arbol de decisiones; aqui solo se envia el nodo actual y la opcion elegida.
class AssistantService {
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

  Future<Map<String, dynamic>> chat({String? nodo, String? opcion}) async {
    final url = Uri.parse('${BackendConfig.baseUrl}/api/v1/assistant/chat');
    final body = jsonEncode({
      if (nodo != null) 'nodo': nodo,
      if (opcion != null) 'opcion': opcion,
    });

    final response = await http.post(url, headers: await _headers(), body: body);

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }

    throw Exception('No se pudo contactar al asistente (${response.statusCode}).');
  }
}
