import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/incidente_provider.dart';
import '../../theme/colors.dart';
import '../ia/diagnostico_ia_screen.dart';
import 'seguimiento_screen.dart';

class MisAtencionesScreen extends StatefulWidget {
  const MisAtencionesScreen({super.key});

  @override
  State<MisAtencionesScreen> createState() => _MisAtencionesScreenState();
}

class _MisAtencionesScreenState extends State<MisAtencionesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_cargarData);
  }

  Future<void> _cargarData() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    await context.read<IncidenteProvider>().cargarMisIncidentes(
      usuarioId: userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IncidenteProvider>(
      builder: (context, incidenteProvider, _) {
        if (incidenteProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final incidentes = incidenteProvider.misIncidentes;
        final activos = incidentes.where((i) {
          final estado = (i['estado'] ?? '').toString().toLowerCase();
          return estado == 'pendiente' ||
              estado == 'buscando_taller' ||
              estado == 'asignado_taller' ||
              estado == 'en_camino' ||
              estado == 'en_atencion';
        }).toList();

        final pendientesPago = incidentes.where((i) {
          final pagoEstado = (i['pago_estado'] ?? '').toString().toLowerCase();
          return pagoEstado == 'por_cobrar';
        }).toList();

        return RefreshIndicator(
          onRefresh: _cargarData,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Mis Atenciones',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (activos.isEmpty && pendientesPago.isEmpty) _emptyCard(),
              if (activos.isNotEmpty) ...[
                _sectionTitle(
                  'Servicios Activos (${activos.length})',
                  AppColors.info,
                ),
                const SizedBox(height: 8),
                ...activos.map(
                  (incidente) => _incidenteActivoCard(context, incidente),
                ),
                const SizedBox(height: 12),
              ],
              if (pendientesPago.isNotEmpty) ...[
                _sectionTitle(
                  'Pendientes de Pago (${pendientesPago.length})',
                  AppColors.warning,
                ),
                const SizedBox(height: 8),
                ...pendientesPago.map(
                  (incidente) => _pendientePagoCard(context, incidente),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _incidenteActivoCard(
    BuildContext context,
    Map<String, dynamic> incidente,
  ) {
    final estado = (incidente['estado'] ?? 'pendiente').toString();
    final prioridad = (incidente['prioridad'] ?? 'media')
        .toString()
        .toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    incidente['descripcion']?.toString() ?? 'Incidente',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _chip(prioridad, _priorityColor(prioridad)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Estado: ${estado.toUpperCase()}'),
            Text('Ubicacion: ${incidente['ubicacion'] ?? 'No especificada'}'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DiagnosticoIAScreen(
                            incidente: incidente,
                            onCompleted: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SeguimientoScreen(incidente: incidente),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Diagnostico IA'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SeguimientoScreen(incidente: incidente),
                        ),
                      );
                    },
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Rastrear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendientePagoCard(
    BuildContext context,
    Map<String, dynamic> incidente,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    incidente['descripcion']?.toString() ??
                        'Servicio completado',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _chip('PAGO PENDIENTE', AppColors.warning),
              ],
            ),
            const SizedBox(height: 8),
            Text('Estado pago: ${incidente['pago_estado'] ?? 'pendiente'}'),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Pagos desde movil aun no habilitados en backend.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.credit_card),
                label: const Text('Ver pago'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: const [
            Icon(Icons.build_circle_outlined, size: 54, color: Colors.grey),
            SizedBox(height: 10),
            Text(
              'No tienes servicios activos',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6),
            Text('Cuando reportes una emergencia aparecera aqui.'),
          ],
        ),
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

  Color _priorityColor(String value) {
    switch (value.toLowerCase()) {
      case 'alta':
        return AppColors.error;
      case 'media':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }
}
