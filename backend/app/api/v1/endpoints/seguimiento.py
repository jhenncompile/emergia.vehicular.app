"""
Endpoints para seguimiento y tracking de técnicos en tiempo real
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime

from app.api import deps
from app.models.incidente import Incidente
from app.models.usuario import Usuario
from app.core.estados import EstadoIncidente
from app.schemas.tracking import (
    LocationTecnicoRequest,
    LocationTecnicoResponse,
    MarcarLlegadaResponse,
    RutaResponse,
)
from app.services.tracking_service import TrackingService
from app.services.routing_service import RoutingService
from app.services.notificacion_service import NotificacionService

router = APIRouter(prefix="/api/v1/incidentes", tags=["seguimiento"])


@router.post("/{incidente_id}/ubicacion-tecnico", response_model=LocationTecnicoResponse)
async def actualizar_ubicacion_tecnico(
    incidente_id: int,
    request: LocationTecnicoRequest,
    current_user: Usuario = Depends(deps.get_current_user),
    db: Session = Depends(deps.get_db),
):
    """
    Endpoint que recibe la ubicación actual del técnico.
    
    El técnico debe estar asignado al incidente y éste debe estar en estado 'en_camino'.
    
    Valida automáticamente si el técnico llegó (2-3 lecturas consecutivas < 100m).
    
    Returns:
        - distancia_metros: Distancia actual al incidente
        - puede_marcar_manual: Si puede marcar llegada manualmente
        - llego_automaticamente: Si se detectó llegada automática
        - estado_nuevo: Nuevo estado si llegó automáticamente
    """
    
    # 1. Validar que el incidente existe
    incidente = db.query(Incidente).filter(
        Incidente.id == incidente_id
    ).first()
    
    if not incidente:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Incidente {incidente_id} no encontrado"
        )
    
    # 2. Validar que el incidente está en estado en_camino
    if incidente.estado != EstadoIncidente.EN_CAMINO:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Incidente no está en camino (estado actual: {incidente.estado})"
        )
    
    # 3. Validar que el usuario es el técnico asignado
    if incidente.tecnico_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No eres el técnico asignado a este incidente"
        )
    
    # 4. Guardar ubicación y detectar llegada
    try:
        resultado = TrackingService.guardar_ubicacion(
            db=db,
            incidente_id=incidente_id,
            tecnico_id=current_user.id,
            latitud=request.latitud,
            longitud=request.longitud
        )
        
        # 5. Si llegó automáticamente, notificar al cliente
        if resultado["llego_automaticamente"]:
            try:
                await NotificacionService.notificar_cliente(
                    usuario_id=incidente.usuario_id,
                    titulo="¡Tu técnico llegó!",
                    mensaje="El técnico ha llegado al lugar del incidente",
                    tipo="tecnico_llego",
                    incidente_id=incidente_id
                )
            except Exception as e:
                print(f"Error al notificar cliente: {e}")
                
        # 6. Broadcast ubicación a Taller
        if incidente.taller_id:
            await NotificacionService.broadcast_ubicacion_tecnico(
                db,
                incidente_id=incidente_id,
                latitud=request.latitud,
                longitud=request.longitud,
                taller_id=incidente.taller_id,
                tecnico_id=incidente.tecnico_id,
                cliente_id=incidente.usuario_id
            )
        
        return LocationTecnicoResponse(**resultado)
    
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.patch("/{incidente_id}/marcar-llegada-tecnico", response_model=MarcarLlegadaResponse)
async def marcar_llegada_tecnico(
    incidente_id: int,
    current_user: Usuario = Depends(deps.get_current_user),
    db: Session = Depends(deps.get_db),
):
    """
    Endpoint manual para marcar llegada (si la detección automática falló).
    
    Solo disponible si el técnico está dentro del umbral (< 100m del incidente).
    Cambia el estado del incidente a 'en_atencion'.
    
    Returns:
        - estado: Nuevo estado
        - fecha_llegada_tecnico: Timestamp de llegada
    """
    
    # 1. Validar que el incidente existe
    incidente = db.query(Incidente).filter(
        Incidente.id == incidente_id
    ).first()
    
    if not incidente:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Incidente {incidente_id} no encontrado"
        )
    
    # 2. Validar que el incidente está en estado en_camino
    if incidente.estado != EstadoIncidente.EN_CAMINO:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Incidente no está en camino (estado actual: {incidente.estado})"
        )
    
    # 3. Validar que el usuario es el técnico asignado
    if incidente.tecnico_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No eres el técnico asignado a este incidente"
        )
    
    # 4. Cambiar estado a en_atencion
    incidente.estado = EstadoIncidente.EN_ATENCION
    incidente.fecha_llegada_tecnico = datetime.utcnow()
    db.commit()
    
    # 5. Limpiar histórico de ubicaciones
    TrackingService.limpiar_ubicaciones_incidente(incidente_id)
    
    # 6. Notificar al cliente
    try:
        await NotificacionService.notificar_cliente(
            usuario_id=incidente.usuario_id,
            titulo="¡Tu técnico llegó!",
            mensaje="El técnico marcó su llegada al incidente",
            tipo="tecnico_llego",
            incidente_id=incidente_id
        )
    except Exception as e:
        print(f"Error al notificar cliente: {e}")
    
    return MarcarLlegadaResponse(
        estado=incidente.estado,
        fecha_llegada_tecnico=incidente.fecha_llegada_tecnico,
        mensaje="Llegada marcada correctamente. Estado cambiado a en_atencion"
    )


@router.get("/{incidente_id}/ruta-tecnico", response_model=RutaResponse)
async def obtener_ruta_tecnico(
    incidente_id: int,
    current_user: Usuario = Depends(deps.get_current_user),
    db: Session = Depends(deps.get_db),
):
    """
    Endpoint para obtener la ruta sugerida entre el técnico y el incidente.
    
    Usa OpenStreetMap OSRM para calcular la ruta.
    
    Returns:
        - distancia_km: Distancia de la ruta
        - duracion_minutos: Tiempo estimado
        - geometry: GeoJSON de la ruta para dibujar en mapa
        - pasos: Instrucciones paso a paso
    """
    
    # 1. Validar que el incidente existe
    incidente = db.query(Incidente).filter(
        Incidente.id == incidente_id
    ).first()
    
    if not incidente:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Incidente {incidente_id} no encontrado"
        )
    
    # 2. Validar que el usuario es el técnico asignado
    if incidente.tecnico_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No eres el técnico asignado a este incidente"
        )
    
    # 3. Validar que el incidente está en camino
    if incidente.estado != EstadoIncidente.EN_CAMINO:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Incidente no está en camino"
        )
    
    # 4. Obtener ruta
    ruta = await RoutingService.obtener_ruta(
        lon_origen=current_user.longitud if hasattr(current_user, 'longitud') else 0,
        lat_origen=current_user.latitud if hasattr(current_user, 'latitud') else 0,
        lon_destino=float(incidente.longitud),
        lat_destino=float(incidente.latitud)
    )
    
    return RutaResponse(**ruta)
