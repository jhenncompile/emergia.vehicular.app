from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from typing import List
import logging

from app.api import deps
from app.crud.crud_notificacion import notificacion_crud, token_crud
from app.schemas.notificacion import (
    Notificacion, NotificacionCreate, NotificacionUpdate,
    TokenDispositivo, TokenDispositivoCreate
)
from app.websocket.manager import manager

logger = logging.getLogger(__name__)
router = APIRouter()

# --- ENDPOINTS DE TOKENS (Dispositivos) ---

@router.post("/tokens", response_model=TokenDispositivo)
def registrar_token_dispositivo(
    *,
    db: Session = Depends(deps.get_db),
    obj_in: TokenDispositivoCreate
):
    """
    Registra el token de Firebase (FCM) del celular del usuario.
    """
    return token_crud.create(db, obj_in=obj_in, usuario_id=obj_in.usuario_id)

# --- ENDPOINTS DE NOTIFICACIONES ---

@router.get("/usuario/{usuario_id}/pendientes", response_model=List[Notificacion])
def leer_notificaciones_no_leidas(
    usuario_id: int,
    db: Session = Depends(deps.get_db)
):
    """
    Lista todas las alertas que el usuario aún no ha visto.
    """
    return notificacion_crud.obtener_no_leidas(db, usuario_id=usuario_id)

@router.get("/usuario/{usuario_id}/historial", response_model=List[Notificacion])
def obtener_historial_notificaciones(
    usuario_id: int,
    db: Session = Depends(deps.get_db)
):
    """
    Lista TODAS las notificaciones del usuario (leídas y no leídas), ordenadas por fecha descendente.
    """
    return notificacion_crud.obtener_historial(db, usuario_id=usuario_id)

@router.patch("/{id}/leer", response_model=Notificacion)
def marcar_como_leida(
    id: int,
    db: Session = Depends(deps.get_db),
    usuario_id: int = 0 # Para la bitácora
):
    """
    Cambia el estado de una notificación a 'leída'.
    """
    notificacion_db = notificacion_crud.get(db, id=id)
    if not notificacion_db:
        raise HTTPException(status_code=404, detail="Notificación no encontrada")
    
    return notificacion_crud.update(
        db, 
        db_obj=notificacion_db, 
        obj_in={"leido": True}, 
        usuario_id=usuario_id
    )

@router.post("/", response_model=Notificacion)
def crear_notificacion_manual(
    *,
    db: Session = Depends(deps.get_db),
    obj_in: NotificacionCreate
):
    """
    Permite al sistema enviar una notificación a un usuario (ej. aviso de pago o emergencia).
    """
    return notificacion_crud.create(db, obj_in=obj_in, usuario_id=obj_in.usuario_id)

# --- WEBSOCKET PARA NOTIFICACIONES EN TIEMPO REAL ---

@router.websocket("/ws/{usuario_id}")
async def websocket_notificaciones(websocket: WebSocket, usuario_id: int):
    """
    WebSocket para recibir notificaciones en tiempo real.
    
    Cliente se conecta con: ws://localhost:8000/notificaciones/ws/{usuario_id}
    
    Envía notificaciones JSON:
    {
        "titulo": "...",
        "mensaje": "...",
        "tipo": "incidente_aceptado",
        "incidente_id": 5
    }
    """
    try:
        # Registrar conexión
        await manager.connect(usuario_id, websocket)
        
        # Mantener conexión abierta (escuchar heartbeat del cliente)
        while True:
            data = await websocket.receive_text()
            # El cliente envía "ping" para mantener viva la conexión
            if data == "ping":
                await websocket.send_text("pong")
    
    except WebSocketDisconnect:
        manager.disconnect(usuario_id, websocket)
        logger.info(f"WebSocket desconectado para usuario {usuario_id}")
    except Exception as e:
        logger.error(f"Error en WebSocket usuario {usuario_id}: {str(e)}")
        manager.disconnect(usuario_id, websocket)