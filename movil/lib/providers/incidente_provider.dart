import 'package:flutter/material.dart';
import '../services/incidente_service.dart';

class IncidenteProvider extends ChangeNotifier {
  final IncidenteService incidenteService;

  List<Map<String, dynamic>> _misIncidentes = [];
  final List<Map<String, dynamic>> _localIncidentes = [];
  Map<String, dynamic>? _incidenteSeleccionado;
  Map<String, dynamic>? _ultimoIncidenteReportado;
  bool _isLoading = false;
  String? _errorMessage;
  final Map<int, Map<String, double>> _ubicacionTecnicosEnVivo = {};

  IncidenteProvider({required this.incidenteService});

  // Getters
  List<Map<String, dynamic>> get misIncidentes => _misIncidentes;
  Map<String, dynamic>? get incidenteSeleccionado => _incidenteSeleccionado;
  Map<String, dynamic>? get ultimoIncidenteReportado =>
      _ultimoIncidenteReportado;
  
  Map<String, dynamic>? get incidenteActivoCliente {
    final index = _misIncidentes.indexWhere((inc) {
      final estado = (inc['estado'] ?? '').toString().toLowerCase();
      return estado == 'pendiente' ||
          estado == 'buscando_taller' ||
          estado == 'asignado_taller' ||
          estado == 'en_camino' ||
          estado == 'en_atencion';
    });
    return index != -1 ? _misIncidentes[index] : null;
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Map<String, double>? getUbicacionTecnicoEnVivo(int incidenteId) {
    return _ubicacionTecnicosEnVivo[incidenteId];
  }

  void actualizarUbicacionTecnico(int incidenteId, double lat, double lng) {
    _ubicacionTecnicosEnVivo[incidenteId] = {'lat': lat, 'lng': lng};
    notifyListeners();
  }

  /// Cargar mis incidentes
  Future<void> cargarMisIncidentes({
    required int usuarioId,
    bool esTecnico = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final remotosUsuario = esTecnico
          ? await incidenteService.obtenerIncidentesTecnico()
          : await incidenteService.obtenerMisIncidentes();

      final combinados = esTecnico
          ? remotosUsuario
          : [..._localIncidentes, ...remotosUsuario];
      final Map<int, Map<String, dynamic>> porId = {};
      for (final incidente in combinados) {
        final id = incidente['id'];
        if (id is int) {
          porId[id] = incidente;
        }
      }

      _misIncidentes = porId.values.toList()
        ..sort((a, b) {
          final idA = a['id'] is int ? a['id'] as int : 0;
          final idB = b['id'] is int ? b['id'] as int : 0;
          return idB.compareTo(idA);
        });
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reportar un nuevo incidente
  Future<bool> reportarIncidente({
    required int usuarioId,
    required int vehiculoId,
    required String descripcion,
    required String ubicacion,
    required double latitud,
    required double longitud,
    String? audioPath,
    String? imagenPath,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final nuevoIncidente = await incidenteService.reportarIncidente(
        usuarioId: usuarioId,
        vehiculoId: vehiculoId,
        descripcion: descripcion,
        ubicacion: ubicacion,
        latitud: latitud,
        longitud: longitud,
        audioPath: audioPath,
        imagenPath: imagenPath,
      );

      _ultimoIncidenteReportado = nuevoIncidente;
      _localIncidentes.insert(0, nuevoIncidente);
      _misIncidentes.insert(0, nuevoIncidente);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Obtener detalles de un incidente
  Future<void> obtenerIncidente({required int id}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _incidenteSeleccionado = _misIncidentes.firstWhere(
        (inc) => inc['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Actualizar estado del incidente
  void actualizarEstadoLocal({required int id, required String estado}) {
    final index = _misIncidentes.indexWhere((inc) => inc['id'] == id);
    if (index != -1) {
      _misIncidentes[index] = {..._misIncidentes[index], 'estado': estado};
      notifyListeners();
    }
  }

  Future<bool> cancelarIncidente({
    required int incidenteId,
    required String motivo,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final actualizado = await incidenteService.cancelarIncidente(
        incidenteId: incidenteId,
        motivo: motivo,
      );

      final index = _misIncidentes.indexWhere((inc) => inc['id'] == incidenteId);
      if (index != -1) {
        _misIncidentes[index] = actualizado;
      }
      _incidenteSeleccionado = actualizado;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Obtener lista de talleres candidatos para un incidente
  Future<List<Map<String, dynamic>>> obtenerCandidatos(int incidenteId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final candidatos = await incidenteService.obtenerCandidatos(incidenteId);
      _isLoading = false;
      notifyListeners();
      return candidatos;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return [];
    }
  }

  /// Seleccionar manualmente el taller para el incidente
  Future<bool> seleccionarTaller({
    required int incidenteId,
    required int tallerId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await incidenteService.seleccionarTaller(
        incidenteId: incidenteId,
        tallerId: tallerId,
      );
      // Actualizar estado local a BUSCANDO_TALLER
      actualizarEstadoLocal(id: incidenteId, estado: 'buscando_taller');
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void limpiar() {
    _misIncidentes = [];
    _localIncidentes.clear();
    _incidenteSeleccionado = null;
    _ultimoIncidenteReportado = null;
    _errorMessage = null;
  }
}
