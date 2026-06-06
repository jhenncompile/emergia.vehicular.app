import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/incidente_provider.dart';
import '../../theme/colors.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_cargar);
  }

  Future<void> _cargar() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.userId;
    if (userId == null) return;
    await context.read<IncidenteProvider>().cargarMisIncidentes(
      usuarioId: userId,
      esTecnico: authProvider.isTecnico,
    );
  }

  @override
  Widget build(BuildContext context) {
    final esTecnico = context.watch<AuthProvider>().isTecnico;

    return Consumer<IncidenteProvider>(
      builder: (context, provider, _) {
        final historial = provider.misIncidentes.where(_esHistorico).toList();

        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                esTecnico ? 'Historico Tecnico' : 'Historial',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (historial.isEmpty)
                _emptyCard(
                  esTecnico
                      ? 'No tienes incidentes historicos aun'
                      : 'No hay servicios completados aun',
                ),
              ...historial.map(
                (item) => _historialCard(context, item, esTecnico),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _esHistorico(Map<String, dynamic> item) {
    final estado = (item['estado'] ?? '').toString().toLowerCase();
    return estado == 'finalizado' || estado == 'completado' || estado == 'cancelado';
  }

  Widget _emptyCard(String mensaje) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.history, size: 54, color: Colors.grey.shade500),
            const SizedBox(height: 10),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historialCard(
    BuildContext context,
    Map<String, dynamic> item,
    bool esTecnico,
  ) {
    final estado = (item['estado'] ?? 'pendiente').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_turned_in_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Incidente #${item['id'] ?? 'N/A'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _chip(estado.toUpperCase(), _estadoColor(estado)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _texto(item['descripcion']) ?? 'Incidente',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            if (esTecnico)
              _infoLine(
                Icons.person_outline,
                _nombrePersona(item['usuario']) ?? 'Cliente no disponible',
              ),
            _infoLine(
              Icons.directions_car_outlined,
              _vehiculoLabel(item['vehiculo']) ?? 'Vehiculo no disponible',
            ),
            _infoLine(
              Icons.location_on_outlined,
              _texto(item['ubicacion']) ?? 'Sin ubicacion',
            ),
            _infoLine(
              Icons.calendar_today_outlined,
              _formatearFecha(item['fecha_creacion'] ?? item['fecha_reporte']),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _verDatos(context, item, esTecnico),
                icon: const Icon(Icons.info_outline),
                label: const Text('Ver datos'),
              ),
            ),
          ],
        ),
      ),
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

  void _verDatos(
    BuildContext context,
    Map<String, dynamic> item,
    bool esTecnico,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Incidente #${item['id'] ?? 'N/A'}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detalle('Estado', _texto(item['estado'])?.toUpperCase() ?? 'N/A'),
              if (esTecnico)
                _detalle(
                  'Cliente',
                  _nombrePersona(item['usuario']) ?? 'N/A',
                ),
              if (esTecnico)
                _detalle('Telefono', _telefonoCliente(item) ?? 'N/A'),
              _detalle('Vehiculo', _vehiculoLabel(item['vehiculo']) ?? 'N/A'),
              _detalle('Ubicacion', _texto(item['ubicacion']) ?? 'N/A'),
              _detalle('Descripcion', _texto(item['descripcion']) ?? 'N/A'),
              _detalle('Prioridad', _texto(item['prioridad']) ?? 'N/A'),
              _detalle(
                'Estado pago',
                _texto(item['pago_estado'])?.toUpperCase() ?? 'N/A',
              ),
              if (_texto(item['clasificacion_ia']) != null)
                _detalle('Categoria IA', _texto(item['clasificacion_ia'])!),
              if (_texto(item['resumen_ia']) != null)
                _detalle('Resumen IA', _texto(item['resumen_ia'])!),
              if (_texto(item['motivo_cancelacion']) != null)
                _detalle('Motivo', _texto(item['motivo_cancelacion'])!),
              _detalle(
                'Fecha',
                _formatearFecha(item['fecha_creacion'] ?? item['fecha_reporte']),
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

  Widget _detalle(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Color _estadoColor(String estado) {
    switch (estado.toLowerCase()) {
      case 'finalizado':
      case 'completado':
        return AppColors.success;
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
    } catch (_) {
      return fecha.toString();
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

  String? _telefonoCliente(Map<String, dynamic> item) {
    final telefono = _texto(item['telefono_cliente']);
    if (telefono != null) return telefono;

    final usuario = item['usuario'];
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

  String? _texto(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
