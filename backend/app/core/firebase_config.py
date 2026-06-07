"""
Configuración centralizada de Firebase Admin SDK para FCM (notificaciones push).

Para activar FCM:
1. Ir a Firebase Console → Configuración del proyecto → Cuentas de servicio
2. Generar nueva clave privada → descargar JSON
3. Guardar el archivo como: backend/serviceAccountKey.json
   O configurar la variable de entorno GOOGLE_APPLICATION_CREDENTIALS con la ruta al JSON.

Sin esas credenciales, el backend funciona normalmente pero FCM estará deshabilitado.
Las notificaciones por WebSocket siguen funcionando independientemente.
"""

import os
import logging

logger = logging.getLogger(__name__)

_firebase_initialized = False


def inicializar_firebase() -> bool:
    """
    Inicializa Firebase Admin SDK si hay credenciales disponibles.

    Busca credenciales en este orden:
    1. Variable de entorno GOOGLE_APPLICATION_CREDENTIALS (ruta al JSON)
    2. Archivo serviceAccountKey.json en el directorio del backend

    Returns:
        True si Firebase se inicializó correctamente, False en caso contrario.
    """
    global _firebase_initialized

    if _firebase_initialized:
        return True

    try:
        import firebase_admin
        from firebase_admin import credentials

        # Verificar si ya está inicializado (evitar doble init)
        if firebase_admin._apps:
            _firebase_initialized = True
            logger.info("✅ Firebase Admin SDK ya estaba inicializado")
            return True

        # Opción 1: Variable de entorno GOOGLE_APPLICATION_CREDENTIALS
        creds_env = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        if creds_env and os.path.exists(creds_env):
            cred = credentials.Certificate(creds_env)
            firebase_admin.initialize_app(cred)
            _firebase_initialized = True
            logger.info(f"✅ Firebase inicializado con credenciales desde env: {creds_env}")
            return True

        # Opción 2: Archivo local serviceAccountKey.json
        local_key_path = os.path.join(os.path.dirname(__file__), "..", "..", "serviceAccountKey.json")
        local_key_path = os.path.normpath(local_key_path)
        if os.path.exists(local_key_path):
            cred = credentials.Certificate(local_key_path)
            firebase_admin.initialize_app(cred)
            _firebase_initialized = True
            logger.info(f"✅ Firebase inicializado con serviceAccountKey.json local")
            return True

        # No hay credenciales disponibles
        logger.info(
            "ℹ️  Firebase no configurado (FCM deshabilitado). "
            "Para activar FCM, configura GOOGLE_APPLICATION_CREDENTIALS o agrega serviceAccountKey.json. "
            "Las notificaciones por WebSocket siguen funcionando normalmente."
        )
        return False

    except ImportError:
        logger.info(
            "ℹ️  firebase-admin no instalado (FCM deshabilitado). "
            "Instalar con: pip install firebase-admin"
        )
        return False
    except Exception as e:
        logger.error(f"❌ Error inicializando Firebase: {str(e)}")
        return False


def firebase_disponible() -> bool:
    """Retorna True si Firebase está inicializado y listo para enviar FCM."""
    return _firebase_initialized
