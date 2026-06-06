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
  static const int tecnicoRoleId = 3;

  AuthService({required this.apiService});

  /// Login - Conecta con /auth/login del backend
  /// Nota: El endpoint /auth/login usa OAuth2PasswordRequestForm que requiere form-encoded, no JSON
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      Map<String, dynamic> data;

      try {
        data = await _loginConPlataforma(
          email: email,
          password: password,
          plataforma: 'movil',
        );
      } on _LoginAttemptException catch (e) {
        if (!_debeReintentarComoTecnico(e)) {
          rethrow;
        }

        data = await _loginConPlataforma(
          email: email,
          password: password,
          plataforma: 'web',
        );
      }

      final roleId = _readInt(data['rol_id']);
      if (!_rolPermitido(roleId)) {
        await logout();
        throw _LoginAttemptException(
          statusCode: 403,
          message:
              'Acceso denegado: esta app movil es solo para clientes y tecnicos.',
        );
      }

      await _guardarSesion(data: data, email: email, roleId: roleId!);
      return data;
    } on _LoginAttemptException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Error al iniciar sesión: $e');
    }
  }

  Future<Map<String, dynamic>> _loginConPlataforma({
    required String email,
    required String password,
    required String plataforma,
  }) async {
    final response = await http.post(
      Uri.parse('${apiService.baseUrl}/api/v1/auth/login'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: {
        'username': email,
        'password': password,
        'client_id': plataforma,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw _LoginAttemptException(
      statusCode: response.statusCode,
      message: _readErrorMessage(response),
    );
  }

  Future<void> _guardarSesion({
    required Map<String, dynamic> data,
    required String email,
    required int roleId,
  }) async {
    if (data['access_token'] == null) return;

    final prefs = await SharedPreferences.getInstance();
    final token = data['access_token'] as String;
    await prefs.setString(_tokenKey, token);
    apiService.setAuthToken(token);
    await prefs.setInt(_userRoleKey, roleId);

    final userId = _readInt(data['usuario_id']) ?? _extractUserIdFromToken(token);
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

  bool _debeReintentarComoTecnico(_LoginAttemptException error) {
    final message = error.message.toLowerCase();
    return error.statusCode == 403 && message.contains('solo para clientes');
  }

  bool _rolPermitido(int? roleId) {
    return roleId == clienteRoleId || roleId == tecnicoRoleId;
  }

  String _readErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {
      // Usa el fallback de abajo si el backend no envio JSON.
    }

    return 'Error al iniciar sesion: ${response.statusCode}';
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
    final isValidMobileSession =
        token != null && token.isNotEmpty && _rolPermitido(roleId);

    if (token != null && token.isNotEmpty && !isValidMobileSession) {
      await logout();
    }

    return isValidMobileSession;
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

class _LoginAttemptException implements Exception {
  final int statusCode;
  final String message;

  _LoginAttemptException({required this.statusCode, required this.message});

  @override
  String toString() => message;
}
