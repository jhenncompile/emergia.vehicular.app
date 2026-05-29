import os
import logging
from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import PlainTextResponse
from app.api.v1.api import api_router
from app.websocket.manager import manager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Cargar .env solo si existe (en Render se usan Variables de Entorno del Dashboard)
if os.path.exists(".env"):
    load_dotenv()

app = FastAPI(title="Taller Pro - Gestión de Emergencias")

# --- MIDDLEWARE PERSONALIZADO PARA WEBSOCKET ---
class WebSocketCORSMiddleware(BaseHTTPMiddleware):
    """Middleware para manejar preflight requests de WebSocket"""
    async def dispatch(self, request: Request, call_next):
        # Si es OPTIONS request (preflight), responder OK
        if request.method == "OPTIONS":
            return PlainTextResponse("OK", status_code=200, headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers": "*",
            })
        
        # Para WebSocket, dejar pasar sin modificar headers
        if request.url.path.startswith("/ws/"):
            return await call_next(request)
        
        # Para otros requests, procesar normalmente
        return await call_next(request)


app.add_middleware(WebSocketCORSMiddleware)

# --- CONFIGURACIÓN DE CORS ---
# Obtenemos la URL del frontend desde el entorno para no dejar "*" en producción
FRONTEND_URL = os.getenv("FRONTEND_URL", "https://taller-pro-client.onrender.com")
DEVELOPMENT_MODE = os.getenv("DEBUG", "False").lower() == "true"

origins = [
    # Frontend Web (Angular)
    "http://localhost:4200",
    "https://emergencia-vehicular-1.onrender.com",
    FRONTEND_URL,
    # Frontend Mobile (Ionic/Angular)
    "http://localhost:8100",
    "https://emergencia-vehicular-1.onrender.com",
    FRONTEND_URL, # Dominio de producción
]

# Filtrar URLs vacías
origins = [origin for origin in origins if origin.strip()]

# En DESARROLLO: permitir "*" para facilitar testing en red local
if DEVELOPMENT_MODE:
    print("[⚠️  DESARROLLO] CORS configurado con '*' - ¡NO usar en producción!")
    origins = ["*"]  # Permite todas las URLs en desarrollo

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- ENDPOINTS PÚBLICOS (Revividor) ---

@app.get("/api/v1/health")
def health_check():
    """Endpoint para el revividor de GitHub Actions. 
    No requiere auth y no genera registros en Bitácora."""
    return {
        "status": "online",
        "service": "Taller Pro API",
        "tenant_mode": "multi-tenant-enabled"
    }

# --- ROUTER PRINCIPAL ---
app.include_router(api_router, prefix="/api/v1")

@app.get("/")
def root():
    return {"message": "API de Asistencia Vehicular funcionando"}


# ============================================================
# WEBSOCKET ENDPOINT - Real-time Notifications
# ============================================================
@app.websocket("/ws/{usuario_id}")
async def websocket_endpoint(websocket: WebSocket, usuario_id: int):
    """
    WebSocket endpoint for real-time notifications.
    
    Connect with: ws://localhost:8000/ws/{usuario_id}
    """
    logger.info(f"🔌 WebSocket request: usuario_id={usuario_id}")
    
    try:
        logger.info(f"✅ Acceptando conexión para usuario {usuario_id}")
        await manager.connect(usuario_id, websocket)
        logger.info(f"✅ Usuario {usuario_id} conectado a WebSocket")
        
        # Mantener conexión abierta (escuchar heartbeat del cliente)
        try:
            while True:
                try:
                    data = await websocket.receive_text()
                    # El cliente envía "ping" para mantener viva la conexión
                    if data == "ping":
                        await websocket.send_text("pong")
                except Exception as receive_error:
                    logger.debug(f"Error recibiendo datos WebSocket usuario {usuario_id}: {str(receive_error)}")
                    break
        except Exception as e:
            logger.error(f"Error en loop WebSocket usuario {usuario_id}: {str(e)}")
    
    except WebSocketDisconnect:
        manager.disconnect(usuario_id, websocket)
        logger.info(f"👋 WebSocket desconectado para usuario {usuario_id}")
    except Exception as e:
        logger.error(f"❌ Error en WebSocket usuario {usuario_id}: {str(e)}")
        try:
            manager.disconnect(usuario_id, websocket)
        except:
            pass