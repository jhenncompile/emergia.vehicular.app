import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/location_tracking_service.dart';
import '../../services/taller_service.dart';
import '../../theme/colors.dart';

/// Numero al que se redirige el contacto por WhatsApp (Bolivia, +591).
/// Cambia este valor para apuntar a otro destino.
const String _whatsappNumero = '59169193675';

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

  final TextEditingController _busquedaCtrl = TextEditingController();
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _cargarEspecialidades();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  /// Talleres filtrados por el texto de busqueda (nombre, direccion o especialidad).
  List<Map<String, dynamic>> get _talleresFiltrados {
    final q = _filtro.trim().toLowerCase();
    if (q.isEmpty) return _talleres;
    return _talleres.where((t) {
      final nombre = (t['nombre'] ?? '').toString().toLowerCase();
      final direccion = (t['direccion'] ?? '').toString().toLowerCase();
      final especialidad = (t['especialidad'] ?? '').toString().toLowerCase();
      return nombre.contains(q) || direccion.contains(q) || especialidad.contains(q);
    }).toList();
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
      _filtro = '';
      _busquedaCtrl.clear();
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
            const SizedBox(height: 2),
            const Text(
              'Elige una especialidad para ver los talleres recomendados por calidad.',
              style: TextStyle(color: AppColors.textLight, fontSize: 13),
            ),
            const SizedBox(height: 10),
            _seccionEspecialidades(),
            const SizedBox(height: 16),
            if (_especialidadSeleccionada == null && !_cargandoEspecialidades)
              _hintSinSeleccion(),
            if (_especialidadSeleccionada != null) ...[
              Row(
                children: [
                  const Text(
                    'Talleres recomendados',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (!_cargandoTalleres && _talleres.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${_talleresFiltrados.length})',
                      style: const TextStyle(color: AppColors.textLight, fontSize: 14),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _busquedaCtrl,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _filtro = value),
                decoration: InputDecoration(
                  hintText: 'Buscar taller por nombre o dirección',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filtro.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() {
                            _filtro = '';
                            _busquedaCtrl.clear();
                          }),
                        )
                      : null,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              _seccionTalleres(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hintSinSeleccion() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.storefront_outlined, size: 48, color: AppColors.textLight.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          const Text(
            'Selecciona una especialidad arriba para descubrir talleres.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textLight),
          ),
        ],
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
    final filtrados = _talleresFiltrados;
    if (filtrados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Ningún taller coincide con tu búsqueda.'),
      );
    }
    return Column(
      children: filtrados.map(_tarjetaTaller).toList(),
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
                      _pillCalificacion(calificacion),
                      if (distanciaKm != null) ...[
                        const SizedBox(width: 10),
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
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: () => _abrirWhatsApp(taller),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('Contactar por WhatsApp'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirWhatsApp(Map<String, dynamic> taller) async {
    final messenger = ScaffoldMessenger.of(context);
    final nombre = taller['nombre']?.toString() ?? 'el taller';
    final mensaje = Uri.encodeComponent(
      'Hola, vi $nombre en el Directorio de Talleres y quiero más información.',
    );
    final url = Uri.parse('https://wa.me/$_whatsappNumero?text=$mensaje');

    try {
      final abierto = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!abierto) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
      );
    }
  }

  Widget _pillCalificacion(dynamic calificacion) {
    final tiene = calificacion != null;
    final texto = tiene ? (calificacion as num).toStringAsFixed(1) : 'Sin calificaciones';
    final color = tiene ? const Color(0xFFF59E0B) : AppColors.textLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, color: color, size: 15),
          const SizedBox(width: 3),
          Text(
            texto,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ],
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
