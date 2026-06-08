import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../providers/incidente_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vehiculo_provider.dart';
import '../../theme/colors.dart';
import 'map_screen.dart';

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
  final _imagePicker = ImagePicker();
  static const _screenChannel = MethodChannel('app_v/screen');
  static const LatLng _centroInicial = LatLng(-17.783327, -63.182140);

  int? _vehiculoSeleccionado;
  double? _latitud;
  double? _longitud;
  bool _obteniendoUbicacion = false;
  bool _grabandoAudio = false;
  bool _pantallaActivaPorGrabacion = false;
  bool _reproduciendoAudio = false;
  Duration _audioDuration = Duration.zero;
  Timer? _audioTimer;
  StreamSubscription<void>? _audioCompleteSubscription;
  String? _audioPath;
  String? _imagenPath;
  String? _ubicacionError;
  String? _audioError;
  String? _imagenError;

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
              'Imagen del incidente',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildImagePicker(),
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
              const SizedBox(width: 8),
              _buildAudioActionButton(),
            ],
          ),
          if (tieneAudio && !_grabandoAudio) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
            ),
          ],
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

  Widget _buildAudioActionButton() {
    final color = _grabandoAudio ? AppColors.error : AppColors.primaryColor;

    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton.filled(
        onPressed: _grabandoAudio
            ? _detenerGrabacionAudio
            : _iniciarGrabacionAudio,
        icon: Icon(_grabandoAudio ? Icons.stop : Icons.mic),
        tooltip: _grabandoAudio ? 'Detener grabacion' : 'Grabar audio',
        style: IconButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
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
          '${tempDir.path}/incidente_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: path,
      );
      await _activarPantallaDuranteGrabacion();

      _audioTimer?.cancel();
      _audioTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _audioDuration += const Duration(seconds: 1);
        });
      });

      if (!mounted) {
        await _audioRecorder.stop();
        _audioTimer?.cancel();
        await _desactivarPantallaDuranteGrabacion();
        return;
      }
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
      await _desactivarPantallaDuranteGrabacion();

      if (!mounted) return;
      setState(() {
        _grabandoAudio = false;
        _audioPath = path ?? _audioPath;
      });
    } catch (e) {
      await _desactivarPantallaDuranteGrabacion();
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
    await _desactivarPantallaDuranteGrabacion();
    setState(() {
      _audioPath = null;
      _audioDuration = Duration.zero;
      _audioError = null;
      _grabandoAudio = false;
      _reproduciendoAudio = false;
    });
  }

  Future<void> _activarPantallaDuranteGrabacion() async {
    if (_pantallaActivaPorGrabacion) return;

    try {
      await _screenChannel.invokeMethod<void>('keepAwake');
      _pantallaActivaPorGrabacion = true;
    } catch (_) {
      _pantallaActivaPorGrabacion = false;
    }
  }

  Future<void> _desactivarPantallaDuranteGrabacion() async {
    if (!_pantallaActivaPorGrabacion) return;

    try {
      await _screenChannel.invokeMethod<void>('allowSleep');
    } catch (_) {
      // No bloquea el flujo de grabacion si el sistema rechaza liberar el wake lock.
    } finally {
      _pantallaActivaPorGrabacion = false;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildImagePicker() {
    final tieneImagen = _imagenPath != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tieneImagen
            ? AppColors.success.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
        border: Border.all(
          color: tieneImagen ? AppColors.success : Colors.grey.shade400,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                tieneImagen ? Icons.image : Icons.add_photo_alternate_outlined,
                color: tieneImagen ? AppColors.success : Colors.grey.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tieneImagen ? 'Imagen seleccionada' : 'Agrega una imagen',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: tieneImagen ? AppColors.success : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (tieneImagen) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: double.infinity,
                height: 180,
                child: Image.file(File(_imagenPath!), fit: BoxFit.cover),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _seleccionarImagen(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Camara'),
              ),
              OutlinedButton.icon(
                onPressed: () => _seleccionarImagen(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galeria'),
              ),
              if (tieneImagen)
                IconButton(
                  onPressed: _descartarImagen,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Descartar imagen',
                ),
            ],
          ),
          if (_imagenError != null) ...[
            const SizedBox(height: 6),
            Text(
              _imagenError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _seleccionarImagen(ImageSource source) async {
    setState(() {
      _imagenError = null;
    });

    try {
      final imagen = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (!mounted || imagen == null) return;

      setState(() {
        _imagenPath = imagen.path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imagenError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _descartarImagen() {
    setState(() {
      _imagenPath = null;
      _imagenError = null;
    });
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
    final tieneImagen = _imagenPath != null && _imagenPath!.isNotEmpty;

    if (descripcion.isEmpty && !tieneAudio && !tieneImagen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Graba un audio, agrega una imagen o escribe una descripcion.',
          ),
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
      imagenPath: _imagenPath,
    );

    if (!context.mounted) return;
    if (success) {
      final guardadoOffline = incidenteProvider.guardadoOffline;

      if (guardadoOffline) {
        // CU-N03: Sin internet, guardado localmente
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.orange),
                SizedBox(width: 8),
                Text('Sin conexión'),
              ],
            ),
            content: const Text(
              'No se detectó conexión a internet.\n\n'
              'Tu emergencia fue guardada localmente y está marcada como '
              '"Pendiente de sincronización". Se enviará al servidor automáticamente '
              'cuando vuelvas a tener conexión.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        Navigator.of(context).pop();
      } else {
        // Online: mostrar resultado IA y navegar al mapa
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Incidente reportado! Buscando taller...'),
            backgroundColor: Colors.green,
          ),
        );
        await _mostrarResultadoIA(
          context,
          incidenteProvider.ultimoIncidenteReportado,
        );
        if (!context.mounted) return;
        // Navegar al mapa de seguimiento
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MapScreen()),
        );
      }
    }
  }

  Future<void> _mostrarSeleccionTaller(
    BuildContext context,
    IncidenteProvider provider,
    int incidenteId,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final candidatos = await provider.obtenerCotizaciones(incidenteId);

    if (!context.mounted) return;
    Navigator.of(context).pop(); // Cerrar loader

    if (candidatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontraron talleres candidatos.')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Selecciona un Taller',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: candidatos.length,
                    itemBuilder: (ctx, i) {
                      final c = candidatos[i];
                      final distanceStr = c['distancia_km'] != null
                          ? '${c['distancia_km']} km'
                          : 'Distancia desconocida';
                      final rating = c['calificacion_promedio'] ?? 0.0;

                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Icon(Icons.build, color: Colors.white),
                        ),
                        title: Text(c['taller_nombre'] ?? 'Taller'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monto cotizado: ${c['monto'] ?? c['sugerencia_ia_monto'] ?? '0.00'} Bs',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                            Text('Tiempo estimado: ${c['tiempo_estimado'] ?? 'No especificado'}'),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final success = await provider.seleccionarCotizacion(
                              incidenteId: incidenteId,
                              tallerId: c['taller_id'],
                            );
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Taller seleccionado exitosamente.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(provider.errorMessage ?? 'Error al seleccionar taller'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          child: const Text('Elegir'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _mostrarResultadoIA(
    BuildContext context,
    Map<String, dynamic>? incidente,
  ) {
    final categoria = _texto(incidente?['clasificacion_ia']);
    final prioridad = _texto(incidente?['prioridad']);
    final transcripcion = _texto(incidente?['transcripcion_audio']);
    final resumen = _texto(incidente?['resumen_ia']);
    final punto =
        _latLngDesdeValores(incidente?['latitud'], incidente?['longitud']) ??
        (_latitud != null && _longitud != null
            ? LatLng(_latitud!, _longitud!)
            : null);

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
              _buildResultadoRow('Criticidad', _labelPrioridad(prioridad)),
              _buildResultadoRow(
                'Transcripcion',
                transcripcion ?? 'No disponible',
              ),
              _buildResultadoRow('Resumen IA', resumen ?? 'No disponible'),
              if (punto != null) _buildResultadoMapa(punto),
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

  Widget _buildResultadoMapa(LatLng punto) {
    final mapWidth = (MediaQuery.sizeOf(context).width - 96)
        .clamp(180.0, 320.0)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ubicacion',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: mapWidth,
              height: 170,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: punto,
                  initialZoom: 15,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
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
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.location_pin,
                          color: AppColors.error,
                          size: 42,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${punto.latitude.toStringAsFixed(6)}, ${punto.longitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
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

  LatLng? _latLngDesdeValores(dynamic latitud, dynamic longitud) {
    final lat = _toDouble(latitud);
    final lng = _toDouble(longitud);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _labelPrioridad(String? prioridad) {
    switch (prioridad?.toLowerCase()) {
      case 'alta':
        return 'Alta';
      case 'media':
        return 'Media';
      case 'baja':
        return 'Baja';
      default:
        return 'No disponible';
    }
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
    unawaited(_desactivarPantallaDuranteGrabacion());
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
