from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.api import deps  # 👈 Aquí vive la magia de la seguridad
from app.crud.crud_taller import taller_crud
from app.crud.crud_bitacora import bitacora_crud
from app.schemas.taller import Taller, TallerCreate, TallerUpdate, TallerDirectorioOut
from app.services.ranking_taller_service import RankingTallerService
from fastapi.encoders import jsonable_encoder

router = APIRouter()

# 1. Registrar un nuevo taller (SaaS onboarding)
@router.post("/", response_model=Taller)
def registrar_taller(
    *,
    db: Session = Depends(deps.get_db),
    obj_in: TallerCreate,
    # Usamos la dependencia que definimos en deps.py
    current_user = Depends(deps.get_current_active_user) 
):
    """Registra un taller y lo vincula al admin actual."""
    nuevo_taller = taller_crud.create(db, obj_in=obj_in)
    
    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=nuevo_taller.id,
        tabla="talleres",
        tabla_id=nuevo_taller.id,
        accion="CREATE_TALLER",
        nuevo=obj_in.dict()
    )
    return nuevo_taller

# 2. Listar talleres activos (Para el mapa de la App Móvil)
@router.get("/activos", response_model=List[Taller])
def leer_talleres_activos(
    db: Session = Depends(deps.get_db),
    skip: int = 0,
    limit: int = 100
):
    return taller_crud.obtener_activos(db, skip=skip, limit=limit)

# 2.5. Directorio de Talleres (solo consulta): talleres activos por especialidad,
# ordenados por la lógica de ranking priorizando la mejor calificación promedio.
@router.get("/directorio", response_model=List[TallerDirectorioOut])
def directorio_talleres(
    especialidad_id: int,
    latitud: float | None = None,
    longitud: float | None = None,
    db: Session = Depends(deps.get_db),
):
    resultados = RankingTallerService(db).recomendar_talleres_por_especialidad(
        especialidad_id=especialidad_id,
        latitud=latitud,
        longitud=longitud,
    )

    tarjetas: List[TallerDirectorioOut] = []
    for item in resultados:
        taller = item["taller"]
        distancia_metros = item["distancia_metros"]
        tarjetas.append(
            TallerDirectorioOut(
                id=taller.id,
                nombre=taller.nombre,
                especialidad=item["especialidad"],
                direccion=taller.direccion,
                telefono=taller.telefono,
                latitud=taller.latitud,
                longitud=taller.longitud,
                calificacion_promedio=taller.calificacion_promedio,
                especialidades_activas=taller.especialidades_activas,
                esta_abierto_ahora=taller.esta_abierto_ahora,
                distancia_km=round(distancia_metros / 1000, 1) if distancia_metros is not None else None,
            )
        )
    return tarjetas

# 3. MI TALLER: El perfil que el admin gestiona (Endpoint /me)
@router.get("/me", response_model=Taller)
def obtener_mi_taller(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    taller = taller_crud.get(db, id=current_user.taller_id)
    if not taller:
        raise HTTPException(status_code=404, detail="Taller no encontrado")
    return taller

# 3.5. Estado actual del taller (Abierto/Cerrado)
@router.get("/me/status", response_model=dict)
def obtener_status_taller(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    """Obtiene si el taller está abierto AHORA"""
    taller = taller_crud.get(db, id=current_user.taller_id)
    if not taller:
        raise HTTPException(status_code=404, detail="Taller no encontrado")
    
    return {
        "taller_id": taller.id,
        "nombre": taller.nombre,
        "esta_abierto_ahora": taller.esta_abierto_ahora,
        "estado": "🟢 ABIERTO" if taller.esta_abierto_ahora else "🔴 CERRADO"
    }

@router.put("/me", response_model=Taller)
def actualizar_mi_taller(
    obj_in: TallerUpdate,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    taller_db = taller_crud.get(db, id=current_user.taller_id)
    if not taller_db:
        raise HTTPException(status_code=404, detail="Taller no encontrado")

    # 💾 Preparamos los datos para la Bitácora (limpios de Decimals)
    # jsonable_encoder asegura que latitud/longitud sean serializables
    anterior_contenido = jsonable_encoder(taller_db)
    
    # Realizamos la actualización en la DB
    taller_actualizado = taller_crud.update(db, db_obj=taller_db, obj_in=obj_in)
    
    # Obtenemos el contenido nuevo ya procesado
    nuevo_contenido = jsonable_encoder(taller_actualizado)

    # 📝 REGISTRO COMPLETO EN BITÁCORA
    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="talleres",
        tabla_id=taller_db.id,
        accion="UPDATE_PERFIL_TALLER",
        anterior=anterior_contenido, # 👈 ¡Faltaba pasar este!
        nuevo=nuevo_contenido
    )
    
    return taller_actualizado

# 4. Leer un taller por su ID (Genérico)
@router.get("/{id}", response_model=Taller)
def leer_taller_por_id(
    id: int,
    db: Session = Depends(deps.get_db)
):
    taller = taller_crud.get(db, id=id)
    if not taller:
        raise HTTPException(status_code=404, detail="Taller no encontrado")
    return taller