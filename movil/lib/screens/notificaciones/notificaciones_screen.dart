import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notificacion_provider.dart';
import '../../theme/colors.dart';
import 'package:intl/intl.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cargarNotificaciones();
    });
  }

  Future<void> _cargarNotificaciones() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId != null) {
      await context
          .read<NotificacionProvider>()
          .cargarHistorialNotificaciones(usuarioId: userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer<NotificacionProvider>(
        builder: (context, notificacionProvider, child) {
          if (notificacionProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final notificaciones = notificacionProvider.notificacionesNoLeidas;

          if (notificaciones.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes notificaciones',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _cargarNotificaciones,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notificaciones.length,
              itemBuilder: (context, index) {
                final notificacion = notificaciones[index];
                final esNoLeida = notificacion['leido'] != true;
                final fecha = DateTime.tryParse(notificacion['fecha_creacion'] ?? '');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: esNoLeida ? AppColors.info.withValues(alpha: 0.1) : Colors.white,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: _getColorParaTipo(notificacion['tipo_evento'] ?? ''),
                      child: Icon(
                        _getIconParaTipo(notificacion['tipo_evento'] ?? ''),
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      notificacion['titulo'] ?? 'Notificación',
                      style: TextStyle(
                        fontWeight: esNoLeida ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(notificacion['mensaje'] ?? ''),
                        const SizedBox(height: 8),
                        if (fecha != null)
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(fecha),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                    onTap: esNoLeida
                        ? () {
                            final userId = context.read<AuthProvider>().userId;
                            context.read<NotificacionProvider>().marcarComoLeida(
                                  notificacionId: notificacion['id'],
                                  usuarioId: userId ?? 0,
                                );
                            // Actualizamos localmente para refrescar la UI sin recargar
                            setState(() {
                              notificacion['leido'] = true;
                            });
                          }
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Color _getColorParaTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'incidente_aceptado':
        return AppColors.success;
      case 'llegada_taller':
        return AppColors.info;
      case 'pago_generado':
        return Colors.green;
      case 'oferta_recibida':
        return Colors.amber.shade700;
      default:
        return AppColors.secondaryColor;
    }
  }

  IconData _getIconParaTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'incidente_aceptado':
        return Icons.check_circle_outline;
      case 'llegada_taller':
        return Icons.build_circle_outlined;
      case 'pago_generado':
        return Icons.payment;
      case 'oferta_recibida':
        return Icons.local_offer_outlined;
      default:
        return Icons.notifications_active;
    }
  }
}
