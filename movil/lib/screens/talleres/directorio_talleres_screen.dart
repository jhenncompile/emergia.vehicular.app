import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/location_tracking_service.dart';
import '../../services/taller_service.dart';
import '../../theme/colors.dart';

/// Directorio de Talleres (solo consulta, exclusivo del cliente).
///
/// Muestra primero las especialidades disponibles; al elegir una, lista los
/// talleres recomendados ordenados por calidad del servicio. Reutiliza
/// `TallerService` y la ubicacion de `LocationTrackingService`. No interviene
/// en el flujo de incidentes.
class DirectorioTalleresScreen extends StatefulWidget {
  const DirectorioTalleresScreen({super.key});

  @override
  State<DirectorioTalleresScreen> createState() => _DirectorioTalleresScreenState();
}

class _DirectorioTalleresScreenState extends State<DirectorioTalleresScreen> {
  List<Map<String, dynamic>> _especialidades = [];
  List<Map<String, dynamic>> _talleres = [];

  int? _especialidadSeleccionada;
  bool _cargandoEspecialidades = true;
  bool _cargandoTalleres = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarEspecialidades();
  }

  Future<void> _cargarEspecialidades() async {
    setState(() {
      _cargandoEspecialidades = true;
      _error = null;
    });
    try {
      final data = await context.read<TallerService>().obtenerEspecialidades();
      if (!mounted) return;
      setState(() {
        _especialidades = data;
        _cargandoEspecialidades = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las especialidades.';
        _cargandoEspecialidades = false;
      });
    }
  }

  Future<void> _seleccionarEspecialidad(int especialidadId) async {
    // Capturamos los servicios antes de los await para no usar el context
    // a traves de gaps asincronos.
    final tallerService = context.read<TallerService>();
    final locationService = context.read<LocationTrackingService>();

    setState(() {
      _especialidadSeleccionada = especialidadId;
      _cargandoTalleres = true;
      _talleres = [];
      _error = null;
    });

    // Ubicacion opcional: si esta disponible se usa para calcular distancia.
    double? lat;
    double? lon;
    try {
      final pos = await locationService.getCurrentLocation();
      lat = pos.latitude;
      lon = pos.longitude;
    } catch (_) {
      lat = null;
      lon = null;
    }

    try {
      final data = await tallerService.obtenerDirectorioPorEspecialidad(
            especialidadId: especialidadId,
            latitud: lat,
            longitud: lon,
          );
      if (!mounted) return;
      setState(() {
        _talleres = data;
        _cargandoTalleres = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los talleres.';
        _cargandoTalleres = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Directorio de Talleres')),
      body: RefreshIndicator(
        onRefresh: _cargarEspecialidades,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Especialidades',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _seccionEspecialidades(),
            const SizedBox(height: 16),
            if (_especialidadSeleccionada != null) ...[
              const Text(
                'Talleres recomendados',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _seccionTalleres(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _seccionEspecialidades() {
    if (_cargandoEspecialidades) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_especialidades.isEmpty) {
      return const Text('No hay especialidades disponibles.');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _especialidades.map((esp) {
        final id = esp['id'] as int;
        final seleccionada = id == _especialidadSeleccionada;
        return ChoiceChip(
          label: Text(esp['nombre']?.toString() ?? 'Especialidad'),
          selected: seleccionada,
          selectedColor: AppColors.primaryColor,
          labelStyle: TextStyle(
            color: seleccionada ? Colors.white : AppColors.textDark,
          ),
          onSelected: (_) => _seleccionarEspecialidad(id),
        );
      }).toList(),
    );
  }

  Widget _seccionTalleres() {
    if (_cargandoTalleres) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: AppColors.error));
    }
    if (_talleres.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No hay talleres para esta especialidad.'),
      );
    }
    return Column(
      children: _talleres.map(_tarjetaTaller).toList(),
    );
  }

  Widget _tarjetaTaller(Map<String, dynamic> taller) {
    final imagenUrl = taller['imagen_url']?.toString();
    final calificacion = taller['calificacion_promedio'];
    final distanciaKm = taller['distancia_km'];
    final abierto = taller['esta_abierto_ahora'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imagenUrl != null && imagenUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imagenUrl,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _avatarTaller(taller),
                ),
              )
            else
              _avatarTaller(taller),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    taller['nombre']?.toString() ?? 'Taller',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    taller['especialidad']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.secondaryColor, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star, color: AppColors.accentColor, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        calificacion != null
                            ? (calificacion as num).toStringAsFixed(1)
                            : 'Sin calificaciones',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (distanciaKm != null) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.place_outlined, size: 16, color: AppColors.textLight),
                        const SizedBox(width: 2),
                        Text('${(distanciaKm as num).toStringAsFixed(1)} km',
                            style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                      ],
                    ],
                  ),
                  if (taller['direccion'] != null &&
                      taller['direccion'].toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textLight),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            taller['direccion'].toString(),
                            style: const TextStyle(color: AppColors.textLight, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    abierto ? '🟢 Abierto ahora' : '🔴 Cerrado',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarTaller(Map<String, dynamic> taller) {
    final nombre = taller['nombre']?.toString() ?? 'T';
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        nombre.isNotEmpty ? nombre[0].toUpperCase() : 'T',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryColor,
        ),
      ),
    );
  }
}
