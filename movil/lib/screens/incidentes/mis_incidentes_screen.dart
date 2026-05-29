import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/incidente_provider.dart';
import '../../providers/auth_provider.dart';
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
              incidente['descripcion'] ?? 'Sin descripción',
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
              'Reportado el: ${_formatearFecha(incidente['fecha_reporte'])}',
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
                'Descripción',
                incidente['descripcion'] ?? 'N/A',
              ),
              _buildDetalleRow('Ubicación', incidente['ubicacion'] ?? 'N/A'),
              _buildDetalleRow(
                'Vehículo',
                incidente['vehiculo']?['placa'] ?? 'N/A',
              ),
              _buildDetalleRow(
                'Fecha',
                _formatearFecha(incidente['fecha_reporte']),
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
}
