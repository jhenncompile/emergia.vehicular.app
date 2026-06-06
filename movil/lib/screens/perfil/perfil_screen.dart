import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/usuario_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/colors.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  @override
  void initState() {
    super.initState();
    // Cargar perfil al abrir la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UsuarioProvider>().cargarPerfil();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer2<UsuarioProvider, AuthProvider>(
        builder: (context, usuarioProvider, authProvider, _) {
          if (usuarioProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final perfil = usuarioProvider.perfil;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Avatar/Foto de perfil
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryColor, width: 2),
                  ),
                  child: Icon(
                    Icons.person,
                    size: 60,
                    color: AppColors.primaryColor,
                  ),
                ),
                const SizedBox(height: 24),

                // Información del usuario
                _buildPerfilInfo(context, perfil, authProvider),
                const SizedBox(height: 32),

                // Botones de acción
                _buildActionButtons(context),
                const SizedBox(height: 32),

                // Botón Cerrar Sesión
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _cerrarSesion(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cerrar Sesión',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPerfilInfo(
    BuildContext context,
    Map<String, dynamic>? perfil,
    AuthProvider authProvider,
  ) {
    if (perfil == null) {
      final nombre = authProvider.userName ?? authProvider.roleLabel;
      final correo = authProvider.userEmail ?? 'Correo no disponible';

      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.warning),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'No se pudo cargar el perfil completo. Mostrando datos de la sesion.',
              style: TextStyle(color: AppColors.warning),
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoCard(label: 'Nombre', value: nombre, icon: Icons.person),
          const SizedBox(height: 12),
          _buildInfoCard(label: 'Email', value: correo, icon: Icons.email),
          const SizedBox(height: 12),
          _buildInfoCard(
            label: 'Rol',
            value: authProvider.roleLabel,
            icon: Icons.badge_outlined,
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildInfoCard(
          label: 'Nombre',
          value: '${perfil['nombre'] ?? 'N/A'} ${perfil['apellido'] ?? ''}',
          icon: Icons.person,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          label: 'Email',
          value: perfil['correo'] ?? 'N/A',
          icon: Icons.email,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          label: 'Rol',
          value: authProvider.roleLabel,
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          label: 'Teléfono',
          value: perfil['telefono'] ?? 'No especificado',
          icon: Icons.phone,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          label: 'Ciudad',
          value: perfil['ciudad'] ?? 'No especificada',
          icon: Icons.location_city,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          label: 'Dirección',
          value: perfil['direccion'] ?? 'No especificada',
          icon: Icons.home,
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.secondaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _editarPerfil(context),
            child: const Text('Editar Información'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _cambiarContrasena(context),
            child: const Text('Cambiar Contraseña'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _ayuda(context),
            child: const Text('Centro de Ayuda'),
          ),
        ),
      ],
    );
  }

  void _editarPerfil(BuildContext context) {
    final perfil = context.read<UsuarioProvider>().perfil;

    final nombreController = TextEditingController(text: perfil?['nombre']);
    final apellidoController = TextEditingController(text: perfil?['apellido']);
    final telefonoController = TextEditingController(text: perfil?['telefono']);
    final ciudadController = TextEditingController(text: perfil?['ciudad']);
    final direccionController = TextEditingController(
      text: perfil?['direccion'],
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Información'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apellidoController,
                decoration: const InputDecoration(labelText: 'Apellido'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telefonoController,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ciudadController,
                decoration: const InputDecoration(labelText: 'Ciudad'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: direccionController,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final usuarioProvider = context.read<UsuarioProvider>();
              final success = await usuarioProvider.actualizarPerfil(
                nombre: nombreController.text,
                apellido: apellidoController.text,
                telefono: telefonoController.text,
                ciudad: ciudadController.text,
                direccion: direccionController.text,
              );

              if (!context.mounted) return;
              if (success) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Perfil actualizado'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      usuarioProvider.errorMessage ?? 'Operacion no disponible',
                    ),
                  ),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _cambiarContrasena(BuildContext context) {
    final actualController = TextEditingController();
    final nuevaController = TextEditingController();
    final confirmarController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar Contraseña'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: actualController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña Actual',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nuevaController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva Contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmarController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar Contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nuevaController.text != confirmarController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Las contraseñas no coinciden')),
                );
                return;
              }

              final usuarioProvider = context.read<UsuarioProvider>();
              final success = await usuarioProvider.cambiarContrasena(
                contrasenaActual: actualController.text,
                contrasenaNueva: nuevaController.text,
              );

              if (!context.mounted) return;
              if (success) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contraseña actualizada'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      usuarioProvider.errorMessage ?? 'Operacion no disponible',
                    ),
                  ),
                );
              }
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  void _ayuda(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Centro de Ayuda'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Preguntas Frecuentes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                '¿Cómo reporto un incidente?\n- Toca el botón "Reportar" en la pantalla de inicio\n- Selecciona tu vehículo\n- Describe el problema\n- Proporciona la ubicación\n\n',
              ),
              Text(
                '¿Cómo pagó mis facturas?\n- Ve a la sección "Pagos y Facturas"\n- Selecciona la factura pendiente\n- Toca "Pagar Ahora"\n\n',
              ),
              Text(
                '¿Necesitas más ayuda?\n- Contacta a nuestro equipo de soporte',
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

  void _cerrarSesion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final authProvider = context.read<AuthProvider>();
              await authProvider.logout();
              // El Consumer en main.dart detectará que isAuthenticated es false
              // y automáticamente mostrará LoginPage
              if (!context.mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }
}
