from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.api import deps
from app.crud.crud_taller_detalles import horario_crud, especialidad_crud
from app.schemas.taller_detalles import (
    HorarioTaller, HorarioTallerCreate,
    Especialidad, EspecialidadCreate
)

router = APIRouter()

# --- HORARIOS ---
@router.post("/horarios", response_model=HorarioTaller)
def agregar_horario(
    obj_in: HorarioTallerCreate, 
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    """Define la hora de apertura y cierre para un día específico."""
    return horario_crud.create(
        db, 
        obj_in=obj_in,
        usuario_id=current_user.id,        
        taller_id=current_user.taller_id   
    )

@router.get("/taller/{taller_id}/horarios", response_model=List[HorarioTaller])
def leer_horarios_taller(taller_id: int, db: Session = Depends(deps.get_db)):
    return horario_crud.obtener_por_taller(db, taller_id=taller_id)

@router.put("/horarios/{horario_id}", response_model=HorarioTaller)
def actualizar_horario(
    horario_id: int,
    obj_in: HorarioTallerCreate,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    """Actualiza un horario existente."""
    horario = horario_crud.get(db, id=horario_id)
    if not horario:
        raise HTTPException(status_code=404, detail="Horario no encontrado")
    
    # Verificar que el horario pertenece al taller del usuario
    if horario.taller_id != current_user.taller_id:
        raise HTTPException(status_code=403, detail="No autorizado")
    
    return horario_crud.update(db, db_obj=horario, obj_in=obj_in)

@router.delete("/horarios/{horario_id}")
def eliminar_horario(
    horario_id: int,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    """Elimina un horario."""
    horario = horario_crud.get(db, id=horario_id)
    if not horario:
        raise HTTPException(status_code=404, detail="Horario no encontrado")
    
    if horario.taller_id != current_user.taller_id:
        raise HTTPException(status_code=403, detail="No autorizado")
    
    horario_crud.remove(db, id=horario_id)
    return {"detail": "Horario eliminado"}

# --- ESPECIALIDADES (Catálogo General) ---
@router.post("/especialidades", response_model=Especialidad)
def crear_especialidad(
    obj_in: EspecialidadCreate, 
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    """Crea una especialidad en el catálogo (ej: Frenos, Motor, Pintura)."""
    existente = especialidad_crud.obtener_por_nombre(db, nombre=obj_in.nombre)
    if existente:
        raise HTTPException(status_code=400, detail="Especialidad ya existe")
    
    return especialidad_crud.create(
        db, 
        obj_in=obj_in,
        usuario_id=current_user.id,        
        taller_id=current_user.taller_id   
    )

@router.get("/especialidades", response_model=List[Especialidad])
def listar_especialidades(db: Session = Depends(deps.get_db)):
    return especialidad_crud.get_multi(db)

# Nota: Se eliminaron los endpoints de 'vincular-especialidad' 
# porque el Taller ahora obtiene sus especialidades automáticamente 
# a través de sus técnicos activos.