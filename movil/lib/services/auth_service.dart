import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_service.dart';

/// Servicio de autenticación - Conecta con el backend
class AuthService {
  final ApiService apiService;
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _userIdKey = 'auth_user_id';
  static const String _userRoleKey = 'auth_user_role_id';
  static const String _userNameKey = 'auth_user_name';
  static const String _userEmailKey = 'auth_user_email';
  static const int clienteRoleId = 2;

  AuthService({required this.apiService});

  /// Login - Conecta con /auth/login del backend
  /// Nota: El endpoint /auth/login usa OAuth2PasswordRequestForm que requiere form-encoded, no JSON
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      // Hacer petición POST directamente con form-encoded
      final response = await http.post(
        Uri.parse('${apiService.baseUrl}/api/v1/auth/login'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'username': email,
          'password': password,
          'client_id': 'movil', // Indica que es desde la app móvil
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final roleId = _readInt(data['rol_id']);

        if (roleId != clienteRoleId) {
          await logout();
          throw Exception('Acceso denegado: esta app es solo para clientes.');
        }
        // Guardar token localmente
        if (data['access_token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          final token = data['access_token'] as String;
          await prefs.setString(_tokenKey, token);
          apiService.setAuthToken(token);
          await prefs.setInt(_userRoleKey, AuthService.clienteRoleId);

          final userId =
              _readInt(data['usuario_id']) ?? _extractUserIdFromToken(token);
          if (userId != null) {
            await prefs.setInt(_userIdKey, userId);
            data['user_id'] = userId;
          }

          if (data['user'] != null) {
            await prefs.setString(_userKey, data['user'].toString());
          }
          if (data['nombre'] != null) {
            await prefs.setString(_userNameKey, data['nombre'].toString());
          }
          await prefs.setString(_userEmailKey, email);
        }

        return data;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
          errorData['detail'] ??
              'Error al iniciar sesión: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error al iniciar sesión: $e');
    }
  }

  /// Obtiene el token guardado localmente
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    apiService.setAuthToken(token);
    return token;
  }

  /// Logout - Elimina el token local
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userRoleKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userEmailKey);
    apiService.setAuthToken(null);
  }

  /// Verifica si el usuario está autenticado
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    final roleId = await getCurrentUserRoleId();
    final isClientSession =
        token != null && token.isNotEmpty && roleId == clienteRoleId;

    if (token != null && token.isNotEmpty && !isClientSession) {
      await logout();
    }

    return isClientSession;
  }

  /// Obtiene datos del usuario guardados localmente
  Future<String?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userKey);
  }

  Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  Future<int?> getCurrentUserRoleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userRoleKey);
  }

  Future<String?> getCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  Future<String?> getCurrentUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey);
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  int? _extractUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      final sub = decoded['sub'];
      if (sub == null) return null;
      return int.tryParse(sub.toString());
    } catch (_) {
      return null;
    }
  }
}
