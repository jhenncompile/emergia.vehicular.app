import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'backend_config.dart';
import 'providers/auth_provider.dart';
import 'providers/incidente_provider.dart';
import 'providers/notificacion_provider.dart';
import 'providers/pago_provider.dart';
import 'providers/realtime_provider.dart';
import 'providers/tecnico_provider.dart';
import 'providers/usuario_provider.dart';
import 'providers/vehiculo_provider.dart';
import 'screens/historial/historial_screen.dart';
import 'screens/incidentes/mis_incidentes_screen.dart';
import 'screens/incidentes/reportar_incidente_screen.dart';
import 'screens/incidentes/map_screen.dart';
import 'screens/pagos/pagos_screen.dart';
import 'screens/perfil/perfil_screen.dart';
import 'screens/servicios/mis_atenciones_screen.dart';
import 'screens/vehiculos/mis_vehiculos_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/incidente_service.dart';
import 'services/location_tracking_service.dart';
import 'services/notificacion_service.dart';
import 'services/pago_service.dart';
import 'services/realtime_service.dart';
import 'services/taller_service.dart';
import 'services/tracking_service.dart';
import 'services/usuario_service.dart';
import 'services/vehiculo_service.dart';
import 'theme/colors.dart';
import 'services/local_notification_service.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Manejando mensaje FCM en segundo plano: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("Error inicializando Firebase: $e");
  }
  await LocalNotificationService().initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final backendUrl = BackendConfig.baseUrl;

    return MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService(baseUrl: backendUrl)),
        Provider<RealtimeService>(
          create: (_) => RealtimeService(baseUrl: backendUrl),
        ),
        Provider<AuthService>(
          create: (context) =>
              AuthService(apiService: context.read<ApiService>()),
        ),
        Provider<IncidenteService>(
          create: (context) =>
              IncidenteService(apiService: context.read<ApiService>()),
        ),
        Provider<VehiculoService>(
          create: (context) =>
              VehiculoService(apiService: context.read<ApiService>()),
        ),
        Provider<PagoService>(
          create: (context) =>
              PagoService(apiService: context.read<ApiService>()),
        ),
        Provider<NotificacionService>(
          create: (context) =>
              NotificacionService(apiService: context.read<ApiService>()),
        ),
        Provider<UsuarioService>(
          create: (context) =>
              UsuarioService(apiService: context.read<ApiService>()),
        ),
        Provider<TallerService>(
          create: (context) =>
              TallerService(apiService: context.read<ApiService>()),
        ),
        Provider<LocationTrackingService>(
          create: (_) => LocationTrackingService(),
        ),
        Provider<TrackingService>(
          create: (context) =>
              TrackingService(apiService: context.read<ApiService>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              AuthProvider(authService: context.read<AuthService>()),
        ),
        ChangeNotifierProvider(
          create: (context) => IncidenteProvider(
            incidenteService: context.read<IncidenteService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => VehiculoProvider(
            vehiculoService: context.read<VehiculoService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              PagoProvider(pagoService: context.read<PagoService>()),
        ),
        ChangeNotifierProvider(
          create: (context) => NotificacionProvider(
            notificacionService: context.read<NotificacionService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              UsuarioProvider(usuarioService: context.read<UsuarioService>()),
        ),
        ChangeNotifierProvider(
          create: (context) => TecnicoProvider(
            incidenteService: context.read<IncidenteService>(),
            locationService: context.read<LocationTrackingService>(),
            trackingService: context.read<TrackingService>(),
          ),
        ),
        ChangeNotifierProxyProvider2<
          AuthProvider,
          IncidenteProvider,
          RealtimeProvider
        >(
          lazy: false,
          create: (context) => RealtimeProvider(
            realtimeService: context.read<RealtimeService>(),
          ),
          update: (context, authProvider, incidenteProvider, realtimeProvider) {
            final provider =
                realtimeProvider ??
                RealtimeProvider(
                  realtimeService: context.read<RealtimeService>(),
                );
            provider.sync(
              authProvider: authProvider,
              incidenteProvider: incidenteProvider,
            );
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        debugShowCheckedModeBanner: false,
        title: 'Emergencia Vehicular',
        theme: appTheme,
        home: Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            if (authProvider.isCheckingAuth) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            return authProvider.isAuthenticated
                ? const HomePage()
                : const LoginPage();
          },
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos')),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(email, password);

    if (!mounted) return;
    if (success) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(authProvider.errorMessage ?? 'Error al iniciar sesion'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Text(
                    'Asistencia Vehicular',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Acceso para clientes y tecnicos',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textLight),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      hintText: 'Correo',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: 'Contrasena',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: authProvider.isLoading
                              ? null
                              : _handleLogin,
                          child: authProvider.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text('Iniciar sesion'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _registrarTokenDispositivo();
    });
  }

  Future<void> _registrarTokenDispositivo() async {
    final authProvider = context.read<AuthProvider>();
    final notificacionProvider = context.read<NotificacionProvider>();
    final userId = authProvider.userId;
    if (userId != null) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token == null) {
          debugPrint('[FCM] No se pudo obtener el token de Firebase');
          return;
        }
        
        final plataforma = Theme.of(context).platform == TargetPlatform.android
            ? 'android'
            : 'ios';
            
        debugPrint('[FCM] Intentando registrar token FCM para usuario $userId...');
        await notificacionProvider.registrarTokenDispositivo(
          usuarioId: userId,
          tokenFCM: token,
          plataforma: plataforma,
        );
        debugPrint('[FCM] Token FCM registrado exitosamente');
      } catch (e) {
        debugPrint('[FCM] Error al registrar token: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final esTecnico = authProvider.isTecnico;
    final pages = esTecnico
        ? <Widget>[
            TecnicoDashboard(
              onNavigate: (index) => setState(() => _selectedIndex = index),
            ),
            const MisIncidentesScreen(),
            const HistorialScreen(),
            const PerfilScreen(),
          ]
        : const <Widget>[
            HomeDashboard(),
            MisAtencionesScreen(),
            HistorialScreen(),
            PerfilScreen(),
          ];
    final items = esTecnico
        ? const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              label: 'Asignados',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'Historial',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Perfil',
            ),
          ]
        : const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.build_circle_outlined),
              label: 'Atenciones',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'Historial',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Perfil',
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(esTecnico ? 'Panel Tecnico' : 'Asistencia Vehicular'),
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: AppColors.primaryColor,
        type: BottomNavigationBarType.fixed,
        items: items,
      ),
    );
  }
}

