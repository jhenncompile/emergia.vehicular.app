import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vehiculo_provider.dart';
import '../../theme/colors.dart';
import 'registrar_vehiculo_screen.dart';

class MisVehiculosScreen extends StatefulWidget {
  const MisVehiculosScreen({super.key});

  @override
  State<MisVehiculosScreen> createState() => _MisVehiculosScreenState();
}

class _MisVehiculosScreenState extends State<MisVehiculosScreen> {
  @override
  void initState() {
    super.initState();
    // Cargar vehículos al abrir la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = context.read<AuthProvider>().userId;
      if (userId != null) {
        context.read<VehiculoProvider>().cargarMisVehiculos(usuarioId: userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Vehículos'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer<VehiculoProvider>(
        builder: (context, vehiculoProvider, _) {
          if (vehiculoProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (vehiculoProvider.misVehiculos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.directions_car_filled,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes vehículos registrados',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RegistrarVehiculoScreen(),
                      ),
                    ),
                    child: const Text('Registrar Vehículo'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: vehiculoProvider.misVehiculos.length,
            itemBuilder: (context, index) {
              final vehiculo = vehiculoProvider.misVehiculos[index];
              return _buildVehiculoCard(context, vehiculo);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const RegistrarVehiculoScreen(),
          ),
        ),
        backgroundColor: AppColors.primaryColor,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildVehiculoCard(
    BuildContext context,
    Map<String, dynamic> vehiculo,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${vehiculo['marca']} ${vehiculo['modelo']}',
                        style: Theme.of(
                          context,
                        ).textTheme.displayLarge?.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vehiculo['anio']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primaryColor),
                  ),
                  child: Text(
                    vehiculo['placa'] ?? 'N/A',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Información del vehículo
            _buildInfoRow(
              icon: Icons.palette,
              label: 'Color',
              value: vehiculo['color'] ?? 'No especificado',
            ),
            const SizedBox(height: 8),
            if (vehiculo['detalle'] != null)
              Column(
                children: [
                  _buildInfoRow(
                    icon: Icons.numbers,
                    label: 'Detalle',
                    value: vehiculo['detalle'],
                  ),
                  const SizedBox(height: 8),
                ],
              ),

            // Botones de acción
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _editarVehiculo(context, vehiculo),
                    child: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _eliminarVehiculo(context, vehiculo),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: const Text(
                      'Eliminar',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.secondaryColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  void _editarVehiculo(BuildContext context, Map<String, dynamic> vehiculo) {
    final colorController = TextEditingController(
      text: vehiculo['color']?.toString() ?? '',
    );
    final seguroController = TextEditingController(
      text: _extractSeguro(vehiculo),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Vehículo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Color'),
              controller: colorController,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(labelText: 'Seguro'),
              controller: seguroController,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final vehiculoId = vehiculo['id'];
              if (vehiculoId is! int) {
                Navigator.of(context).pop();
                return;
              }

              final usuarioId = context.read<AuthProvider>().userId;
              if (usuarioId == null) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sesion invalida. Inicia sesion nuevamente.'),
                  ),
                );
                return;
              }

              final vehiculoProvider = context.read<VehiculoProvider>();
              final ok = await vehiculoProvider.actualizarVehiculo(
                vehiculoId: vehiculoId,
                usuarioId: usuarioId,
                color: colorController.text.trim(),
                seguro: seguroController.text.trim(),
              );

              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Vehiculo actualizado'
                        : (vehiculoProvider.errorMessage ??
                              'No se pudo actualizar'),
                  ),
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ).whenComplete(() {
      colorController.dispose();
      seguroController.dispose();
    });
  }

  String _extractSeguro(Map<String, dynamic> vehiculo) {
    final detalle = vehiculo['detalle']?.toString();
    if (detalle == null || detalle.trim().isEmpty) return '';

    // Expected format (from VehiculoProvider): "VIN: ... | Seguro: ..."
    final parts = detalle.split('|').map((p) => p.trim()).toList();
    for (final part in parts) {
      final lower = part.toLowerCase();
      if (lower.startsWith('seguro:')) {
        return part.substring('seguro:'.length).trim();
      }
    }
    return '';
  }

  void _eliminarVehiculo(BuildContext context, Map<String, dynamic> vehiculo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Vehículo'),
        content: Text(
          '¿Estás seguro de que deseas eliminar ${vehiculo['marca']} ${vehiculo['modelo']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final vehiculoProvider = context.read<VehiculoProvider>();
              await vehiculoProvider.eliminarVehiculo(
                vehiculoId: vehiculo['id'],
              );
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    vehiculoProvider.errorMessage ?? 'Operacion no disponible',
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
