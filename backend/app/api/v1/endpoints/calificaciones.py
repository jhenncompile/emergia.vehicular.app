from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api import deps
from app.crud.crud_calificacion import calificacion_crud
from app.schemas.calificacion import CalificacionCreate, CalificacionOut, PromedioTallerOut
from app.models.usuario import Usuario

router = APIRouter()


@router.post("/", response_model=CalificacionOut, status_code=201)
def crear_calificacion(
    obj: CalificacionCreate,
    db: Session = Depends(deps.get_db),
    current_user: Usuario = Depends(deps.get_current_user),
):
    """El cliente califica al taller tras finalizar el incidente."""
    return calificacion_crud.crear(db, obj=obj, usuario_id=current_user.id)


@router.get("/incidente/{incidente_id}", response_model=CalificacionOut)
def obtener_calificacion_incidente(
    incidente_id: int,
    db: Session = Depends(deps.get_db),
    _: Usuario = Depends(deps.get_current_user),
):
    """Consulta si ya existe calificación para un incidente."""
    cal = calificacion_crud.obtener_por_incidente(db, incidente_id=incidente_id)
    if not cal:
        from fastapi import HTTPException, status
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sin calificación.")
    return cal


@router.get("/taller/{taller_id}/promedio", response_model=PromedioTallerOut)
def promedio_taller(
    taller_id: int,
    db: Session = Depends(deps.get_db),
):
    """Promedio de calificaciones de un taller (público)."""
    return calificacion_crud.promedio_taller(db, taller_id=taller_id)

from typing import List
from app.schemas.calificacion import CalificacionDetalleOut

@router.get("/taller/mis-calificaciones", response_model=List[CalificacionDetalleOut])
def mis_calificaciones_taller(
    db: Session = Depends(deps.get_db),
    current_user: Usuario = Depends(deps.get_current_admin_taller),
):
    """Obtiene todas las calificaciones y comentarios del taller del usuario."""
    if not current_user.taller_id:
        from fastapi import HTTPException, status
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El usuario no pertenece a ningún taller.",
        )
    return calificacion_crud.obtener_por_taller(db, taller_id=current_user.taller_id)
