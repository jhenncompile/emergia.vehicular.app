import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vehiculo_provider.dart';
import '../../theme/colors.dart';

class RegistrarVehiculoScreen extends StatefulWidget {
  const RegistrarVehiculoScreen({super.key});

  @override
  State<RegistrarVehiculoScreen> createState() =>
      _RegistrarVehiculoScreenState();
}

class _RegistrarVehiculoScreenState extends State<RegistrarVehiculoScreen> {
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _placaController = TextEditingController();
  final _colorController = TextEditingController();
  final _anioController = TextEditingController();
  final _vinController = TextEditingController();
  final _seguroController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Vehículo'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTextField(
              controller: _marcaController,
              label: 'Marca',
              hint: 'Ej: Toyota',
              icon: Icons.business,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _modeloController,
              label: 'Modelo',
              hint: 'Ej: Corolla',
              icon: Icons.directions_car,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _placaController,
              label: 'Placa',
              hint: 'Ej: ABC-1234',
              icon: Icons.confirmation_number,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _anioController,
              label: 'Año',
              hint: 'Ej: 2020',
              icon: Icons.calendar_today,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _colorController,
              label: 'Color',
              hint: 'Ej: Rojo',
              icon: Icons.palette,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _vinController,
              label: 'VIN (Número de chasis) - Opcional',
              hint: 'Número de identificación del vehículo',
              icon: Icons.numbers,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _seguroController,
              label: 'Póliza de Seguro - Opcional',
              hint: 'Número de póliza',
              icon: Icons.security,
            ),
            const SizedBox(height: 32),
            Consumer<VehiculoProvider>(
              builder: (context, vehiculoProvider, _) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: vehiculoProvider.isLoading
                        ? null
                        : () => _registrarVehiculo(context, vehiculoProvider),
                    child: vehiculoProvider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Registrar Vehículo',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                );
              },
            ),
            Consumer<VehiculoProvider>(
              builder: (context, vehiculoProvider, _) {
                if (vehiculoProvider.errorMessage != null) {
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
                        vehiculoProvider.errorMessage!,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.secondaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _registrarVehiculo(
    BuildContext context,
    VehiculoProvider vehiculoProvider,
  ) async {
    if (_marcaController.text.isEmpty ||
        _modeloController.text.isEmpty ||
        _placaController.text.isEmpty ||
        _colorController.text.isEmpty ||
        _anioController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor completa todos los campos requeridos'),
        ),
      );
      return;
    }

    final usuarioId = context.read<AuthProvider>().userId;
    if (usuarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesion invalida. Inicia sesion nuevamente.'),
        ),
      );
      return;
    }

    final anio = int.tryParse(_anioController.text);
    if (anio == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El año no es valido')));
      return;
    }

    final success = await vehiculoProvider.registrarVehiculo(
      usuarioId: usuarioId,
      marca: _marcaController.text,
      modelo: _modeloController.text,
      placa: _placaController.text,
      color: _colorController.text,
      anio: anio,
      vin: _vinController.text.isNotEmpty ? _vinController.text : null,
      seguro: _seguroController.text.isNotEmpty ? _seguroController.text : null,
    );

    if (!context.mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Vehículo registrado exitosamente!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _placaController.dispose();
    _colorController.dispose();
    _anioController.dispose();
    _vinController.dispose();
    _seguroController.dispose();
    super.dispose();
  }
}
