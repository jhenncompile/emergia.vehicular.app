import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/incidente_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vehiculo_provider.dart';
import '../../theme/colors.dart';

class ReportarIncidenteScreen extends StatefulWidget {
  const ReportarIncidenteScreen({super.key});

  @override
  State<ReportarIncidenteScreen> createState() =>
      _ReportarIncidenteScreenState();
}

class _ReportarIncidenteScreenState extends State<ReportarIncidenteScreen> {
  final _descriptionController = TextEditingController();
  final _ubicacionController = TextEditingController();
  int? _vehiculoSeleccionado;

  // TODO: Integrar servicios de geolocalización para obtener coordenadas automáticas
  // Por ahora usaremos coordenadas de prueba
  final double _latitud = -17.389277;
  final double _longitud = -66.163788;

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

            // Descripción del problema
            Text(
              'Descripción del Problema',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe qué le pasó a tu vehículo...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Ubicación
            Text(
              'Ubicación',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ubicacionController,
              decoration: InputDecoration(
                hintText: 'Dirección o punto de referencia',
                prefixIcon: const Icon(
                  Icons.location_on,
                  color: AppColors.secondaryColor,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Coordenadas: $_latitud, $_longitud',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Botón Reportar
            Consumer2<IncidenteProvider, AuthProvider>(
              builder: (context, incidenteProvider, authProvider, _) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: incidenteProvider.isLoading
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

    if (_descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor describe el problema')),
      );
      return;
    }

    if (_ubicacionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor especifica la ubicación')),
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

    final success = await incidenteProvider.reportarIncidente(
      usuarioId: usuarioId,
      vehiculoId: _vehiculoSeleccionado!,
      descripcion: _descriptionController.text,
      ubicacion: _ubicacionController.text,
      latitud: _latitud,
      longitud: _longitud,
    );

    if (!context.mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Incidente reportado exitosamente!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _ubicacionController.dispose();
    super.dispose();
  }
}
