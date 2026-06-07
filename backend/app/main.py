"""
VialIA Backend - Emergency Vehicle Assistance System with AI Integration

Production-ready FastAPI application for emergency vehicle reporting with:
- Multimodal AI processing (audio transcription + image analysis)
- Hugging Face Inference API integration
- Comprehensive CORS configuration for Flutter mobile + Angular frontend
- Environment-based deployment (development/staging/production on Render)

Author: VialIA Team
License: MIT
"""

import os
import logging
import asyncio
from pathlib import Path
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import PlainTextResponse
from app.db.session import SessionLocal, engine
from app.db.base import Base
from app.api.v1.api import api_router
from app.websocket.manager import manager
from app.core.config import settings
from app.services.ranking_taller_service import RankingTallerService

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")


# ============================================================
# BACKGROUND WORKER
# ============================================================
async def assignment_timeout_worker():
    """Avanza ofertas de taller vencidas sin esperar una accion manual."""
    interval_seconds = int(os.getenv("ASSIGNMENT_TIMEOUT_CHECK_SECONDS", "30"))
    while True:
        await asyncio.sleep(interval_seconds)
        db = SessionLocal()
        try:
            procesados = RankingTallerService(db).procesar_ofertas_vencidas()
            if procesados:
                logger.info("Ofertas vencidas procesadas: %s", procesados)
        except Exception as exc:
            logger.exception("Error procesando ofertas vencidas: %s", exc)
        finally:
            db.close()


# ============================================================
# APPLICATION INITIALIZATION
# ============================================================
app = FastAPI(
    title="VialIA - Sistema de Asistencia Vehicular",
    description="Emergency vehicle reporting with AI-powered multimodal analysis",
    version="1.0.0",
)


# ============================================================
# MIDDLEWARE PERSONALIZADO PARA WEBSOCKET PREFLIGHT
# ============================================================
class WebSocketCORSMiddleware(BaseHTTPMiddleware):
    """Middleware para manejar preflight requests de WebSocket"""
    async def dispatch(self, request: Request, call_next):
        if request.method == "OPTIONS":
            return PlainTextResponse("OK", status_code=200, headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers": "*",
            })
        if request.url.path.startswith("/ws/"):
            return await call_next(request)
        return await call_next(request)


app.add_middleware(WebSocketCORSMiddleware)

# CORS para HTTP requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=3600,
)


# ============================================================
# API ROUTES
# ============================================================
app.include_router(api_router, prefix="/api/v1")

UPLOADS_ROOT = Path("uploads")
UPLOADS_ROOT.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_ROOT)), name="uploads")


# ============================================================
# HEALTH CHECK ENDPOINTS
# ============================================================
@app.get("/")
def root():
    """Root endpoint - API status check."""
    return {
        "message": "API de Asistencia Vehicular funcionando",
        "service": "VialIA Backend with AI Integration",
        "version": "1.0.0",
        "environment": ENVIRONMENT,
    }


@app.get("/health")
def health_check():
    """Health check endpoint for monitoring and deployment verification."""
    return {
        "status": "healthy",
        "service": "vialia-backend",
        "ai_enabled": os.getenv("HF_API_TOKEN") is not None,
    }


@app.get("/api/v1/health")
def legacy_health_check():
    """Endpoint para el revividor de GitHub Actions.
    No requiere auth y no genera registros en Bitácora."""
    return {
        "status": "online",
        "service": "Taller Pro API",
        "tenant_mode": "multi-tenant-enabled"
    }


@app.get("/ready")
def readiness_check():
    """Readiness check endpoint."""
    try:
        from app.db.session import SessionLocal
        db = SessionLocal()
        db.execute("SELECT 1")
        db.close()
        return {
            "ready": True,
            "database": "connected",
            "ai_service": "available" if os.getenv("HF_API_TOKEN") else "disabled",
        }
    except Exception as e:
        logger.error(f"Readiness check failed: {str(e)}")
        return {"ready": False, "error": str(e)}


@app.get("/ws-test")
def ws_test():
    """Test endpoint to verify FastAPI is working."""
    return {"status": "ok", "message": "FastAPI is running"}


# ============================================================
# WEBSOCKET ENDPOINT
# ============================================================
@app.websocket("/ws/{usuario_id}")
async def websocket_endpoint(websocket: WebSocket, usuario_id: int):
    """
    WebSocket endpoint para notificaciones en tiempo real.

    Conectar con: ws://host:8000/ws/{usuario_id}

    Envía notificaciones JSON:
    {
        "titulo": "...",
        "mensaje": "...",
        "tipo": "incidente_aceptado",
        "incidente_id": 5,
        "estado_nuevo": "asignado_taller"
    }

    El cliente puede enviar "ping" para mantener viva la conexión.
    """
    logger.info(f"🔌 WebSocket request: usuario_id={usuario_id}")

    try:
        await manager.connect(usuario_id, websocket)
        logger.info(f"✅ Usuario {usuario_id} conectado a WebSocket")

        # Mantener conexión abierta y escuchar heartbeat del cliente
        while True:
            try:
                data = await websocket.receive_text()
                if data == "ping":
                    await websocket.send_text("pong")
            except WebSocketDisconnect:
                logger.info(f"👋 Usuario {usuario_id} se desconectó limpiamente")
                break
            except Exception as receive_error:
                logger.debug(f"Error recibiendo datos WS usuario {usuario_id}: {str(receive_error)}")
                break

    except Exception as e:
        logger.error(f"❌ Error en WebSocket usuario {usuario_id}: {str(e)}")

    finally:
        # SIEMPRE limpiar la conexión del manager, sin importar cómo terminó.
        # Esto previene zombie connections que bloquean notificaciones futuras.
        manager.disconnect(usuario_id, websocket)
        logger.info(f"🧹 Conexión WS limpiada para usuario {usuario_id}")


# ============================================================
# STARTUP AND SHUTDOWN EVENTS
# ============================================================
@app.on_event("startup")
async def startup_event():
    """Initialize application on startup."""
    logger.info("=== VialIA Backend Starting ===")
    logger.info(f"Environment: {ENVIRONMENT}")

    # Check AI service configuration
    hf_token = os.getenv("HF_API_TOKEN")
    if hf_token:
        logger.info("✓ Hugging Face API Token configured - AI features enabled")
    else:
        logger.warning("✗ Hugging Face API Token not configured - AI features disabled")

    # Inicializar Firebase (FCM) si hay credenciales configuradas
    try:
        from app.core.firebase_config import inicializar_firebase
        inicializar_firebase()
    except ImportError:
        logger.info("ℹ️  Módulo firebase_config no encontrado - FCM deshabilitado")
    except Exception as e:
        logger.warning(f"⚠️  Firebase no inicializado: {str(e)}")

    # Initialize database
    logger.info("Initializing database tables...")
    Base.metadata.create_all(bind=engine)
    logger.info("✓ Database initialized")

    worker_enabled = os.getenv("ASSIGNMENT_TIMEOUT_WORKER_ENABLED", "true").lower()
    if worker_enabled not in {"0", "false", "no"}:
        app.state.assignment_timeout_task = asyncio.create_task(
            assignment_timeout_worker()
        )
        logger.info("✓ Assignment timeout worker enabled")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on application shutdown."""
    task = getattr(app.state, "assignment_timeout_task", None)
    if task:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
    logger.info("VialIA Backend shutting down...")
