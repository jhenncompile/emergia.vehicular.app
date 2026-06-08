import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pago_provider.dart';
import '../../theme/colors.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;

class PagosScreen extends StatefulWidget {
  const PagosScreen({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<PagosScreen> createState() => _PagosScreenState();
}

class _PagosScreenState extends State<PagosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialIndex);

    // Cargar datos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = context.read<AuthProvider>().userId;
      if (userId == null) return;
      final pagoProvider = context.read<PagoProvider>();
      pagoProvider.cargarHistorialPagos(usuarioId: userId);
      pagoProvider.cargarFacturasPendientes(usuarioId: userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Historial'),
            Tab(text: 'Pendientes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildHistorialPagos(), _buildFacturasPendientes()],
      ),
    );
  }

  Widget _buildHistorialPagos() {
    return Consumer<PagoProvider>(
      builder: (context, pagoProvider, _) {
        if (pagoProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (pagoProvider.misPagos.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No tienes pagos registrados',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: pagoProvider.misPagos.length,
          itemBuilder: (context, index) {
            final pago = pagoProvider.misPagos[index];
            return InkWell(
              onTap: () => _mostrarDetallePago(context, pago),
              child: _buildPagoCard(context, pago, false),
            );
          },
        );
      },
    );
  }

  Widget _buildFacturasPendientes() {
    return Consumer<PagoProvider>(
      builder: (context, pagoProvider, _) {
        if (pagoProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (pagoProvider.facturasPendientes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green[400]),
                const SizedBox(height: 16),
                Text(
                  '¡No tienes facturas pendientes!',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: pagoProvider.facturasPendientes.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: AppColors.error),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: AppColors.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Pendiente',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '\$${pagoProvider.totalPendiente.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            final pago = pagoProvider.facturasPendientes[index - 1];
            return _buildPagoCard(context, pago, true);
          },
        );
      },
    );
  }

  Widget _buildPagoCard(
    BuildContext context,
    Map<String, dynamic> pago,
    bool esPendiente,
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
                        'Incidente #${pago['incidente_id']}',
                        style: Theme.of(
                          context,
                        ).textTheme.displayLarge?.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Taller: ${pago['taller']?['nombre'] ?? 'Desconocido'}',
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
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getColorEstado(pago['estado'] ?? 'pendiente'),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (pago['estado'] ?? 'PENDIENTE').toString().toUpperCase(),
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

            // Monto
            Text(
              'Monto: \$${pago['monto']?.toString() ?? '0.00'}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 8),

            // Método de pago
            Text(
              'Método: ${pago['metodo_pago'] ?? 'No especificado'}',
              style: const TextStyle(fontSize: 12),
            ),

            // Fecha
            Text(
              'Fecha: ${_formatearFecha(pago['fecha_pago'])}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),

            if (esPendiente) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _pagarAhora(context, pago),
                  child: const Text('Pagar Ahora'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getColorEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'pendiente':
        return Colors.orange;
      case 'completado':
      case 'pagado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
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

  Future<void> _pagarAhora(BuildContext context, Map<String, dynamic> pago) async {
    final pagoProvider = context.read<PagoProvider>();
    final pagoService = pagoProvider.pagoService; // Asegúrate de poder acceder a esto o pásalo

    try {
      // 1. Mostrar loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // 2. Obtener PaymentIntent desde backend
      final pagoId = pago['id'] ?? pago['pago_id'];
      if (pagoId == null) {
        throw Exception("ID de pago no encontrado");
      }
      
      final intentData = await pagoService.crearPaymentIntent(pagoId as int);

      // 3. Inicializar PaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intentData['paymentIntent'],
          merchantDisplayName: 'VialIA Auxilio',
          style: ThemeMode.system,
        ),
      );

      // 4. Mostrar PaymentSheet
      if (context.mounted) {
        Navigator.pop(context); // Quitar loading
      }
      await Stripe.instance.presentPaymentSheet();

      // 5. Confirmar pago al backend directamente (fallback en caso de que webhook no llegue localmente)
      await pagoService.confirmarPagoCliente(pagoId as int);

      // 6. Éxito
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Pago realizado con éxito!'),
            backgroundColor: Colors.green,
          ),
        );
        // Recargar listas
        final userId = context.read<AuthProvider>().userId;
        if (userId != null) {
          pagoProvider.cargarHistorialPagos(usuarioId: userId);
          pagoProvider.cargarFacturasPendientes(usuarioId: userId);
        }
      }
    } on StripeException catch (e) {
      if (context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pago cancelado: ${e.error.localizedMessage}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _mostrarDetallePago(BuildContext context, Map<String, dynamic> pago) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalles del Pago',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildDetalleRow('ID Pago:', '${pago['id'] ?? pago['pago_id']}'),
            _buildDetalleRow('Incidente ID:', '${pago['incidente_id']}'),
            _buildDetalleRow('Taller:', pago['taller']?['nombre'] ?? 'Desconocido'),
            _buildDetalleRow('Monto:', '\$${pago['monto']}'),
            _buildDetalleRow('Método:', '${pago['metodo_pago'] ?? 'No especificado'}'),
            _buildDetalleRow('Estado:', '${pago['estado'] ?? 'desconocido'}'.toUpperCase()),
            _buildDetalleRow('Fecha:', _formatearFecha(pago['fecha_pago'])),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetalleRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
