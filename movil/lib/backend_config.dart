import 'package:flutter/foundation.dart';

/// Configuración centralizada de conexión al backend
/// ======================================================
/// Esta clase gestiona dinámicamente la URL del servidor según:
/// - Plataforma (Android, iOS, Web)
/// - Tipo de dispositivo (emulador vs físico)
/// - Variables de entorno
class BackendConfig {
  // ===== CONFIGURACIÓN GLOBAL =====
  static const String _defaultPort = '8000';
  static const String _localNetworkIp = '192.168.100.9';
  static const String _androidEmulatorHost = '10.0.2.2';

  // ===== URLS CONSTRUIDAS =====
  static const String _localDevUrl = 'http://localhost:$_defaultPort';
  static const String _localNetworkUrl =
      'http://$_localNetworkIp:$_defaultPort';
  static const String _androidEmulatorUrl =
      'http://$_androidEmulatorHost:$_defaultPort';

  /// URL del backend - automática por plataforma
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('BACKEND_URL');
    if (fromEnv.isNotEmpty) {
      debugPrint('[CONFIG] URL de variable de entorno: $fromEnv');
      return fromEnv;
    }

    if (kIsWeb) {
      debugPrint('[CONFIG] Web: $_localDevUrl');
      return _localDevUrl;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        debugPrint('[CONFIG] Android - Dispositivo físico: $_localNetworkUrl');
        return _localNetworkUrl;
      case TargetPlatform.iOS:
        debugPrint('[CONFIG] iOS - Dispositivo físico: $_localNetworkUrl');
        return _localNetworkUrl;
      default:
        return _localDevUrl;
    }
  }

  static String get androidEmulatorUrl => _androidEmulatorUrl;
  static String get physicalDeviceUrl => _localNetworkUrl;
  static String get localDevUrl => _localDevUrl;

  static void printDebugInfo() {
    debugPrint('[CONFIG] URL Base: $baseUrl');
    debugPrint('[CONFIG] Emulador Android: $_androidEmulatorUrl');
    debugPrint('[CONFIG] Dispositivo Físico: $_localNetworkUrl');
    debugPrint('[CONFIG] Localhost: $_localDevUrl');
  }
}
