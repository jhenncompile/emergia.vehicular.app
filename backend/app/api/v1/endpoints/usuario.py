from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel

from app.api import deps
from app.crud.crud_usuario import usuario_crud
from app.crud.crud_bitacora import bitacora_crud
from app.models.usuario import Usuario as UsuarioModel, Especialidad
from app.schemas.usuario import (
    Usuario as UsuarioSchema, 
    UsuarioCreate, 
    UsuarioUpdate,
    UsuarioPerfilUpdate,
    TecnicoCreate,
    TecnicoUpdate
)

router = APIRouter()

# --- PERFIL Y ADMINISTRADORES (Existente) ---

@router.get("/me", response_model=UsuarioSchema)
def leer_usuario_actual(current_user = Depends(deps.get_current_user)):
    """Retorna los datos del usuario autenticado."""
    return current_user

@router.put("/me", response_model=UsuarioSchema)
def actualizar_mi_perfil(
    *,
    db: Session = Depends(deps.get_db),
    user_in: UsuarioPerfilUpdate,
    current_user = Depends(deps.get_current_active_user)
):
    """Actualiza datos editables del perfil del usuario autenticado."""
    update_data = user_in.dict(exclude_unset=True)
    if not update_data:
        return current_user

    return usuario_crud.update(
        db,
        db_obj=current_user,
        obj_in=update_data,
        usuario_id=current_user.id,
    )

@router.get("/mis-administradores", response_model=List[UsuarioSchema])
def listar_admins_de_mi_taller(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    """Lista otros administradores (Rol 1) del mismo taller."""
    return db.query(UsuarioModel).filter(
        UsuarioModel.taller_id == current_user.taller_id,
        UsuarioModel.rol_id == 1
    ).all()

@router.post("/nuevo-colega", response_model=UsuarioSchema)
def crear_administrador_adicional(
    *,
    db: Session = Depends(deps.get_db),
    user_in: UsuarioCreate,
    current_user = Depends(deps.get_current_admin_taller)
):
    """Permite a un admin crear otro administrador para su taller."""
    user = usuario_crud.get_by_email(db, email=user_in.correo)
    if user:
        raise HTTPException(status_code=400, detail="El correo ya existe.")
    
    user_in.rol_id = 1
    user_in.taller_id = current_user.taller_id
    
    nuevo_admin = usuario_crud.create(db, obj_in=user_in, usuario_id=current_user.id)
    return nuevo_admin

# --- GESTIÓN DE TÉCNICOS (NUEVO) ---

@router.get("/mis-tecnicos", response_model=List[UsuarioSchema])
def listar_tecnicos_de_mi_taller(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    """Obtiene todos los técnicos (rol_id = 3) del taller actual."""
    return db.query(UsuarioModel).filter(
        UsuarioModel.taller_id == current_user.taller_id,
        UsuarioModel.rol_id == 3
    ).all()

@router.post("/nuevo-tecnico", response_model=UsuarioSchema)
def crear_tecnico(
    *,
    db: Session = Depends(deps.get_db),
    user_in: TecnicoCreate,
    current_user = Depends(deps.get_current_admin_taller)
):
    """Crea un nuevo técnico asignándole especialidades desde el inicio."""
    if usuario_crud.get_by_email(db, email=user_in.correo):
        raise HTTPException(status_code=400, detail="El correo ya existe.")
    
    from app.models.taller import Taller
    taller = db.query(Taller).filter(Taller.id == current_user.taller_id).first()
    
    if taller and taller.plan_suscripcion == 'gratuito':
        num_tecnicos = db.query(UsuarioModel).filter(
            UsuarioModel.taller_id == current_user.taller_id,
            UsuarioModel.rol_id == 3
        ).count()
        if num_tecnicos >= 3:
            raise HTTPException(
                status_code=402, 
                detail="Límite del plan gratuito alcanzado. Mejora a Premium para agregar más técnicos."
            )

    # 1. Extraer IDs de especialidades y preparar datos de usuario
    esp_ids = user_in.especialidades_ids
    user_data = user_in.dict(exclude={"especialidades_ids"})
    
    # 2. Forzar Rol 3 (Técnico) y el Taller del Admin
    obj_in_user = UsuarioCreate(**user_data)
    obj_in_user.rol_id = 3
    obj_in_user.taller_id = current_user.taller_id
    
    # 3. Crear usuario base
    nuevo_tecnico = usuario_crud.create(db, obj_in=obj_in_user, usuario_id=current_user.id)

    # 4. Vincular especialidades
    if esp_ids:
        especialidades_db = db.query(Especialidad).filter(Especialidad.id.in_(esp_ids)).all()
        nuevo_tecnico.especialidades = especialidades_db
        db.commit()
        db.refresh(nuevo_tecnico)

    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="usuario",
        tabla_id=nuevo_tecnico.id,
        accion="CREAR_TECNICO",
        nuevo={"nombre": nuevo_tecnico.nombre, "especialidades": esp_ids}
    )
    return nuevo_tecnico

@router.put("/tecnico/{tecnico_id}", response_model=UsuarioSchema)
def actualizar_tecnico(
    tecnico_id: int,
    *,
    db: Session = Depends(deps.get_db),
    user_in: TecnicoUpdate,
    current_user = Depends(deps.get_current_admin_taller)
):
    """Actualiza datos, estado activo/inactivo y especialidades de un técnico."""
    tecnico_db = db.query(UsuarioModel).filter(
        UsuarioModel.id == tecnico_id,
        UsuarioModel.taller_id == current_user.taller_id,
        UsuarioModel.rol_id == 3
    ).first()

    if not tecnico_db:
        raise HTTPException(status_code=404, detail="Técnico no encontrado")

    anterior_datos = {"nombre": tecnico_db.nombre, "activo": tecnico_db.esta_activo}

    # 1. Actualizar campos base (incluyendo esta_activo)
    update_data = user_in.dict(exclude={"especialidades_ids"}, exclude_unset=True)
    obj_in_update = UsuarioUpdate(**update_data)
    tecnico_actualizado = usuario_crud.update(
        db, db_obj=tecnico_db, obj_in=obj_in_update, usuario_id=current_user.id
    )

    # 2. Actualizar relación de especialidades si se proveen IDs
    if user_in.especialidades_ids is not None:
        especialidades_db = db.query(Especialidad).filter(
            Especialidad.id.in_(user_in.especialidades_ids)
        ).all()
        tecnico_actualizado.especialidades = especialidades_db
        db.commit()
        db.refresh(tecnico_actualizado)

    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="usuario",
        tabla_id=tecnico_id,
        accion="ACTUALIZAR_TECNICO",
        anterior=anterior_datos,
        nuevo=update_data
    )
    return tecnico_actualizado

# --- OPERACIONES GENERALES ---

@router.delete("/{usuario_id}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_usuario(
    usuario_id: int,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    """Elimina un usuario del taller (Admin o Técnico)."""
    usuario = db.query(UsuarioModel).filter(
        UsuarioModel.id == usuario_id, 
        UsuarioModel.taller_id == current_user.taller_id
    ).first()

    if not usuario:
        raise HTTPException(status_code=404, detail="No encontrado.")
    if usuario.id == current_user.id:
        raise HTTPException(status_code=400, detail="No puedes eliminarte a ti mismo.")

    datos_borrado = {"nombre": usuario.nombre, "correo": usuario.correo}
    
    db.delete(usuario)
    db.commit()

    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="usuario",
        tabla_id=usuario_id,
        accion="ELIMINAR_USUARIO",
        anterior=datos_borrado
    )
    return None
