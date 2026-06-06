"""
Schemas para seguimiento/tracking de técnicos
"""
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime


class LocationTecnicoRequest(BaseModel):
    """Request para enviar ubicación del técnico"""
    latitud: float = Field(..., description="Latitud del técnico")
    longitud: float = Field(..., description="Longitud del técnico")
    
    class Config:
        schema_extra = {
            "example": {
                "latitud": -17.783,
                "longitud": -63.182
            }
        }


class LocationTecnicoResponse(BaseModel):
    """Response al enviar ubicación"""
    distancia_metros: float = Field(..., description="Distancia al incidente en metros")
    llego_automaticamente: bool = Field(..., description="¿Se detectó llegada automática?")
    estado_nuevo: Optional[str] = Field(None, description="Nuevo estado si llegó")
    puede_marcar_manual: bool = Field(..., description="¿Puede marcar llegada manualmente?")
    mensaje: str = Field(..., description="Mensaje descriptivo")
    
    class Config:
        schema_extra = {
            "example": {
                "distancia_metros": 87.5,
                "llego_automaticamente": False,
                "estado_nuevo": None,
                "puede_marcar_manual": True,
                "mensaje": "A 88m del incidente"
            }
        }


class MarcarLlegadaResponse(BaseModel):
    """Response al marcar llegada manualmente"""
    estado: str = Field(..., description="Nuevo estado del incidente")
    fecha_llegada_tecnico: datetime = Field(..., description="Timestamp de llegada")
    mensaje: str = Field(..., description="Mensaje de confirmación")
    
    class Config:
        schema_extra = {
            "example": {
                "estado": "en_atencion",
                "fecha_llegada_tecnico": "2026-06-05T10:35:00Z",
                "mensaje": "Llegada marcada correctamente"
            }
        }


class RutaResponse(BaseModel):
    """Response con información de ruta"""
    distancia_km: Optional[float] = Field(None, description="Distancia en km")
    duracion_minutos: Optional[float] = Field(None, description="Duración estimada en minutos")
    geometry: Optional[Dict[str, Any]] = Field(None, description="GeoJSON de la ruta")
    pasos: List[Dict[str, Any]] = Field(default_factory=list, description="Instrucciones paso a paso")
    error: Optional[str] = Field(None, description="Error si hubo")
    
    class Config:
        schema_extra = {
            "example": {
                "distancia_km": 3.5,
                "duracion_minutos": 7.2,
                "geometry": {
                    "type": "LineString",
                    "coordinates": [[-63.182, -17.783], [-63.185, -17.785]]
                },
                "pasos": [
                    {
                        "instruccion": "Gira derecha en Calle Principal",
                        "distancia_m": 150,
                        "duracion_seg": 12
                    }
                ],
                "error": None
            }
        }


class UbicacionTecnicoEventoWebSocket(BaseModel):
    """Evento WebSocket: Ubicación del técnico actualizada"""
    tipo: str = Field(default="ubicacion_tecnico_actualizada")
    incidente_id: int
    tecnico_id: int
    latitud: float
    longitud: float
    distancia_incidente: float = Field(..., description="Distancia al incidente en metros")
    puede_marcar_llegada: bool
    llego_automaticamente: bool
    timestamp: datetime
    
    class Config:
        schema_extra = {
            "example": {
                "tipo": "ubicacion_tecnico_actualizada",
                "incidente_id": 5,
                "tecnico_id": 10,
                "latitud": -17.783,
                "longitud": -63.182,
                "distancia_incidente": 87.5,
                "puede_marcar_llegada": True,
                "llego_automaticamente": False,
                "timestamp": "2026-06-05T10:30:45Z"
            }
        }
