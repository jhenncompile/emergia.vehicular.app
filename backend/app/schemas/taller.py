from pydantic import BaseModel, Field
from typing import Optional, List
from decimal import Decimal
from datetime import time, datetime

# Importar schema de horarios para reutilización
class HorarioTallerInfo(BaseModel):
    id: int
    dia: str
    hora_apertura: time
    hora_cierre: time
    
    class Config:
        from_attributes = True

class TallerBase(BaseModel):
    nombre: str = Field(..., min_length=3, max_length=100)
    direccion: Optional[str] = Field(None, max_length=200)
    # Validamos que las coordenadas sean reales (Bolivia está en estos rangos aprox)
    latitud: Optional[Decimal] = Field(None, ge=-90, le=90)
    longitud: Optional[Decimal] = Field(None, ge=-180, le=180)
    estado: bool = True
    telefono: Optional[str] = None 
    comision_porcentaje: Optional[float] = None
    stripe_account_id: Optional[str] = None
    plan_suscripcion: Optional[str] = "gratuito"
    suscripcion_expira: Optional[datetime] = None
    stripe_subscription_id: Optional[str] = None

class TallerCreate(TallerBase):
    pass

class TallerUpdate(BaseModel):
    nombre: Optional[str] = None
    direccion: Optional[str] = None
    latitud: Optional[Decimal] = None
    longitud: Optional[Decimal] = None
    telefono: Optional[str] = None
    estado: Optional[bool] = True
    comision_porcentaje: Optional[float] = 10.0
    stripe_account_id: Optional[str] = None
    plan_suscripcion: Optional[str] = "gratuito"
    suscripcion_expira: Optional[datetime] = None
    stripe_subscription_id: Optional[str] = None

class Taller(TallerBase):
    id: int
    especialidades_activas: List[str] = []
    horarios: List[HorarioTallerInfo] = []
    esta_abierto_ahora: bool = False

    class Config:
        from_attributes = True