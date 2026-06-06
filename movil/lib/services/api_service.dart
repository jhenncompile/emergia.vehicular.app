import 'dart:convert';
import 'package:http/http.dart' as http; // Para hacer peticiones HTTP
import 'package:shared_preferences/shared_preferences.dart';

/// ApiService: Cliente HTTP genérico para comunicarse con el Backend (FastAPI)
///
/// FLUJO DE FUNCIONAMIENTO:
/// 1. La aplicación Flutter (app_v) usa este servicio para enviar peticiones HTTP al backend en Python
/// 2. El backend (FastAPI) está configurado en: http://localhost:5000 (o tu URL de backend)
/// 3. Todos los endpoints del backend tienen prefijo: /api/v1/
///
/// ENDPOINTS DISPONIBLES EN EL BACKEND:
/// - /auth/login              → Autenticación y generación de JWT token
/// - /incidentes/             → CRUD de incidentes reportados
/// - /usuarios/               → Gestión de usuarios
/// - /talleres/               → Gestión de talleres
/// - /vehiculos/              → CRUD de vehículos
/// - /pagos/                  → Registro de transacciones
/// - /bitacora/               → Registro de auditoría
///
/// FLUJO DE AUTENTICACIÓN:
/// 1. Usuario inicia sesión → POST /auth/login (correo, contraseña, platform)
/// 2. Backend valida y retorna JWT token
/// 3. El token se almacena localmente en la app
/// 4. Todas las siguientes peticiones incluyen el token en header: "Authorization: Bearer {token}"
///
class ApiService {
  ApiService({required this.baseUrl, this.getToken, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;

  /// getToken: Función que obtiene el JWT almacenado localmente
  /// Se ejecuta antes de cada petición para incluir autenticación
  final Future<String?> Function()? getToken;
  final http.Client _client;
  String? _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
  }

  Future<String?> currentAuthToken() async {
    String? token = _authToken;
    token ??= await getToken?.call();
    token ??= (await SharedPreferences.getInstance()).getString('auth_token');
    _authToken = token;
    return token;
  }

  // Construye la URI completa para la petición, incluyendo los parámetros de consulta si se proporcionan
  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';

    return Uri.parse('$cleanBase$cleanPath').replace(
      queryParameters: queryParams?.map(
        (key, value) => MapEntry(key, '$value'),
      ),
    );
  }

  /// Construye los Headers HTTP necesarios para la petición
  /// - Content-Type: 'application/json' (si es JSON)
  /// - Accept: 'application/json' (especifica que espera JSON como respuesta)
  /// - Authorization: 'Bearer {token}' (incluye JWT para autenticación)
  ///
  /// Ej: Un petición POST a /incidentes/ llevará el header:
  ///     Authorization: Bearer eyJhbGciOiJIUzI1NiI...
  Future<Map<String, String>> _headers({bool jsonContent = true}) async {
    final token = await currentAuthToken();

    return {
      if (jsonContent) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// GET: Obtiene datos del backend
  /// Ej: var incidentes = await apiService.get('/incidentes/pendientes');
  ///     → GET http://localhost:5000/api/v1/incidentes/pendientes
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParams}) async {
    final response = await _client.get(
      _buildUri(path, queryParams),
      headers: await _headers(),
    );

    return _handleResponse(response);
  }

  /// POST: Crea nuevos recursos en el backend
  /// Ej: var nuevoIncidente = await apiService.post('/incidentes/', body: {
  ///       'usuario_id': 1,
  ///       'descripcion': 'Vehículo averiado en carretera',
  ///       'ubicacion': '...',
  ///     });
  ///     → POST http://localhost:5000/api/v1/incidentes/
  ///     → Body: JSON con los datos del incidente
  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
  }) async {
    final response = await _client.post(
      _buildUri(path, queryParams),
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );

    return _handleResponse(response);
  }

  /// PUT: Actualiza recursos existentes en el backend
  /// Ej: var incidenteActualizado = await apiService.put('/incidentes/5', body: {
  ///       'estado': 'en_camino',
  ///       'taller_id': 3,
  ///     });
  ///     → PUT http://localhost:5000/api/v1/incidentes/5
  Future<dynamic> put(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
  }) async {
    final response = await _client.put(
      _buildUri(path, queryParams),
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );

    return _handleResponse(response);
  }

  /// DELETE: Elimina recursos en el backend
  /// Ej: await apiService.delete('/incidentes/5');
  ///     → DELETE http://localhost:5000/api/v1/incidentes/5
  Future<dynamic> delete(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
  }) async {
    final response = await _client.delete(
      _buildUri(path, queryParams),
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );

    return _handleResponse(response);
  }

  /// PATCH: Actualización parcial de recursos en el backend
  /// Ej: var notificacionLeida = await apiService.patch('/notificaciones/5/leer');
  ///     → PATCH http://localhost:5000/api/v1/notificaciones/5/leer
  Future<dynamic> patch(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
  }) async {
    final response = await _client.patch(
      _buildUri(path, queryParams),
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );

    return _handleResponse(response);
  }

  /// Procesa la respuesta HTTP del backend
  /// - Códigos 200-299: Éxito  ✓ Decodifica JSON y retorna
  /// - Códigos 400-599: Error ✗ Lanza excepción con mensaje descriptivo
  ///
  /// Ej: Si el backend retorna 422 (datos inválidos)
  ///     Lanza: "Error 422: {detalle del error}"
  dynamic _handleResponse(http.Response response) {
    return handleRawResponse(response);
  }

  dynamic handleRawResponse(http.Response response) {
    final body = response.body.isNotEmpty ? response.body : null;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body == null) return null;

      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    }

    throw Exception(
      'Error ${response.statusCode}: ${body ?? 'Respuesta vacía'}',
    );
  }

  void dispose() {
    _client.close();
  }
}
