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
    String prioridad = 'media',
    String telefonoCliente = 'No disponible',
  }) async {
    if (audioPath != null && audioPath.isNotEmpty) {
      return _reportarIncidenteConAudio(
        usuarioId: usuarioId,
        vehiculoId: vehiculoId,
        descripcion: descripcion,
        ubicacion: ubicacion,
        latitud: latitud,
        longitud: longitud,
        audioPath: audioPath,
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

  Future<Map<String, dynamic>> _reportarIncidenteConAudio({
    required int usuarioId,
    required int vehiculoId,
    required String descripcion,
    required String ubicacion,
    required double latitud,
    required double longitud,
    required String audioPath,
  }) async {
    try {
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        throw Exception('No se encontro el audio grabado.');
      }

      final uri = Uri.parse(
        '${apiService.baseUrl}/api/v1/incidentes/reportar-audio',
      );
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

      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          audioPath,
          contentType: MediaType('audio', 'mp4'),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final parsed = apiService.handleRawResponse(response);

      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      throw Exception('Respuesta inesperada del servidor');
    } catch (e) {
      throw Exception('Error al reportar incidente con audio: $e');
    }
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
