import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/incidente_provider.dart';
import '../../providers/tecnico_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/taller_service.dart';
import '../../theme/colors.dart';
// Para reutilizar logica o navegar, aunque es mejor importar el modal


class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  Timer? _quotesTimer;
  List<Map<String, dynamic>> _talleres = [];
  List<Map<String, dynamic>> _cotizaciones = [];

  void _startQuotesTimer(int incidenteId) {
    if (_quotesTimer != null) return;
    _fetchQuotes(incidenteId);
    _quotesTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchQuotes(incidenteId));
  }

  void _stopQuotesTimer() {
    _quotesTimer?.cancel();
    _quotesTimer = null;
  }

  Future<void> _fetchQuotes(int incidenteId) async {
    final provider = context.read<IncidenteProvider>();
    try {
      final quotes = await provider.obtenerCotizaciones(incidenteId);
      if (mounted) {
        setState(() {
          _cotizaciones = quotes;
        });
      }
    } catch (e) {
      debugPrint("Error fetching quotes: $e");
    }
  }

  late AnimationController _radarController;
  List<LatLng> _routePoints = [];
  int? _etaMinutes;
  LatLng? _lastTallerLocation;
  String? _lastEstado;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTalleres();
      final auth = context.read<AuthProvider>();
      if (auth.isTecnico) {
        final tecnicoProvider = context.read<TecnicoProvider>();
        if (!tecnicoProvider.isTracking && tecnicoProvider.incidenteActivo != null) {
          final estado = (tecnicoProvider.incidenteActivo!['estado'] ?? '').toString();
          if (estado == 'en_camino' || estado == 'en_atencion') {
            tecnicoProvider.iniciarTracking();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _stopQuotesTimer();
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _loadTalleres() async {
    
    try {
      final tallerService = context.read<TallerService>();
      _talleres = await tallerService.obtenerTalleresActivos();
    } catch (e) {
      debugPrint('Error loading talleres: $e');
    }
    
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    final url = 'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        if (routes.isNotEmpty) {
          final route = routes.first;
          final duration = (route['duration'] as num).toDouble();
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;
          
          final List<LatLng> points = coordinates.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          
          if (mounted) {
            setState(() {
              _routePoints = points;
              _etaMinutes = (duration / 60).round();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
    }
  }

  void _ajustarCamara(LatLng userLocation, LatLng? tallerLocation) {
    if (tallerLocation == null) return;
    try {
      final bounds = LatLngBounds.fromPoints([userLocation, tallerLocation]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80.0),
        ),
      );
    } catch (e) {
      debugPrint("Error al ajustar bounds: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IncidenteProvider>(
      builder: (context, provider, child) {
        final activo = provider.incidenteActivoCliente;
        if (activo == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Seguimiento en Mapa')),
            body: const Center(child: Text('No hay incidente activo')),
          );
        }

        final esTecnico = context.watch<AuthProvider>().isTecnico;
        final tecnicoProvider = esTecnico ? context.watch<TecnicoProvider>() : null;

        final estado = (activo['estado'] ?? '').toString().toLowerCase();
        final double lat = activo['latitud'] is double ? activo['latitud'] : double.tryParse(activo['latitud']?.toString() ?? '0') ?? 0.0;
        final double lng = activo['longitud'] is double ? activo['longitud'] : double.tryParse(activo['longitud']?.toString() ?? '0') ?? 0.0;
        final userLocation = LatLng(lat, lng);

        final isBuscando = estado == 'pendiente' || estado == 'buscando_taller';
        final isAsignado = estado == 'asignado_taller';
        final isEnCamino = estado == 'en_camino';
        final isEnAtencion = estado == 'en_atencion';

        // Filter taller pins based on state
        List<Marker> tallerMarkers = [];
        LatLng? tallerLocation;
        String tallerNombre = 'Taller Asignado';

        if (isBuscando) {
             final incId = activo['id'] as int;
             if (_quotesTimer == null) {
                Future.microtask(() => _startQuotesTimer(incId));
             }

             tallerMarkers = _talleres.map((t) {
                final quoteIndex = _cotizaciones.indexWhere((c) => c['taller_id'] == t['id']);
                final quote = quoteIndex >= 0 ? _cotizaciones[quoteIndex] : null;
                
                final tLat = t['latitud'] is double ? t['latitud'] : double.tryParse(t['latitud']?.toString() ?? '0') ?? 0.0;
                final tLng = t['longitud'] is double ? t['longitud'] : double.tryParse(t['longitud']?.toString() ?? '0') ?? 0.0;
                
                return Marker(
                  point: LatLng(tLat, tLng),
                  width: 100,
                  height: 60,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (quote != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Text(
                            "${quote['monto'] ?? quote['sugerencia_ia_monto'] ?? 0} Bs",
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      Icon(Icons.build_circle, color: quote != null ? Colors.blue : Colors.grey, size: 30),
                    ],
                  ),
                );
             }).toList();
        } else {
             _stopQuotesTimer();
        }
        if (isAsignado || isEnCamino || isEnAtencion) {
           final Map<String, dynamic> tallerData = (activo['taller'] as Map<String, dynamic>?) ??
    _talleres.firstWhere(
        (t) => t['id'] == activo['taller_id'],
        orElse: () => <String, dynamic>{});
           final incidentId = activo['id'] as int;
           final liveUbic = provider.getUbicacionTecnicoEnVivo(incidentId);

           if (tallerData.isNotEmpty || esTecnico || liveUbic != null) {

              // 1. Coordenadas fijas del Taller
              LatLng? realTallerLocation;
              if (tallerData.isNotEmpty) {
                final lat = tallerData['latitud'] is double ? tallerData['latitud'] : double.tryParse(tallerData['latitud']?.toString() ?? '0') ?? 0.0;
                final lng = tallerData['longitud'] is double ? tallerData['longitud'] : double.tryParse(tallerData['longitud']?.toString() ?? '0') ?? 0.0;
                realTallerLocation = LatLng(lat, lng);
              }
              
              // 2. Coordenadas móviles del Técnico
              LatLng? tecnicoLocation;
              if (liveUbic != null) {
                tecnicoLocation = LatLng(liveUbic['lat']!, liveUbic['lng']!);
              } else if (esTecnico && tecnicoProvider?.ubicacionActual != null) {
                tecnicoLocation = LatLng(tecnicoProvider!.ubicacionActual!.latitude, tecnicoProvider.ubicacionActual!.longitude);
              }

              // Usar la ubicación del técnico si existe, sino la del taller para la ruta
              tallerLocation = tecnicoLocation ?? realTallerLocation;
              tallerNombre = tallerData['nombre'] ?? (esTecnico ? 'Tu Ubicación' : 'Taller');
              
              // Dibujar marcador del Taller (siempre verde y estático)
              if (realTallerLocation != null) {
                 tallerMarkers.add(Marker(
                   point: realTallerLocation,
                   child: Stack(
                     alignment: Alignment.center,
                     children: [
                       const Icon(Icons.build_circle, color: Colors.green, size: 36),
                       Positioned(
                         bottom: -20,
                         child: Text(
                           tallerNombre,
                           style: const TextStyle(
                             color: Colors.black,
                             fontWeight: FontWeight.bold,
                             fontSize: 12,
                             backgroundColor: Colors.white70,
                           ),
                         ),
                       ),
                     ],
                   ),
                 ));
              }

              // Dibujar marcador del Técnico (siempre azul y móvil)
              if (tecnicoLocation != null) {
                 tallerMarkers.add(Marker(
                   point: tecnicoLocation,
                   child: Stack(
                     alignment: Alignment.center,
                     children: [
                       const Icon(Icons.directions_car, color: Colors.blue, size: 36),
                       Positioned(
                         bottom: -20,
                         child: Text(
                           esTecnico ? 'Tu Ubicación' : 'Técnico',
                           style: const TextStyle(
                             color: Colors.black,
                             fontWeight: FontWeight.bold,
                             fontSize: 12,
                             backgroundColor: Colors.white70,
                           ),
                         ),
                       ),
                     ],
                   ),
                 ));
              }

              // Fetch route when we have a location and the incident is assigned or in motion
              if ((isAsignado || isEnCamino || isEnAtencion) && _lastTallerLocation != tallerLocation) {
                 _lastTallerLocation = tallerLocation;
                 Future.microtask(() => _fetchRoute(tallerLocation!, userLocation));
              }
           }
        }

        // Adjust camera when state changes from something else to Asignado/Camino
        if (_lastEstado != estado && (isAsignado || isEnCamino || isBuscando)) {
           if (tallerLocation != null) {
              Future.microtask(() => _ajustarCamara(userLocation, tallerLocation));
           }
        }
        _lastEstado = estado;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Seguimiento en Mapa'),
            elevation: 0,
          ),
          body: Stack(
            children: [
              // Map fills the available space
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: userLocation,
                    initialZoom: 14.0,
                    onMapReady: () {
                      if (isAsignado || isEnCamino) {
                        _ajustarCamara(userLocation, tallerLocation);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.emergencia.vehicular',
                    ),
                    if ((isEnCamino || isEnAtencion) && tallerLocation != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints.isNotEmpty ? _routePoints : [tallerLocation, userLocation],
                            strokeWidth: 5.0,
                            color: Colors.blueAccent,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: userLocation,
                          child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                        ),
                        ...tallerMarkers,
                      ],
                    ),
                  ],
                ),
              ),
              // Bottom sheet and controls will be stacked on top
              Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBuscando && _cotizaciones.isNotEmpty)
                      _buildCarousel(activo['id'] as int),
                    _buildBottomSheet(activo, tallerNombre, isBuscando, isAsignado, isEnCamino, isEnAtencion, esTecnico),
                  ],
                ),
              ),
              if (isAsignado && tallerLocation != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: FloatingActionButton(
                    mini: true,
                    onPressed: () => _ajustarCamara(userLocation, tallerLocation),
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomSheet(Map<String, dynamic> activo, String tallerNombre, bool isBuscando, bool isAsignado, bool isEnCamino, bool isEnAtencion, bool esTecnico) {
    if (isBuscando) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _radarController,
              builder: (_, child) {
                return Opacity(
                  opacity: 0.3 + (_radarController.value * 0.7),
                  child: const CircularProgressIndicator(strokeWidth: 3),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              "Contactando talleres cercanos...",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!esTecnico)
                  ElevatedButton.icon(
                    onPressed: () => _mostrarSeleccionTallerMapa(context, activo['id'] as int),
                    icon: const Icon(Icons.build_circle),
                    label: const Text('Talleres'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: () => _mostrarDialogoCancelar(context, activo['id'] as int, esTecnico),
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancelar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else if (isAsignado) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green, size: 40),
            const SizedBox(height: 16),
            Text(
              "$tallerNombre evaluando tu caso...",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _mostrarDialogoCancelar(context, activo['id'] as int, esTecnico),
              icon: const Icon(Icons.cancel),
              label: const Text('Cancelar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    } else if (isEnCamino || isEnAtencion) {
      final tecnico = activo['tecnico'] != null ? activo['tecnico']['nombre'] ?? 'Técnico Asignado' : 'Conductor Asignado';
      final isAtencion = isEnAtencion;
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryColor.withValues(alpha: 0.1),
                  radius: 30,
                  child: const Icon(Icons.engineering, color: AppColors.primaryColor, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tallerNombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(tecnico, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        isAtencion ? "El técnico está atendiendo tu vehículo" : 
                        (_etaMinutes != null ? "ETA: ~$_etaMinutes mins" : "Calculando ruta..."),
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                        child: Text("Incidente #${activo['id']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      )
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (esTecnico && !isAtencion && activo['estado'] == 'en_camino')
                  ElevatedButton.icon(
                    onPressed: () async {
                      final provider = context.read<TecnicoProvider>();
                      try {
                        await provider.marcarLlegada();
                        if (!context.mounted) return;
                        context.read<IncidenteProvider>().actualizarEstadoLocal(
                          id: activo['id'] as int,
                          estado: 'en_atencion',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Llegada marcada exitosamente'), backgroundColor: Colors.green),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Marcar Llegada'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                if (esTecnico && isAtencion)
                  ElevatedButton.icon(
                    onPressed: () => _mostrarDialogoFinalizar(context),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Finalizar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                const SizedBox(width: 8),
                if (esTecnico || (!esTecnico && !isEnAtencion))
                  ElevatedButton.icon(
                    onPressed: () => _mostrarDialogoCancelar(context, activo['id'] as int, esTecnico),
                    icon: const Icon(Icons.cancel),
                    label: const Text('Cancelar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    final clientPhone = activo['telefono_cliente']?.toString() ?? '';
                    if (clientPhone.isNotEmpty) {
                      launchUrl(Uri.parse('tel:$clientPhone'));
                    }
                  },
                  icon: const Icon(Icons.call, color: Colors.white),
                  label: const Text('Llamar Cliente', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse("sms:+59112345678")),
                  icon: const Icon(Icons.message),
                  label: const Text('Mensaje'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildCarousel(int incidenteId) {
    return SizedBox(
      height: 170,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.85),
        itemCount: _cotizaciones.length,
        itemBuilder: (ctx, i) {
          final c = _cotizaciones[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.build_circle, color: AppColors.primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c['taller_nombre'] ?? 'Taller',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Cotización: ${c['monto'] ?? c['sugerencia_ia_monto']} Bs', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  Text('Tiempo estimado: ${c['tiempo_estimado'] ?? 'No especificado'}', style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                      onPressed: () => _aceptarCotizacion(c['taller_id'], incidenteId),
                      child: const Text("Aceptar Cotización"),

                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _aceptarCotizacion(int tallerId, int incidenteId) async {
    final provider = context.read<IncidenteProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    final ok = await provider.seleccionarCotizacion(incidenteId: incidenteId, tallerId: tallerId);
    if (!mounted) return;
    Navigator.pop(context); // Cierra el loader
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cotización aceptada.'), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.errorMessage ?? 'Error al aceptar cotización.'), backgroundColor: Colors.red));
    }
  }

  Future<void> _mostrarDialogoFinalizar(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Incidente'),
        content: const Text('¿Estás seguro de que deseas finalizar este incidente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, finalizar')),
        ],
      ),
    );
    if (confirm == true) {
      final provider = context.read<TecnicoProvider>();
      try {
        await provider.finalizarIncidente();
        if (context.mounted) {
          final incProvider = context.read<IncidenteProvider>();
          final incActivo = incProvider.incidenteActivoCliente;
          if (incActivo != null) {
            incProvider.actualizarEstadoLocal(id: incActivo['id'], estado: 'finalizado');
          }
          Navigator.pop(context);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _mostrarDialogoCancelar(BuildContext context, int incidenteId, bool esTecnico) async {
    final TextEditingController motivoCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Incidente'),
        content: TextField(
          controller: motivoCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motivo',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancelar incidente'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final motivo = motivoCtrl.text.trim();
    if (motivo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes ingresar un motivo.')),
      );
      return;
    }
    if (esTecnico) {
      final provider = context.read<TecnicoProvider>();
      try {
        await provider.cancelarIncidente(motivo);
        if (mounted) {
          final incProvider = context.read<IncidenteProvider>();
          final incActivo = incProvider.incidenteActivoCliente;
          if (incActivo != null) {
            incProvider.actualizarEstadoLocal(id: incActivo['id'], estado: 'cancelado');
          }
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      final provider = context.read<IncidenteProvider>();
      try {
        final success = await provider.cancelarIncidente(incidenteId: incidenteId, motivo: motivo);
        if (success && mounted) {
           Navigator.pop(context);
        } else if (!success && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(provider.errorMessage ?? 'Error al cancelar'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _mostrarSeleccionTallerMapa(BuildContext context, int incidenteId) async {
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
                    'Talleres en la zona',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _talleres.length,
                    itemBuilder: (ctx, i) {
                      final t = _talleres[i];
                      final quoteIndex = _cotizaciones.indexWhere((c) => c['taller_id'] == t['id']);
                      final c = quoteIndex >= 0 ? _cotizaciones[quoteIndex] : null;

                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.primaryColor,
                          child: Icon(Icons.build, color: Colors.white),
                        ),
                        title: Text(t['nombre'] ?? 'Taller sin nombre'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (c != null) ...[
                              Text(
                                'Monto cotizado: ${c['monto'] ?? c['sugerencia_ia_monto'] ?? '0.00'} Bs',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                              Text('Tiempo estimado: ${c['tiempo_estimado'] ?? 'No especificado'}'),
                            ] else ...[
                              const Text('Esperando cotización...', style: TextStyle(color: Colors.orange)),
                            ]
                          ],
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: c != null ? () async {
                            Navigator.pop(context); // Cierra el bottom sheet
                            _aceptarCotizacion(t['id'], incidenteId);
                          } : null,
                          child: Text(c != null ? 'Elegir' : 'Esperando...'),
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
}

