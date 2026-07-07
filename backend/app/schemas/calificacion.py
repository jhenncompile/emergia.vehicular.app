from pydantic import BaseModel, Field, validator, field_serializer
from typing import Optional
from datetime import datetime, timezone


def _serializar_utc(dt: Optional[datetime]) -> Optional[str]:
    """Serializa un datetime naive como UTC con sufijo 'Z' (ver schemas/incidente.py)."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class CalificacionCreate(BaseModel):
    incidente_id: int
    puntuacion: int = Field(..., ge=1, le=5, description="Puntuación del 1 al 5")
    comentario: Optional[str] = None

    @validator("puntuacion")
    def validar_puntuacion(cls, v):
        if v < 1 or v > 5:
            raise ValueError("La puntuación debe estar entre 1 y 5")
        return v


class CalificacionOut(BaseModel):
    id: int
    incidente_id: int
    taller_id: int
    usuario_id: int
    puntuacion: int
    comentario: Optional[str] = None
    fecha_creacion: Optional[datetime] = None

    @field_serializer("fecha_creacion", when_used="json")
    def _ser_fecha_utc(self, dt: Optional[datetime]) -> Optional[str]:
        return _serializar_utc(dt)

    class Config:
        from_attributes = True


class PromedioTallerOut(BaseModel):
    taller_id: int
    promedio: Optional[float] = None
    total_calificaciones: int

class CalificacionDetalleOut(CalificacionOut):
    cliente_nombre: Optional[str] = None
    cliente_apellido: Optional[str] = None
    vehiculo_marca: Optional[str] = None
    vehiculo_modelo: Optional[str] = None
