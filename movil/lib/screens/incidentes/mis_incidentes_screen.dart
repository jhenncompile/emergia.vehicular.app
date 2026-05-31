import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../../providers/incidente_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/incidente_service.dart';
import '../../theme/colors.dart';

class MisIncidentesScreen extends StatefulWidget {
  const MisIncidentesScreen({super.key});

  @override
  State<MisIncidentesScreen> createState() => _MisIncidentesScreenState();
}

class _MisIncidentesScreenState extends State<MisIncidentesScreen> {
  @override
  void initState() {
    super.initState();
    // Cargar incidentes al abrir la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = context.read<AuthProvider>().userId;
      if (userId != null) {
        context.read<IncidenteProvider>().cargarMisIncidentes(
          usuarioId: userId,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Incidentes'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer<IncidenteProvider>(
        builder: (context, incidenteProvider, _) {
          if (incidenteProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (incidenteProvider.misIncidentes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes incidentes reportados',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: incidenteProvider.misIncidentes.length,
            itemBuilder: (context, index) {
              final incidente = incidenteProvider.misIncidentes[index];
              return _buildIncidenteCard(context, incidente);
            },
          );
        },
      ),
    );
  }

  Widget _buildIncidenteCard(
    BuildContext context,
    Map<String, dynamic> incidente,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con ID y Estado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Incidente #${incidente['id']}',
                  style: Theme.of(
                    context,
                  ).textTheme.displayLarge?.copyWith(fontSize: 14),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getColorEstado(incidente['estado']),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    incidente['estado']?.toString().toUpperCase() ??
                        'PENDIENTE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Descripción
            Text(
              _textoIncidente(incidente) ?? 'Sin descripción',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),

            // Vehículo
            Row(
              children: [
                const Icon(
                  Icons.directions_car,
                  size: 16,
                  color: AppColors.secondaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  incidente['vehiculo']?['placa'] ?? 'Vehículo desconocido',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Ubicación
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: AppColors.secondaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    incidente['ubicacion'] ?? 'Ubicación desconocida',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Fecha
            Text(
              'Reportado el: ${_formatearFecha(_fechaIncidente(incidente))}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            // Botón de ver detalles
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _verDetalles(context, incidente),
                child: const Text('Ver Detalles'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorEstado(String? estado) {
    switch (estado?.toLowerCase()) {
      case 'pendiente':
        return Colors.orange;
      case 'en_proceso':
      case 'en proceso':
        return Colors.blue;
      case 'atendido':
      case 'completado':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatearFecha(dynamic fecha) {
    if (fecha == null) return 'Fecha desconocida';
    try {
      final dateTime = DateTime.parse(fecha.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return fecha.toString();
    }
  }

  void _verDetalles(BuildContext context, Map<String, dynamic> incidente) {
    final punto = _latLngDesdeValores(
      incidente['latitud'],
      incidente['longitud'],
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Incidente #${incidente['id']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetalleRow(
                'Estado',
                incidente['estado']?.toString().toUpperCase() ?? 'N/A',
              ),
              _buildDetalleRow(
                'Criticidad',
                _labelPrioridad(_texto(incidente['prioridad'])),
              ),
              _buildDetalleRow(
                'Descripción',
                _texto(incidente['descripcion']) ?? 'N/A',
              ),
              if (_texto(incidente['clasificacion_ia']) != null)
                _buildDetalleRow(
                  'Categoria IA',
                  _texto(incidente['clasificacion_ia'])!,
                ),
              if (_texto(incidente['transcripcion_audio']) != null)
                _buildDetalleRow(
                  'Transcripcion',
                  _texto(incidente['transcripcion_audio'])!,
                ),
              if (_texto(incidente['resumen_ia']) != null)
                _buildDetalleRow(
                  'Resumen IA',
                  _texto(incidente['resumen_ia'])!,
                ),
              if (punto != null)
                _buildDetalleMapa(punto)
              else
                _buildDetalleRow('Ubicación', incidente['ubicacion'] ?? 'N/A'),
              _EvidenciasIncidenteSection(
                incidenteId: incidente['id'] is int ? incidente['id'] as int : 0,
                incidenteService: context.read<IncidenteProvider>().incidenteService,
              ),
              _buildDetalleRow(
                'Vehículo',
                incidente['vehiculo']?['placa'] ?? 'N/A',
              ),
              _buildDetalleRow(
                'Fecha',
                _formatearFecha(_fechaIncidente(incidente)),
              ),
              if (incidente['taller'] != null)
                _buildDetalleRow(
                  'Taller Asignado',
                  incidente['taller']['nombre'] ?? 'N/A',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalleMapa(LatLng punto) {
    final mapWidth = (MediaQuery.sizeOf(context).width - 96)
        .clamp(180.0, 320.0)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ubicación',
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

  Widget _buildDetalleRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

  String? _textoIncidente(Map<String, dynamic> incidente) {
    return _texto(incidente['descripcion']) ??
        _texto(incidente['transcripcion_audio']) ??
        _texto(incidente['resumen_ia']);
  }

  dynamic _fechaIncidente(Map<String, dynamic> incidente) {
    return incidente['fecha_creacion'] ?? incidente['fecha_reporte'];
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
}

class _EvidenciasIncidenteSection extends StatefulWidget {
  const _EvidenciasIncidenteSection({
    required this.incidenteId,
    required this.incidenteService,
  });

  final int incidenteId;
  final IncidenteService incidenteService;

  @override
  State<_EvidenciasIncidenteSection> createState() =>
      _EvidenciasIncidenteSectionState();
}

class _EvidenciasIncidenteSectionState
    extends State<_EvidenciasIncidenteSection> {
  late final Future<List<Map<String, dynamic>>> _futureEvidencias;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _audioUrlActivo;

  @override
  void initState() {
    super.initState();
    _futureEvidencias = widget.incidenteId <= 0
        ? Future.value(<Map<String, dynamic>>[])
        : widget.incidenteService.obtenerEvidenciasPorIncidente(
            incidenteId: widget.incidenteId,
          );

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _audioUrlActivo = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evidencias',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _futureEvidencias,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 32,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Text(
                  'No se pudieron cargar las evidencias.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                );
              }

              final evidencias = snapshot.data ?? [];
              if (evidencias.isEmpty) {
                return const Text(
                  'Sin evidencias cargadas.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                );
              }

              return Column(
                children: evidencias
                    .map((evidencia) => _buildEvidencia(context, evidencia))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEvidencia(
    BuildContext context,
    Map<String, dynamic> evidencia,
  ) {
    final tipo = evidencia['tipo_archivo']?.toString().toLowerCase() ?? '';
    final url = widget.incidenteService.resolverUrlArchivo(
      evidencia['url_archivo']?.toString(),
    );

    if (tipo == 'imagen') {
      return _buildImagen(context, url);
    }
    if (tipo == 'audio') {
      return _buildAudio(url);
    }

    return const SizedBox.shrink();
  }

  Widget _buildImagen(BuildContext context, String url) {
    final mapWidth = (MediaQuery.sizeOf(context).width - 96)
        .clamp(180.0, 320.0)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _mostrarImagen(context, url),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: mapWidth,
            height: 170,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildArchivoNoDisponible(
                Icons.broken_image_outlined,
                'Imagen no disponible',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudio(String url) {
    final reproduciendo = _audioUrlActivo == url;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _alternarAudio(url),
            icon: Icon(reproduciendo ? Icons.pause : Icons.play_arrow),
            tooltip: reproduciendo ? 'Pausar audio' : 'Reproducir audio',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reproduciendo ? 'Reproduciendo audio' : 'Audio del reporte',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivoNoDisponible(IconData icon, String text) {
    return Container(
      color: Colors.grey.shade100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _alternarAudio(String url) async {
    if (url.isEmpty) return;

    if (_audioUrlActivo == url) {
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _audioUrlActivo = null;
      });
      return;
    }

    await _audioPlayer.stop();
    await _audioPlayer.play(UrlSource(url));
    if (!mounted) return;
    setState(() {
      _audioUrlActivo = url;
    });
  }

  void _mostrarImagen(BuildContext context, String url) {
    if (url.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildArchivoNoDisponible(
              Icons.broken_image_outlined,
              'Imagen no disponible',
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
