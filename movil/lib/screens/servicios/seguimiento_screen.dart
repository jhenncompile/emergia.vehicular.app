import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../providers/tecnico_provider.dart';

class SeguimientoScreen extends StatefulWidget {
  const SeguimientoScreen({super.key, required this.incidente});

  final Map<String, dynamic> incidente;

  @override
  State<SeguimientoScreen> createState() => _SeguimientoScreenState();
}

class _SeguimientoScreenState extends State<SeguimientoScreen> {
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Iniciar tracking después del frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<TecnicoProvider>();
      if (!provider.isTracking && provider.incidenteActivo != null) {
        provider.iniciarTracking();
      }
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seguimiento en Tiempo Real')),
      body: Consumer<TecnicoProvider>(
        builder: (context, tecnicoProvider, child) {
          final incidente = tecnicoProvider.incidenteActivo;

          if (incidente == null) {
            return const Center(child: Text('No hay incidente activo'));
          }

          final latIncidente = incidente['latitud'] as double?;
          final lonIncidente = incidente['longitud'] as double?;
          final ubicacionActual = tecnicoProvider.ubicacionActual;

          if (latIncidente == null ||
              lonIncidente == null ||
              ubicacionActual == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final incidenteLatLng = LatLng(latIncidente, lonIncidente);
          final tecnicoLatLng = LatLng(
            ubicacionActual.latitude,
            ubicacionActual.longitude,
          );

          // Extraer polyline de la ruta si existe
          List<LatLng> routePoints = [];
          if (tecnicoProvider.rutaActual?.geometry != null) {
            try {
              final coordinates =
                  tecnicoProvider.rutaActual!.geometry!['coordinates'] as List?;
              if (coordinates != null) {
                routePoints = coordinates
                    .map((coord) {
                      if (coord is List && coord.length >= 2) {
                        return LatLng(
                          (coord[1] as num).toDouble(),
                          (coord[0] as num).toDouble(),
                        );
                      }
                      return null;
                    })
                    .whereType<LatLng>()
                    .toList();
              }
            } catch (e) {
              // Ignorar errores de parsing
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // === INFORMACIÓN DEL INCIDENTE ===
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Información del Incidente',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Descripción: ${incidente['descripcion'] ?? 'N/A'}',
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Ubicación: ${incidente['ubicacion'] ?? 'No especificada'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Estado: ${(incidente['estado'] ?? 'pendiente').toString().toUpperCase()}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // === INFORMACIÓN DE DISTANCIA Y ETA ===
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Distancia',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${tecnicoProvider.distanciaActual.toStringAsFixed(0)} m',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ETA Estimado',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${tecnicoProvider.etaMinutos.toStringAsFixed(1)} min',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Conexión',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                tecnicoProvider.estadoConexion,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: _colorEstadoConexion(
                                    tecnicoProvider.estadoConexion,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // === MAPA EN TIEMPO REAL ===
              Container(
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: tecnicoLatLng,
                      initialZoom: 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.app',
                      ),
                      // Polyline de la ruta
                      if (routePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePoints,
                              color: Colors.blue,
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      // Marcadores
                      MarkerLayer(
                        markers: [
                          // Marcador del técnico (verde)
                          Marker(
                            point: tecnicoLatLng,
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.5),
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                          // Marcador del incidente (azul)
                          Marker(
                            point: incidenteLatLng,
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.5),
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.pin_drop,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // === BOTONES DE ACCIÓN ===
              if (tecnicoProvider.errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    'Error: ${tecnicoProvider.errorMessage}',
                    style: TextStyle(color: Colors.red.shade900),
                  ),
                ),
              const SizedBox(height: 12),

              // Botón de marcar llegada
              if (tecnicoProvider.puedeMarcarLlegada())
                ElevatedButton.icon(
                  onPressed: () async {
                    await tecnicoProvider.marcarLlegada();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Llegada marcada exitosamente'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Marcar Llegada'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                )
              else if (tecnicoProvider.llego)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Llegada registrada',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color _colorEstadoConexion(String estado) {
    switch (estado) {
      case 'conectado':
        return Colors.green;
      case 'conectando':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }
}
