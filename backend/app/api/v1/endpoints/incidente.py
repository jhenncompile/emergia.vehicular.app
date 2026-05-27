from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from app.api import deps
from app.models.incidente import Incidente
from app.models.usuario import Usuario
from app.schemas.incidente import IncidenteSchema

router = APIRouter()

# Obtener incidentes asignados al técnico actual
@router.get("/mis-incidentes", response_model=List[IncidenteSchema])
def obtener_incidentes_asignados(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_user)
):
    """
    Retorna todos los incidentes asignados al técnico autenticado.
    Solo rol_id = 3 (Técnico) puede acceder.
    """
    if current_user.rol_id != 3:
        raise HTTPException(status_code=403, detail="Solo técnicos pueden acceder a esta sección.")
    
    incidentes = db.query(Incidente).filter(
        Incidente.tecnico_id == current_user.id
    ).order_by(Incidente.fecha_creacion.desc()).all()
    
    return incidentes

# Obtener incidentes del taller (para admin)
@router.get("/del-taller", response_model=List[IncidenteSchema])
def obtener_incidentes_del_taller(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    """
    Retorna todos los incidentes del taller del admin.
    """
    incidentes = db.query(Incidente).filter(
        Incidente.taller_id == current_user.taller_id
    ).order_by(Incidente.fecha_creacion.desc()).all()
    
    return incidentes

# Obtener un incidente específico
@router.get("/{incidente_id}", response_model=IncidenteSchema)
def obtener_incidente(
    incidente_id: int,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_user)
):
    """
    Obtiene los detalles de un incidente.
    Un técnico solo puede ver sus incidentes asignados.
    """
    incidente = db.query(Incidente).filter(Incidente.id == incidente_id).first()
    
    if not incidente:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")
    
    # Si es técnico, solo puede ver sus incidentes
    if current_user.rol_id == 3 and incidente.tecnico_id != current_user.id:
        raise HTTPException(status_code=403, detail="No tienes permiso para ver este incidente")
    
    # Si es admin, solo puede ver incidentes de su taller
    if current_user.rol_id == 1 and incidente.taller_id != current_user.taller_id:
        raise HTTPException(status_code=403, detail="No tienes permiso para ver este incidente")
    
    return incidente
