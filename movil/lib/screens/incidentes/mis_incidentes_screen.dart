import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../../providers/incidente_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/incidente_service.dart';
import '../../services/sync_service.dart';
import '../../theme/colors.dart';
import '../calificacion/calificacion_screen.dart';

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
      _cargarDatos(context);
    });
  }

  void _cargarDatos(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.userId;
    if (userId != null) {
      context.read<IncidenteProvider>().cargarMisIncidentes(
        usuarioId: userId,
        esTecnico: authProvider.isTecnico,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esTecnico = context.watch<AuthProvider>().isTecnico;

    return Scaffold(
      appBar: AppBar(
        title: Text(esTecnico ? 'Incidentes Asignados' : 'Mis Incidentes'),
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
                    esTecnico
                        ? 'No tienes incidentes asignados'
                        : 'No tienes incidentes reportados',
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
              return _buildIncidenteCard(context, incidente, esTecnico);
            },
          );
        },
      ),
    );
  }

  Widget _buildIncidenteCard(
    BuildContext context,
    Map<String, dynamic> incidente,
    bool esTecnico,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_turned_in_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    esTecnico
                        ? 'Asignado #${incidente['id']}'
                        : 'Incidente #${incidente['id']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _chip(
                  incidente['estado'] == 'pendiente_sync'
                      ? 'SIN CONEXIÓN'
                      : (incidente['estado']?.toString().toUpperCase() ?? 'PENDIENTE'),
                  _getColorEstado(incidente['estado']),
                ),
                if (incidente['es_local'] == true) ...[  
                  const SizedBox(width: 6),
                  const Tooltip(
                    message: 'Guardado localmente, pendiente de envío al servidor',
                    child: Icon(Icons.wifi_off, size: 16, color: Colors.orange),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            if (incidente['es_local'] == true)
              _buildSyncStatusWidget(context, incidente),

            Text(
              _textoIncidente(incidente) ?? 'Incidente',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            
            if (esTecnico)
              _infoLine(
                Icons.person_outline,
                _nombrePersona(incidente['usuario']) ?? 'Cliente no disponible',
              ),
            _infoLine(
              Icons.directions_car_outlined,
              _vehiculoLabel(incidente['vehiculo']) ?? 'Vehiculo no disponible',
            ),
            _infoLine(
              Icons.location_on_outlined,
              incidente['ubicacion'] ?? 'Sin ubicación',
            ),
            _infoLine(
              Icons.calendar_today_outlined,
              _formatearFecha(_fechaIncidente(incidente)),
            ),
            const SizedBox(height: 10),

            // Botones de acción
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _verDetalles(context, incidente),
                icon: const Icon(Icons.info_outline),
                label: Text(esTecnico ? 'Ver Datos' : 'Ver Detalles'),
              ),
            ),

            if (!esTecnico && incidente['estado']?.toString().toLowerCase() == 'buscando_taller') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarSeleccionTaller(context, incidente['id'] as int),
                  icon: const Icon(Icons.handyman),
                  label: const Text('Cambiar Taller / Escoger'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ),
            ],


            // Botón calificar taller (solo cliente, solo finalizado)
            if (!esTecnico &&
                (incidente['estado']?.toString().toLowerCase() == 'finalizado' ||
                    incidente['estado']?.toString().toLowerCase() == 'completado') &&
                incidente['taller'] != null &&
                incidente['calificado'] != true) ...
              [
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final taller = incidente['taller'] as Map<String, dynamic>?;
                      final nombreTaller = taller?['nombre']?.toString();
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => CalificacionScreen(
                            incidenteId: incidente['id'] as int,
                            nombreTaller: nombreTaller,
                          ),
                        ),
                      );
                      if (result == true) {
                        setState(() {
                          incidente['calificado'] = true;
                        });
                      }
                      // Si calificó, podemos refrescar si es necesario
                      if (result == true && mounted) {
                        _cargarDatos(context);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Calificación enviada. ¡Gracias!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.star),
                    label: const Text('Calificar Servicio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],

            // Botón Seleccionar Taller (solo cliente, estado pendiente)
            if (!esTecnico && incidente['estado']?.toString().toLowerCase() == 'pendiente') ...
              [
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () => _mostrarSeleccionTaller(context, incidente['id'] as int),
                    icon: const Icon(Icons.build_circle),
                    label: const Text('Seleccionar Taller'),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarSeleccionTaller(BuildContext context, int incidenteId) async {
    final provider = Provider.of<IncidenteProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    List<Map<String, dynamic>> candidatos = [];
    try {
      candidatos = await provider.obtenerCotizaciones(incidenteId);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Cerrar loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar opciones: $e')),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // Cerrar loader

    if (candidatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontraron talleres disponibles para cambiar.')),
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
                      final candidato = candidatos[i];
                      final rating = candidato['calificacion_promedio'] ?? 0.0;

                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.build),
                        ),
                        title: Text(candidato['taller_nombre'] ?? 'Taller sin nombre'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monto cotizado: ${candidato['monto'] ?? candidato['sugerencia_ia_monto'] ?? '0.00'} Bs',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                            Text('Tiempo estimado: ${candidato['tiempo_estimado'] ?? 'No especificado'}'),
                            Row(
                              children: [
                                const Icon(Icons.star, size: 16, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(rating.toStringAsFixed(1)),
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context); // Cierra el bottom sheet
                            final success = await provider.seleccionarCotizacion(
                              incidenteId: incidenteId,
                              tallerId: candidato['taller_id'],
                            );
                            if (!context.mounted) return;
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Taller seleccionado exitosamente.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _cargarDatos(context); // Refrescar lista
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

  Color _getColorEstado(String? estado) {
    switch (estado?.toLowerCase()) {
      case 'pendiente':
        return Colors.orange;
      case 'pendiente_sync':
        return Colors.deepOrange;
      case 'buscando_taller':
        return Colors.amber.shade700;
      case 'asignado_taller':
        return Colors.indigo;
      case 'en_camino':
        return Colors.blue;
      case 'en_atencion':
        return Colors.cyan;
      case 'finalizado':
      case 'completado':
        return Colors.green;
      case 'cancelado':
        return AppColors.error;
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
    final esTecnico = context.read<AuthProvider>().isTecnico;
    final punto = _latLngDesdeValores(
      incidente['latitud'],
      incidente['longitud'],
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
              if (esTecnico)
                _buildDetalleRow(
                  'Cliente',
                  _nombrePersona(incidente['usuario']) ?? 'N/A',
                ),
              if (esTecnico)
                _buildDetalleRow(
                  'Telefono cliente',
                  _telefonoCliente(incidente) ?? 'N/A',
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
              if (_texto(incidente['tiempo_reparacion_estimado']) != null)
                _buildDetalleRow(
                  'Tiempo de Reparación',
                  _texto(incidente['tiempo_reparacion_estimado'])!,
                ),
              if (punto != null)
                _buildDetalleMapa(punto)
              else
                _buildDetalleRow('Ubicación', incidente['ubicacion'] ?? 'N/A'),
              _EvidenciasIncidenteSection(
                incidenteId: incidente['id'] is int
                    ? incidente['id'] as int
                    : 0,
                incidenteService: context
                    .read<IncidenteProvider>()
                    .incidenteService,
              ),
              _buildDetalleRow(
                'Vehiculo',
                _vehiculoLabel(incidente['vehiculo']) ?? 'N/A',
              ),
              _buildDetalleRow(
                'Fecha',
                _formatearFecha(_fechaIncidente(incidente)),
              ),
              if (incidente['taller'] != null)
                _buildDetalleRow(
                  'Taller Asignado',
                  _tallerLabel(incidente['taller']) ?? 'N/A',
                ),
              if (!esTecnico && incidente['tecnico'] != null)
                _buildDetalleRow(
                  'Tecnico Asignado',
                  _nombrePersona(incidente['tecnico']) ?? 'N/A',
                ),
              if (_texto(incidente['pago_estado']) != null)
                _buildDetalleRow(
                  'Estado pago',
                  _texto(incidente['pago_estado'])!.toUpperCase(),
                ),
              if (_pagoLabel(incidente['pagos']) != null)
                _buildDetalleRow('Pago', _pagoLabel(incidente['pagos'])!),
              if (_texto(incidente['motivo_cancelacion']) != null)
                _buildDetalleRow(
                  'Motivo',
                  _texto(incidente['motivo_cancelacion'])!,
                ),
            ],
          ),
        ),
        actions: [
          if (!esTecnico && _puedeCancelarCliente(incidente))
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _solicitarCancelacion(context, incidente);
              },
              child: const Text('Cancelar incidente'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  bool _puedeCancelarCliente(Map<String, dynamic> incidente) {
    final estado = (incidente['estado'] ?? '').toString().toLowerCase();
    return estado == 'pendiente' ||
        estado == 'buscando_taller' ||
        estado == 'asignado_taller' ||
        estado == 'en_camino';
  }

  // Hay taller asignado si viene el id o el objeto anidado del taller.
  bool _tieneTaller(Map<String, dynamic> incidente) =>
      incidente['taller_id'] != null || incidente['taller'] != null;

  // Penalidad si se cancela pasado 1 segundo desde la creacion del incidente.
  bool _aplicaPenalidad(Map<String, dynamic> incidente) {
    final creadoRaw = incidente['fecha_creacion'];
    if (creadoRaw == null) return false;
    var creado = DateTime.tryParse(creadoRaw.toString());
    if (creado == null) return false;
    // El backend envia la fecha en UTC pero sin marca de zona ('Z'); si se
    // interpreta como hora local queda desfasada. La reinterpretamos como UTC.
    if (!creado.isUtc) {
      creado = DateTime.utc(creado.year, creado.month, creado.day, creado.hour,
          creado.minute, creado.second, creado.millisecond, creado.microsecond);
    }
    final diff = DateTime.now().toUtc().difference(creado);
    return diff > const Duration(seconds: 1);
  }

  Future<void> _solicitarCancelacion(
    BuildContext context,
    Map<String, dynamic> incidente,
  ) async {
    final motivoController = TextEditingController();
    try {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancelar incidente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_aplicaPenalidad(incidente) && _tieneTaller(incidente))
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border.all(color: const Color(0xFFFECACA)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '⚠️ Se aplicarán recargos por cancelación.\n'
                    'Han pasado más de 1 segundo desde el reporte y ya hay '
                    'un taller asignado, por lo que al cancelar se generará '
                    'un cargo de penalidad.',
                    style: TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
                  ),
                ),
              TextField(
                controller: motivoController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Volver'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancelar incidente'),
            ),
          ],
        ),
      );

      if (confirmar != true) return;
      if (!context.mounted) return;
      final motivo = motivoController.text.trim();
      if (motivo.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes ingresar un motivo.')),
        );
        return;
      }

      // Penalidad: aplica si pasado el umbral y el incidente ya tenía taller asignado.
      final penaliza = _aplicaPenalidad(incidente) && _tieneTaller(incidente);

      final incidenteProvider = context.read<IncidenteProvider>();
      final ok = await incidenteProvider.cancelarIncidente(
        incidenteId: incidente['id'] as int,
        motivo: motivo,
      );
      if (!context.mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cancelar.')),
        );
      } else if (penaliza) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFB91C1C),
            duration: Duration(seconds: 5),
            content: Text(
              'Incidente cancelado. Se generó un cargo de penalidad por '
              'cancelación tardía. Revísalo en la sección Pagos.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incidente cancelado.')),
        );
      }
    } finally {
      motivoController.dispose();
    }
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

  String? _nombrePersona(dynamic value) {
    if (value is! Map) return null;

    final nombre = _texto(value['nombre']);
    final apellido = _texto(value['apellido']);
    final correo = _texto(value['correo']);
    final partes = [nombre, apellido].whereType<String>().join(' ').trim();

    if (partes.isNotEmpty) return partes;
    return correo;
  }

  String? _telefonoCliente(Map<String, dynamic> incidente) {
    final telefono = _texto(incidente['telefono_cliente']);
    if (telefono != null) return telefono;

    final usuario = incidente['usuario'];
    if (usuario is Map) {
      return _texto(usuario['telefono']);
    }
    return null;
  }

  String? _vehiculoLabel(dynamic value) {
    if (value is! Map) return null;

    final placa = _texto(value['placa']);
    final marca = _texto(value['marca']);
    final modelo = _texto(value['modelo']);
    final detalle = [marca, modelo].whereType<String>().join(' ').trim();

    if (placa == null && detalle.isEmpty) return null;
    if (detalle.isEmpty) return placa;
    if (placa == null) return detalle;
    return '$placa - $detalle';
  }

  String? _tallerLabel(dynamic value) {
    if (value is! Map) return null;

    final nombre = _texto(value['nombre']);
    final direccion = _texto(value['direccion']);
    if (nombre == null) return direccion;
    if (direccion == null) return nombre;
    return '$nombre - $direccion';
  }

  String? _pagoLabel(dynamic value) {
    dynamic pago = value;
    if (pago is List && pago.isNotEmpty) {
      pago = pago.first;
    }
    if (pago is! Map) return null;

    final monto = _texto(pago['monto']);
    final estado = _texto(pago['estado']);
    if (monto == null && estado == null) return null;
    if (monto == null) return estado!.toUpperCase();
    if (estado == null) return 'Bs. $monto';
    return 'Bs. $monto - ${estado.toUpperCase()}';
  }

  String? _texto(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
  /// Indicador visual del estado de sincronización para incidentes offline.
  Widget _buildSyncStatusWidget(BuildContext context, Map<String, dynamic> incidente) {
    final idLocal = incidente['id'] as int;

    return FutureBuilder<EstadoSync>(
      future: SyncService.obtenerEstado(idLocal),
      builder: (context, snapshot) {
        final estado = snapshot.data ?? EstadoSync.pendiente;

        Widget icon;
        String mensaje;
        Color color;
        Widget? botonReintento;

        switch (estado) {
          case EstadoSync.pendiente:
            icon = const Icon(Icons.access_time, size: 14, color: Colors.orange);
            mensaje = 'Pendiente de sincronización';
            color = Colors.orange.shade50;
            break;
          case EstadoSync.sincronizando:
            icon = const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
            mensaje = 'Sincronizando...';
            color = Colors.blue.shade50;
            break;
          case EstadoSync.sincronizado:
            icon = const Icon(Icons.check_circle, size: 14, color: Colors.green);
            mensaje = 'Sincronizado correctamente';
            color = Colors.green.shade50;
            break;
          case EstadoSync.error:
            icon = const Icon(Icons.error_outline, size: 14, color: Colors.red);
            mensaje = 'Error al sincronizar';
            color = Colors.red.shade50;
            botonReintento = TextButton.icon(
              onPressed: () async {
                final syncService = context.read<SyncService>();
                final ok = await syncService.reintentar(idLocal);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? '✅ Sincronizado' : '❌ Sigue sin conexión'),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    ),
                  );
                  setState(() {}); // Refrescar el FutureBuilder
                }
              },
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Reintentar', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
            );
            break;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color == Colors.orange.shade50 ? Colors.orange : Colors.transparent),
          ),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 6),
              Expanded(
                child: Text(mensaje, style: const TextStyle(fontSize: 12)),
              ),
              ?botonReintento,
            ],
          ),
        );
      },
    );
  }
  Widget _infoLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.secondaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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

  Widget _buildEvidencia(BuildContext context, Map<String, dynamic> evidencia) {
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
              errorBuilder: (_, _, _) => _buildArchivoNoDisponible(
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
            errorBuilder: (_, _, _) => _buildArchivoNoDisponible(
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
