import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/incidente_service.dart';
import 'offline_incidente_service.dart';

/// Estados de sincronización de un incidente local.
enum EstadoSync { pendiente, sincronizando, sincronizado, error }

/// Resultado de un intento de sincronización.
class ResultadoSync {
  final int totalPendientes;
  final int sincronizados;
  final int errores;

  const ResultadoSync({
    required this.totalPendientes,
    required this.sincronizados,
    required this.errores,
  });
}

/// Servicio que detecta la reconexión a internet y sincroniza los
/// incidentes guardados offline. Implementa el flujo de CU-N04.
class SyncService extends ChangeNotifier {
  final IncidenteService incidenteService;
  final VoidCallback? onSyncComplete;

  Timer? _timer;
  bool _sincronizando = false;
  int _pendientesCount = 0;
  String? _ultimoErrorSync;

  // Suscripción a cambios de conectividad
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _estabaOffline = false;

  static const String _kSyncStatusKey = 'sync_status_map';

  SyncService({required this.incidenteService, this.onSyncComplete});

  bool get sincronizando => _sincronizando;
  int get pendientesCount => _pendientesCount;
  String? get ultimoErrorSync => _ultimoErrorSync;

  /// Inicia el monitoreo periódico para detectar reconexión.
  /// Lanza un intento de sync cada 30 segundos mientras haya pendientes.
  /// Además escucha cambios de red para sincronizar al reconectarse.
  void iniciarMonitoreo() {
    _prepararEstadoInicial();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_pendientesCount > 0) {
        await intentarSincronizar();
      }
    });

    // Escuchar reconexión para sincronizar inmediatamente
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) async {
        final hayConexion = _hayConexion(results);
        await refrescarPendientes();
        if (hayConexion && _estabaOffline && _pendientesCount > 0) {
          // Se reconectó con pendientes: sincronizar automáticamente
          await intentarSincronizar();
        }
        _estabaOffline = !hayConexion;
      },
    );
  }

  void detenerMonitoreo() {
    _timer?.cancel();
    _timer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  @override
  void dispose() {
    detenerMonitoreo();
    super.dispose();
  }

  Future<void> _prepararEstadoInicial() async {
    await refrescarPendientes();
    final results = await Connectivity().checkConnectivity();
    final hayConexion = _hayConexion(results);
    _estabaOffline = !hayConexion;
    if (hayConexion && _pendientesCount > 0) {
      await intentarSincronizar();
    }
  }

  bool _hayConexion(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  /// Recalcula los incidentes pendientes y notifica a la UI inmediatamente.
  Future<void> refrescarPendientes() => _actualizarContador();

  /// Actualiza el contador de pendientes sin sincronizar.
  Future<void> _actualizarContador() async {
    final todos = await OfflineIncidenteService.obtenerPendientes();
    final pendientesReales = todos.where((inc) => inc['estado'] != 'sincronizado').toList();
    _pendientesCount = pendientesReales.length;
    notifyListeners();
  }

  /// Intenta sincronizar todos los incidentes pendientes.
  /// Devuelve el resultado con estadísticas de la sincronización.
  Future<ResultadoSync> intentarSincronizar({int? usuarioId}) async {
    if (_sincronizando) {
      return const ResultadoSync(totalPendientes: 0, sincronizados: 0, errores: 0);
    }

    final todos = await OfflineIncidenteService.obtenerPendientes();
    final pendientes = todos.where((inc) => inc['estado'] != 'sincronizado').toList();

    if (pendientes.isEmpty) {
      _pendientesCount = 0;
      notifyListeners();
      return const ResultadoSync(totalPendientes: 0, sincronizados: 0, errores: 0);
    }

    _sincronizando = true;
    _ultimoErrorSync = null;
    notifyListeners();

    int sincronizados = 0;
    int errores = 0;

    for (final incidente in List.from(pendientes)) {
      final idLocal = incidente['id'] as int;
      await _marcarEstado(idLocal, EstadoSync.sincronizando);
      notifyListeners();

      try {
        await incidenteService.reportarIncidente(
          usuarioId: incidente['usuario_id'] as int,
          vehiculoId: incidente['vehiculo_id'] as int,
          descripcion: incidente['descripcion'] as String,
          ubicacion: incidente['ubicacion'] as String,
          latitud: (incidente['latitud'] as num).toDouble(),
          longitud: (incidente['longitud'] as num).toDouble(),
          audioPath: incidente['audio_path'] as String?,
          imagenPath: incidente['imagen_path'] as String?,
        );

        // Éxito: marcar como sincronizado en lugar de eliminarlo
        await OfflineIncidenteService.marcarComoSincronizado(idLocal);
        await _marcarEstado(idLocal, EstadoSync.sincronizado);
        sincronizados++;
      } catch (e) {
        // Error: puede ser sin conexión todavía u otro error
        await _marcarEstado(idLocal, EstadoSync.error);
        _ultimoErrorSync = e.toString();
        errores++;
      }
    }

    await _actualizarContador();
    _sincronizando = false;
    notifyListeners();

    if (sincronizados > 0) {
      onSyncComplete?.call();
    }

    return ResultadoSync(
      totalPendientes: pendientes.length,
      sincronizados: sincronizados,
      errores: errores,
    );
  }

  /// Guarda el estado de sincronización para un ID local.
  Future<void> _marcarEstado(int idLocal, EstadoSync estado) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSyncStatusKey) ?? '{}';
    final Map<String, dynamic> mapa = Map.from(jsonDecode(raw));
    mapa[idLocal.toString()] = estado.name;
    await prefs.setString(_kSyncStatusKey, jsonEncode(mapa));
  }

  /// Obtiene el estado de sincronización para un ID local.
  static Future<EstadoSync> obtenerEstado(int idLocal) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('sync_status_map') ?? '{}';
    final mapa = jsonDecode(raw) as Map<String, dynamic>;
    final nombre = mapa[idLocal.toString()] as String?;
    if (nombre == null) return EstadoSync.pendiente;
    return EstadoSync.values.firstWhere(
      (e) => e.name == nombre,
      orElse: () => EstadoSync.pendiente,
    );
  }

  /// Reintenta la sincronización de un incidente específico.
  Future<bool> reintentar(int idLocal) async {
    final pendientes = await OfflineIncidenteService.obtenerPendientes();
    final incidente = pendientes.where((i) => i['id'] == idLocal).firstOrNull;
    if (incidente == null) return false;

    await _marcarEstado(idLocal, EstadoSync.sincronizando);
    notifyListeners();

    try {
      await incidenteService.reportarIncidente(
        usuarioId: incidente['usuario_id'] as int,
        vehiculoId: incidente['vehiculo_id'] as int,
        descripcion: incidente['descripcion'] as String,
        ubicacion: incidente['ubicacion'] as String,
        latitud: (incidente['latitud'] as num).toDouble(),
        longitud: (incidente['longitud'] as num).toDouble(),
        audioPath: incidente['audio_path'] as String?,
        imagenPath: incidente['imagen_path'] as String?,
      );
      await OfflineIncidenteService.eliminarPendiente(idLocal);
      await _marcarEstado(idLocal, EstadoSync.sincronizado);
      await _actualizarContador();
      notifyListeners();
      return true;
    } catch (e) {
      await _marcarEstado(idLocal, EstadoSync.error);
      _ultimoErrorSync = e.toString();
      notifyListeners();
      return false;
    }
  }
}
