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
from pathlib import Path
from typing import List
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import PlainTextResponse
from app.db.session import engine
from app.db.base import Base  # Importamos el que tiene todos los modelos
from app.api.v1.api import api_router
from app.websocket.manager import manager
from app.core.config import settings

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
cors_origins = ["*"]  # Allow all origins in development

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
        # Si es OPTIONS request (preflight), responder OK
        if request.method == "OPTIONS":
            return PlainTextResponse("OK", status_code=200, headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers": "*",
            })
        
        # Para WebSocket, dejar pasar sin modificar headers
        # (WebSocket no es una respuesta HTTP normal y no soporta header modification)
        if request.url.path.startswith("/ws/"):
            return await call_next(request)
        
        # Para otros requests, procesar normalmente
        return await call_next(request)


app.add_middleware(WebSocketCORSMiddleware)

# ============================================================
# CORS CONFIGURATION
# Middleware personalizado ya maneja WebSocket preflight
# ============================================================

# Log CORS configuration
logger.info(f"Environment: development")
logger.info("✅ WebSocket CORS manejado por middleware personalizado")

# CORS para HTTP requests (no WebSocket)
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
# Incluimos el router maestro con todos los endpoints
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


@app.get("/ready")
def readiness_check():
    """Readiness check endpoint - ensures all dependencies are available."""
    try:
        # Check database connection
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
        return {
            "ready": False,
            "error": str(e),
        }


@app.get("/ws-test")
def ws_test():
    """Test endpoint to verify FastAPI is working."""
    return {"status": "ok", "message": "FastAPI is running"}


# ============================================================
# WEBSOCKET ENDPOINT (Direct on app, not in router)
# ============================================================
@app.websocket("/ws/{usuario_id}")
async def websocket_endpoint(websocket: WebSocket, usuario_id: int):
    """
    WebSocket endpoint for real-time notifications.
    
    Connect with: ws://localhost:8000/ws/{usuario_id}
    
    Sends JSON notifications:
    {
        "titulo": "...",
        "mensaje": "...",
        "tipo": "incident_type",
        "incidente_id": 5
    }
    """
    # Debug headers
    print(f"\n🔍 DEBUG WebSocket Request:")
    print(f"  Path: {websocket.url.path}")
    print(f"  Headers: {dict(websocket.headers)}")
    print(f"  usuario_id: {usuario_id}")
    logger.info(f"🔌 WebSocket request: usuario_id={usuario_id}, origin={websocket.headers.get('origin', 'N/A')}")
    
    try:
        print(f"✅ Acceptando conexión para usuario {usuario_id}")
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
        manager.disconnect(usuario_id, websocket)


# ============================================================
# STARTUP AND SHUTDOWN EVENTS
# ============================================================
@app.on_event("startup")
async def startup_event():
    """Initialize application on startup."""
    logger.info("=== VialIA Backend Starting ===")
    logger.info(f"Environment: {ENVIRONMENT}")
    logger.info(f"CORS Configuration: {len(cors_origins)} allowed origins")
    
    # Check AI service configuration
    hf_token = os.getenv("HF_API_TOKEN")
    if hf_token:
        logger.info("✓ Hugging Face API Token configured - AI features enabled")
    else:
        logger.warning("✗ Hugging Face API Token not configured - AI features disabled")
    
    # Initialize database
    logger.info("Initializing database tables...")
    Base.metadata.create_all(bind=engine)
    logger.info("✓ Database initialized")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on application shutdown."""
    logger.info("VialIA Backend shutting down...")
