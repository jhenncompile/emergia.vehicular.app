import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pago_provider.dart';
import '../../theme/colors.dart';

class PagosScreen extends StatefulWidget {
  const PagosScreen({super.key});

  @override
  State<PagosScreen> createState() => _PagosScreenState();
}

class _PagosScreenState extends State<PagosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

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
        title: const Text('Pagos y Facturas'),
        backgroundColor: AppColors.primaryColor,
        bottom: TabBar(
          controller: _tabController,
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
            return _buildPagoCard(context, pago, false);
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
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _pagarAhora(context, pago),
                      child: const Text('Pagar Ahora'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _descargarFactura(context, pago),
                      child: const Text('Ver Factura'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _descargarComprobante(context, pago),
                  child: const Text('Descargar Comprobante'),
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

  void _pagarAhora(BuildContext context, Map<String, dynamic> pago) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔄 Sistema de pago en desarrollo...')),
    );
  }

  void _descargarFactura(BuildContext context, Map<String, dynamic> pago) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('📥 Descargando factura...')));
  }

  void _descargarComprobante(BuildContext context, Map<String, dynamic> pago) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📥 Descargando comprobante...')),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
