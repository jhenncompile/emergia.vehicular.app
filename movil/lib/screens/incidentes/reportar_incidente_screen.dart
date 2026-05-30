import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../providers/incidente_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vehiculo_provider.dart';
import '../../theme/colors.dart';

class ReportarIncidenteScreen extends StatefulWidget {
  const ReportarIncidenteScreen({super.key});

  @override
  State<ReportarIncidenteScreen> createState() =>
      _ReportarIncidenteScreenState();
}

class _ReportarIncidenteScreenState extends State<ReportarIncidenteScreen> {
  final _descriptionController = TextEditingController();
  final _mapController = MapController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  static const LatLng _centroInicial = LatLng(-17.783327, -63.182140);

  int? _vehiculoSeleccionado;
  double? _latitud;
  double? _longitud;
  bool _obteniendoUbicacion = false;
  bool _grabandoAudio = false;
  bool _reproduciendoAudio = false;
  Duration _audioDuration = Duration.zero;
  Timer? _audioTimer;
  StreamSubscription<void>? _audioCompleteSubscription;
  String? _audioPath;
  String? _ubicacionError;
  String? _audioError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cargarVehiculos();
    });
    _audioCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _reproduciendoAudio = false;
      });
    });
    Future.microtask(_obtenerUbicacionActual);
  }

  Future<void> _cargarVehiculos() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;

    final vehiculoProvider = context.read<VehiculoProvider>();
    await vehiculoProvider.cargarMisVehiculos(usuarioId: userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar Incidente'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seleccionar vehículo
            Text(
              'Vehículo',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Consumer<VehiculoProvider>(
              builder: (context, vehiculoProvider, _) {
                if (vehiculoProvider.isLoading) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Cargando vehiculos...'),
                      ],
                    ),
                  );
                }

                if (vehiculoProvider.misVehiculos.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'No tienes vehículos registrados. Registra uno primero.',
                    ),
                  );
                }

                return DropdownButton<int>(
                  isExpanded: true,
                  value: _vehiculoSeleccionado,
                  hint: const Text('Selecciona un vehículo'),
                  items: vehiculoProvider.misVehiculos.map((vehiculo) {
                    return DropdownMenuItem<int>(
                      value: vehiculo['id'],
                      child: Text(
                        '${vehiculo['marca']} ${vehiculo['modelo']} - ${vehiculo['placa']}',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _vehiculoSeleccionado = value;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 24),

            Text(
              'Descripción del problema (opcional)',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Puedes escribir detalles extra si quieres...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Audio del incidente',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildAudioRecorder(),
            const SizedBox(height: 24),

            Text(
              'Ubicación del incidente',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildSelectorMapa(),
            const SizedBox(height: 24),

            // Botón Reportar
            Consumer2<IncidenteProvider, AuthProvider>(
              builder: (context, incidenteProvider, authProvider, _) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        incidenteProvider.isLoading ||
                            _obteniendoUbicacion ||
                            _grabandoAudio
                        ? null
                        : () => _reportarIncidente(
                            context,
                            incidenteProvider,
                            authProvider,
                          ),
                    child: incidenteProvider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Reportar Incidente',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                );
              },
            ),

            // Mensaje de error
            Consumer<IncidenteProvider>(
              builder: (context, incidenteProvider, _) {
                if (incidenteProvider.errorMessage != null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        border: Border.all(color: AppColors.error),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        incidenteProvider.errorMessage!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioRecorder() {
    final tieneAudio = _audioPath != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _grabandoAudio
            ? AppColors.error.withValues(alpha: 0.08)
            : tieneAudio
            ? AppColors.success.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
        border: Border.all(
          color: _grabandoAudio
              ? AppColors.error
              : tieneAudio
              ? AppColors.success
              : Colors.grey.shade400,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _grabandoAudio
                    ? Icons.mic
                    : tieneAudio
                    ? Icons.check_circle
                    : Icons.mic_none,
                color: _grabandoAudio
                    ? AppColors.error
                    : tieneAudio
                    ? AppColors.success
                    : Colors.grey.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _grabandoAudio
                      ? 'Grabando ${_formatDuration(_audioDuration)}'
                      : tieneAudio
                      ? 'Audio grabado (${_formatDuration(_audioDuration)})'
                      : 'Agrega un audio opcional',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _grabandoAudio
                        ? AppColors.error
                        : tieneAudio
                        ? AppColors.success
                        : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _grabandoAudio
                    ? _detenerGrabacionAudio
                    : _iniciarGrabacionAudio,
                icon: Icon(_grabandoAudio ? Icons.stop : Icons.mic),
                label: Text(_grabandoAudio ? 'Detener' : 'Grabar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _grabandoAudio
                      ? AppColors.error
                      : AppColors.primaryColor,
                ),
              ),
              if (tieneAudio && !_grabandoAudio) ...[
                OutlinedButton.icon(
                  onPressed: _reproducirOPausarAudio,
                  icon: Icon(
                    _reproduciendoAudio ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(_reproduciendoAudio ? 'Pausar' : 'Escuchar'),
                ),
                IconButton(
                  onPressed: () => _descartarAudio(),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Descartar audio',
                ),
              ],
            ],
          ),
          if (_audioError != null) ...[
            const SizedBox(height: 6),
            Text(
              _audioError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _iniciarGrabacionAudio() async {
    setState(() {
      _audioError = null;
    });

    try {
      await _detenerReproduccionAudio();
      final tienePermiso = await _audioRecorder.hasPermission();
      if (!tienePermiso) {
        throw Exception('Permiso de microfono denegado.');
      }

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/incidente_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      _audioTimer?.cancel();
      _audioTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _audioDuration += const Duration(seconds: 1);
        });
      });

      if (!mounted) return;
      setState(() {
        _grabandoAudio = true;
        _audioPath = path;
        _audioDuration = Duration.zero;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _audioError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _detenerGrabacionAudio() async {
    try {
      final path = await _audioRecorder.stop();
      _audioTimer?.cancel();

      if (!mounted) return;
      setState(() {
        _grabandoAudio = false;
        _audioPath = path ?? _audioPath;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _grabandoAudio = false;
        _audioError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _reproducirOPausarAudio() async {
    final path = _audioPath;
    if (path == null || path.isEmpty) return;

    try {
      setState(() {
        _audioError = null;
      });

      if (_reproduciendoAudio) {
        await _audioPlayer.pause();
        if (!mounted) return;
        setState(() {
          _reproduciendoAudio = false;
        });
        return;
      }

      await _audioPlayer.play(DeviceFileSource(path));
      if (!mounted) return;
      setState(() {
        _reproduciendoAudio = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _audioError = e.toString().replaceFirst('Exception: ', '');
        _reproduciendoAudio = false;
      });
    }
  }

  Future<void> _detenerReproduccionAudio() async {
    if (!_reproduciendoAudio) return;

    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _reproduciendoAudio = false;
    });
  }

  Future<void> _descartarAudio() async {
    _audioTimer?.cancel();
    await _audioPlayer.stop();
    setState(() {
      _audioPath = null;
      _audioDuration = Duration.zero;
      _audioError = null;
      _grabandoAudio = false;
      _reproduciendoAudio = false;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildSelectorMapa() {
    final tieneCoordenadas = _latitud != null && _longitud != null;
    final punto = _puntoSeleccionado;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tieneCoordenadas
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.warning.withValues(alpha: 0.08),
        border: Border.all(
          color: tieneCoordenadas ? AppColors.success : AppColors.warning,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 260,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: punto,
                      initialZoom: 15,
                      onTap: (_, point) => _seleccionarPunto(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.app_v',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: punto,
                            width: 52,
                            height: 52,
                            child: Icon(
                              Icons.location_pin,
                              color: tieneCoordenadas
                                  ? AppColors.error
                                  : Colors.grey,
                              size: 48,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: FloatingActionButton.small(
                      heroTag: 'gps-incidente',
                      onPressed: _obteniendoUbicacion
                          ? null
                          : _obtenerUbicacionActual,
                      child: _obteniendoUbicacion
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                tieneCoordenadas ? Icons.check_circle : Icons.touch_app,
                color: tieneCoordenadas ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tieneCoordenadas
                      ? 'Ubicacion seleccionada'
                      : 'Toca el mapa o usa GPS para seleccionar la ubicacion',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: tieneCoordenadas
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          if (tieneCoordenadas) ...[
            const SizedBox(height: 6),
            Text(
              'Coordenadas: ${_latitud!.toStringAsFixed(6)}, ${_longitud!.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          if (_ubicacionError != null) ...[
            const SizedBox(height: 6),
            Text(
              _ubicacionError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  LatLng get _puntoSeleccionado {
    if (_latitud != null && _longitud != null) {
      return LatLng(_latitud!, _longitud!);
    }
    return _centroInicial;
  }

  void _seleccionarPunto(LatLng punto) {
    setState(() {
      _latitud = punto.latitude;
      _longitud = punto.longitude;
      _ubicacionError = null;
    });
  }

  Future<void> _obtenerUbicacionActual() async {
    if (_obteniendoUbicacion) return;

    setState(() {
      _obteniendoUbicacion = true;
      _ubicacionError = null;
    });

    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        throw Exception(
          'Activa el GPS del celular para reportar el incidente.',
        );
      }

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }

      if (permiso == LocationPermission.denied) {
        throw Exception('Permiso de ubicacion denegado.');
      }

      if (permiso == LocationPermission.deniedForever) {
        throw Exception(
          'Permiso de ubicacion bloqueado. Habilitalo desde ajustes.',
        );
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;
      setState(() {
        _latitud = posicion.latitude;
        _longitud = posicion.longitude;
        _ubicacionError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(LatLng(posicion.latitude, posicion.longitude), 16);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ubicacionError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _obteniendoUbicacion = false;
        });
      }
    }
  }

  void _reportarIncidente(
    BuildContext context,
    IncidenteProvider incidenteProvider,
    AuthProvider authProvider,
  ) async {
    if (_vehiculoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona un vehículo')),
      );
      return;
    }

    final descripcion = _descriptionController.text.trim();
    final tieneAudio = _audioPath != null && _audioPath!.isNotEmpty;

    if (descripcion.isEmpty && !tieneAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Graba un audio o escribe una descripcion.'),
        ),
      );
      return;
    }

    final usuarioId = authProvider.userId;
    if (usuarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesion invalida. Inicia sesion nuevamente.'),
        ),
      );
      return;
    }

    if (_latitud == null || _longitud == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Obteniendo ubicacion GPS...')),
      );
      await _obtenerUbicacionActual();
      if (!context.mounted) return;

      if (_latitud == null || _longitud == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _ubicacionError ?? 'No se pudo obtener la ubicacion GPS.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    final success = await incidenteProvider.reportarIncidente(
      usuarioId: usuarioId,
      vehiculoId: _vehiculoSeleccionado!,
      descripcion: descripcion,
      ubicacion: 'Ubicacion seleccionada en mapa',
      latitud: _latitud!,
      longitud: _longitud!,
      audioPath: _audioPath,
    );

    if (!context.mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Incidente reportado exitosamente!'),
          backgroundColor: Colors.green,
        ),
      );
      await _mostrarResultadoIA(
        context,
        incidenteProvider.ultimoIncidenteReportado,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _mostrarResultadoIA(
    BuildContext context,
    Map<String, dynamic>? incidente,
  ) {
    final categoria = _texto(incidente?['clasificacion_ia']);
    final transcripcion = _texto(incidente?['transcripcion_audio']);
    final resumen = _texto(incidente?['resumen_ia']);

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Incidente reportado'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildResultadoRow('Categoria IA', categoria ?? 'No disponible'),
              _buildResultadoRow(
                'Transcripcion',
                transcripcion ?? 'No disponible',
              ),
              _buildResultadoRow('Resumen IA', resumen ?? 'No disponible'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultadoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  String? _texto(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  @override
  void dispose() {
    _audioTimer?.cancel();
    _audioCompleteSubscription?.cancel();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
