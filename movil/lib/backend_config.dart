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

  /// Backend (API FastAPI) de producción desplegado en Render.
  /// El APK release distribuido en la web usa esta URL.
  /// Nota: el frontend web vive en emergencia-vehicular-1.onrender.com;
  /// la API es este host (sin el sufijo -1).
  static const String _renderUrl = 'https://emergencia-vehicular.onrender.com';

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

    // En compilaciones release (APK distribuido para pruebas) siempre se
    // apunta al backend de producción en Render, sin importar la plataforma.
    if (kReleaseMode) {
      debugPrint('[CONFIG] Release: $_renderUrl');
      return _renderUrl;
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