class TecnicoDashboard extends StatefulWidget {
  const TecnicoDashboard({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  State<TecnicoDashboard> createState() => _TecnicoDashboardState();
}

class _TecnicoDashboardState extends State<TecnicoDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cargarIncidentes();
    });
  }

  Future<void> _cargarIncidentes() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.userId;
    if (userId == null) return;

    final incidenteProvider = context.read<IncidenteProvider>();
    final tecnicoProvider = authProvider.isTecnico
        ? context.read<TecnicoProvider>()
        : null;

    await incidenteProvider.cargarMisIncidentes(
      usuarioId: userId,
      esTecnico: authProvider.isTecnico,
    );

    if (!mounted) return;

    // Cargar incidente activo en TecnicoProvider para seguimiento
    if (tecnicoProvider != null) {
      await tecnicoProvider.cargarIncidenteActivo(usuarioId: userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IncidenteProvider>(
      builder: (context, incidenteProvider, _) {
        final incidentes = incidenteProvider.misIncidentes;
        final activos = incidentes.where(_esIncidenteActivo).length;
        final historico = incidentes.where(_esIncidenteHistorico).length;

        return RefreshIndicator(
          onRefresh: _cargarIncidentes,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.info,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.engineering_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sesion tecnica activa. Revisa tus incidentes asignados.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (incidenteProvider.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              _actionCard(
                context,
                color: AppColors.secondaryColor,
                icon: Icons.assignment_outlined,
                title: 'Incidentes asignados',
                subtitle: '$activos activos de ${incidentes.length} asignados',
                onTap: () {
                  if (activos == 1) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MapScreen()),
                    );
                  } else {
                    widget.onNavigate(1);
                  }
                },
              ),
              _actionCard(
                context,
                color: const Color(0xFF2563EB),
                icon: Icons.history,
                title: 'Historico de servicios',
                subtitle: '$historico incidentes finalizados o cancelados',
                onTap: () => widget.onNavigate(2),
              ),
              _actionCard(
                context,
                color: AppColors.accentColor,
                icon: Icons.person_outline,
                title: 'Mis datos',
                subtitle: 'Perfil y datos de sesion',
                onTap: () => widget.onNavigate(3),
              ),
              if (incidentes.isEmpty && !incidenteProvider.isLoading)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: const [
                        Icon(
                          Icons.assignment_late_outlined,
                          color: Colors.grey,
                          size: 48,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Aun no tienes incidentes asignados',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Cuando el taller te asigne uno, aparecera aqui.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _esIncidenteActivo(Map<String, dynamic> incidente) {
    final estado = (incidente['estado'] ?? '').toString().toLowerCase();
    return estado == 'pendiente' ||
        estado == 'buscando_taller' ||
        estado == 'asignado_taller' ||
        estado == 'en_camino' ||
        estado == 'en_atencion';
  }

  bool _esIncidenteHistorico(Map<String, dynamic> incidente) {
    final estado = (incidente['estado'] ?? '').toString().toLowerCase();
    return estado == 'finalizado' ||
        estado == 'completado' ||
        estado == 'cancelado';
  }

  Widget _actionCard(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: color,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cargarIncidentes();
    });
  }

  Future<void> _cargarIncidentes() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.userId;
    if (userId == null) return;
    await context.read<IncidenteProvider>().cargarMisIncidentes(
      usuarioId: userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IncidenteProvider>(
      builder: (context, incidenteProvider, child) {
        final activo = incidenteProvider.incidenteActivoCliente;
        
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (activo != null)
              Card(
                color: Colors.orange.shade700,
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MapScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                            const SizedBox(width: 8),
                            const Text('Incidente Activo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                              child: Text(
                                (activo['estado'] ?? '').toString().toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          activo['descripcion'] ?? 'Sin descripción',
                          style: const TextStyle(color: Colors.white),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Text('Toca para ver el mapa en tiempo real', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Spacer(),
                            Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14)
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Estado: Activo. Listo para reportar incidentes.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        _actionCard(
          context,
          color: AppColors.secondaryColor,
          icon: Icons.warning_amber_rounded,
          title: 'Reportar Incidente',
          subtitle: 'Describe tu emergencia',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ReportarIncidenteScreen(),
              ),
            );
          },
        ),
        _actionCard(
          context,
          color: const Color(0xFF2563EB),
          icon: Icons.build_circle_outlined,
          title: 'Mis Atenciones',
          subtitle: 'Servicios activos y pendientes',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MisAtencionesScreen()),
            );
          },
        ),
        _actionCard(
          context,
          color: AppColors.accentColor,
          icon: Icons.directions_car_outlined,
          title: 'Mis Vehiculos',
          subtitle: 'Gestiona tus vehiculos',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MisVehiculosScreen()),
            );
          },
        ),
        _actionCard(
          context,
          color: const Color(0xFF7E22CE),
          icon: Icons.payment_outlined,
          title: 'Pagos y Facturas',
          subtitle: 'Modulo disponible parcialmente',
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PagosScreen()));
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MisIncidentesScreen()),
            );
          },
          icon: const Icon(Icons.list_alt_outlined),
          label: const Text('Ver mis reportes'),
        ),
      ],
    );
   },
  );
 }

  Widget _actionCard(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: color,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
