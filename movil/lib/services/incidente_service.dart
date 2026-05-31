import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_service.dart';

/// Servicio para gestionar incidentes del usuario movil.
class IncidenteService {
  final ApiService apiService;

  IncidenteService({required this.apiService});

  Future<Map<String, dynamic>> reportarIncidente({
    required int usuarioId,
    required int vehiculoId,
    required String descripcion,
    required String ubicacion,
    required double latitud,
    required double longitud,
    String? audioPath,
    String? imagenPath,
    String prioridad = 'media',
    String telefonoCliente = 'No disponible',
  }) async {
    final tieneAudio = audioPath != null && audioPath.isNotEmpty;
    final tieneImagen = imagenPath != null && imagenPath.isNotEmpty;

    if (tieneAudio || tieneImagen) {
      return _reportarIncidenteConEvidencias(
        usuarioId: usuarioId,
        vehiculoId: vehiculoId,
        descripcion: descripcion,
        ubicacion: ubicacion,
        latitud: latitud,
        longitud: longitud,
        audioPath: audioPath,
        imagenPath: imagenPath,
      );
    }

    try {
      final response = await apiService.post(
        '/api/v1/incidentes/',
        body: {
          'usuario_id': usuarioId,
          'vehiculo_id': vehiculoId,
          'descripcion': descripcion,
          'ubicacion': ubicacion,
          'latitud': latitud,
          'longitud': longitud,
          'prioridad': prioridad,
          'estado': 'pendiente',
          'pago_estado': 'pendiente',
          'telefono_cliente': telefonoCliente,
        },
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al reportar incidente: $e');
    }
  }

  Future<Map<String, dynamic>> _reportarIncidenteConEvidencias({
    required int usuarioId,
    required int vehiculoId,
    required String descripcion,
    required String ubicacion,
    required double latitud,
    required double longitud,
    String? audioPath,
    String? imagenPath,
  }) async {
    try {
      final tieneAudio = audioPath != null && audioPath.isNotEmpty;
      final tieneImagen = imagenPath != null && imagenPath.isNotEmpty;

      if (tieneAudio && !await File(audioPath).exists()) {
        throw Exception('No se encontro el audio grabado.');
      }

      if (tieneImagen && !await File(imagenPath).exists()) {
        throw Exception('No se encontro la imagen seleccionada.');
      }

      final uri = Uri.parse('${apiService.baseUrl}/api/v1/incidentes/reportar');
      final request = http.MultipartRequest('POST', uri);
      final token = await apiService.currentAuthToken();

      request.headers.addAll({
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      });

      request.fields.addAll({
        'usuario_id': '$usuarioId',
        'vehiculo_id': '$vehiculoId',
        'descripcion': descripcion,
        'ubicacion': ubicacion,
        'latitud': '$latitud',
        'longitud': '$longitud',
      });

      if (tieneAudio) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'audio',
            audioPath,
            contentType: _mediaTypeAudio(audioPath),
          ),
        );
      }

      if (tieneImagen) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'imagen',
            imagenPath,
            contentType: _mediaTypeImagen(imagenPath),
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final parsed = apiService.handleRawResponse(response);

      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al reportar incidente con evidencias: $e');
    }
  }

  MediaType _mediaTypeImagen(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (lowerPath.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }
    return MediaType('image', 'jpeg');
  }

  MediaType _mediaTypeAudio(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.wav')) {
      return MediaType('audio', 'wav');
    }
    if (lowerPath.endsWith('.flac')) {
      return MediaType('audio', 'flac');
    }
    if (lowerPath.endsWith('.mp3') || lowerPath.endsWith('.mpeg')) {
      return MediaType('audio', 'mpeg');
    }
    if (lowerPath.endsWith('.ogg') || lowerPath.endsWith('.opus')) {
      return MediaType('audio', 'ogg');
    }
    return MediaType('audio', 'wav');
  }

  /// Backend disponible: lista pendientes globales.
  Future<List<Map<String, dynamic>>> obtenerIncidentesPendientes() async {
    try {
      final response = await apiService.get('/api/v1/incidentes/pendientes');

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
      throw Exception('Error al obtener incidentes pendientes: $e');
    }
  }

  Future<List<Map<String, dynamic>>> obtenerMisIncidentes() async {
    try {
      final response = await apiService.get(
        '/api/v1/incidentes/mis-incidentes',
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
      throw Exception('Error al obtener mis incidentes: $e');
    }
  }

  Future<List<Map<String, dynamic>>> obtenerEvidenciasPorIncidente({
    required int incidenteId,
  }) async {
    try {
      final response = await apiService.get(
        '/api/v1/evidencias/incidente/$incidenteId',
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
      throw Exception('Error al obtener evidencias: $e');
    }
  }

  String resolverUrlArchivo(String? urlArchivo) {
    final url = urlArchivo?.trim();
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;

    final cleanBase = apiService.baseUrl.endsWith('/')
        ? apiService.baseUrl.substring(0, apiService.baseUrl.length - 1)
        : apiService.baseUrl;
    final cleanPath = url.startsWith('/') ? url : '/$url';
    return '$cleanBase$cleanPath';
  }

  Future<Map<String, dynamic>> crearEvidencia({
    required int incidenteId,
    required int usuarioId,
    required String tipoArchivo,
    required String urlArchivo,
  }) async {
    try {
      final response = await apiService.post(
        '/api/v1/evidencias/',
        queryParams: {'usuario_id': usuarioId},
        body: {
          'incidente_id': incidenteId,
          'tipo_archivo': tipoArchivo,
          'url_archivo': urlArchivo,
        },
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al crear evidencia: $e');
    }
  }
}
