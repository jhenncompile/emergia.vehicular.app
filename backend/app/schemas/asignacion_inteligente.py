from datetime import datetime
from typing import Optional

from pydantic import BaseModel

from app.schemas.incidente import TallerInfo


class CategoriaIncidenteOut(BaseModel):
    id: int
    nombre: str
    descripcion: Optional[str] = None
    prioridad_default: str
    activa: bool

    class Config:
        from_attributes = True


class CategoriaEspecialidadOut(BaseModel):
    id: int
    categoria_id: int
    especialidad_id: int
    peso: float
    es_obligatoria: bool

    class Config:
        from_attributes = True


class IncidenteAsignacionCandidatoOut(BaseModel):
    id: int
    incidente_id: int
    taller_id: int
    orden: int
    score_total: float
    score_distancia: float
    score_especialidad: float
    score_disponibilidad: float
    estado: str
    explicacion: Optional[str] = None
    fecha_creacion: Optional[datetime] = None
    fecha_oferta: Optional[datetime] = None
    fecha_respuesta: Optional[datetime] = None
    expira_en: Optional[datetime] = None
    motivo_rechazo: Optional[str] = None
    taller: Optional[TallerInfo] = None

    class Config:
        from_attributes = True
