from pydantic import BaseModel, Field, root_validator
from typing import Optional, Dict, Any, List
from decimal import Decimal
from datetime import datetime

# Esquema para mostrar info básica del usuario/cliente
class UsuarioInfo(BaseModel):
    id: int
    nombre: str
    correo: str
    telefono: Optional[str] = None
    class Config:
        from_attributes = True

# Esquema para mostrar info básica del técnico
class TecnicoInfo(BaseModel):
    id: int
    nombre: str
    class Config:
        from_attributes = True

# Esquema para mostrar info del vehículo
class VehiculoInfo(BaseModel):
    id: int
    placa: str
    marca: str
    modelo: str
    class Config:
        from_attributes = True

# Esquema para mostrar info del pago asociado
class PagoInfo(BaseModel):
    id: int
    monto: Decimal
    comision_plataforma: Decimal
    estado: str
    class Config:
        from_attributes = True

# Esquema para mostrar info básica del taller
class TallerInfo(BaseModel):
    id: int
    nombre: Optional[str] = None
    direccion: Optional[str] = None
    latitud: Decimal
    longitud: Decimal
    comision_porcentaje: Optional[Decimal] = None
    class Config:
        from_attributes = True

# Esquema para mostrar evidencia
class EvidenciaInfo(BaseModel):
    id: int
    tipo_archivo: Optional[str] = None
    url_archivo: Optional[str] = None
    class Config:
        from_attributes = True

class IncidenteBase(BaseModel):
    vehiculo_id: int
    usuario_id: int
    taller_id: Optional[int] = None
    tecnico_id: Optional[int] = None
    descripcion: Optional[str] = None
    ubicacion: Optional[str] = None
    latitud: Decimal = Field(..., ge=-90, le=90)
    longitud: Decimal = Field(..., ge=-180, le=180)
    prioridad: str = "media" 
    estado: str = "pendiente"
    pago_estado: str = "pendiente"
    telefono_cliente: str = "No disponible"
    motivo_cancelacion: Optional[str] = None
    cancelado_por: Optional[str] = None
    tiempo_asignacion_segundos: Optional[int] = None
    fecha_creacion: Optional[datetime] = None
    fecha_llegada_tecnico: Optional[datetime] = None
    tiempo_reparacion_estimado: Optional[str] = None

    class Config:
        from_attributes = True

class IncidenteCreate(IncidenteBase):
    transcripcion_audio: Optional[str] = None
    clasificacion_ia: Optional[str] = None
    resumen_ia: Optional[str] = None

class IncidenteUpdate(BaseModel):
    taller_id: Optional[int] = None
    tecnico_id: Optional[int] = None
    descripcion: Optional[str] = None
    ubicacion: Optional[str] = None
    prioridad: Optional[str] = None
    estado: Optional[str] = None 
    pago_estado: Optional[str] = None
    motivo_cancelacion: Optional[str] = None
    cancelado_por: Optional[str] = None
    tiempo_asignacion_segundos: Optional[int] = None
    fecha_llegada_tecnico: Optional[datetime] = None
    tiempo_reparacion_estimado: Optional[str] = None
    resumen_ia: Optional[str] = None


class IncidenteCancel(BaseModel):
    motivo_cancelacion: str
    cancelado_por: Optional[str] = None

class TiempoReparacionUpdate(BaseModel):
    tiempo_reparacion_estimado: str

class Incidente(IncidenteBase):
    id: int
    transcripcion_audio: Optional[str] = None
    clasificacion_ia: Optional[str] = None
    resumen_ia: Optional[str] = None
    
    # Relaciones con otros modelos
    usuario: Optional[UsuarioInfo] = None  # 👤 Cliente que reportó el incidente
    tecnico: Optional[TecnicoInfo] = None  # 👨‍🔧 Técnico asignado
    vehiculo: Optional[VehiculoInfo] = None  # 🚗 Vehículo del incidente
    pagos: Optional[PagoInfo] = None  # Relación con el pago asociado
    taller: Optional[TallerInfo] = None  # 🏢 Taller asignado
    distancia_metros: Optional[float] = None  # 📏 Distancia al taller en metros 
    mensaje_asignacion: Optional[str] = None
    taller_ofrecido: Optional[TallerInfo] = None
    candidato_ofrecido_id: Optional[int] = None
    candidato_estado: Optional[str] = None
    sugerencia_ia_monto: Optional[Decimal] = None
    cotizacion_monto: Optional[Decimal] = None
    cotizacion_tiempo: Optional[str] = None
    tiempo_llegada_estimado: Optional[str] = None
    evidencias: Optional[List[EvidenciaInfo]] = None
    calificado: Optional[bool] = False

    @root_validator(pre=True)
    def extraer_datos_virtuales(cls, obj):
        if not isinstance(obj, dict):
            usuario = getattr(obj, "usuario", None)
            tel = getattr(obj, "telefono_cliente", None) or "No disponible"
            if usuario:
                tel = getattr(usuario, "telefono", None) or tel
            
            return {
                "id": obj.id,
                "vehiculo_id": obj.vehiculo_id,
                "usuario_id": obj.usuario_id,
                "taller_id": obj.taller_id,
                "tecnico_id": obj.tecnico_id,
                "descripcion": getattr(obj, "descripcion", None),
                "ubicacion": getattr(obj, "ubicacion", None),
                "latitud": obj.latitud,
                "longitud": obj.longitud,
                "prioridad": obj.prioridad,
                "estado": obj.estado,
                "pago_estado": obj.pago_estado,
                "telefono_cliente": tel,
                "motivo_cancelacion": obj.motivo_cancelacion,
                "cancelado_por": getattr(obj, "cancelado_por", None),
                "tiempo_asignacion_segundos": getattr(
                    obj,
                    "tiempo_asignacion_segundos",
                    None,
                ),
                "transcripcion_audio": obj.transcripcion_audio,
                "clasificacion_ia": obj.clasificacion_ia,
                "resumen_ia": obj.resumen_ia,
                "fecha_creacion": obj.fecha_creacion,
                "fecha_llegada_tecnico": getattr(obj, "fecha_llegada_tecnico", None),
                "usuario": getattr(obj, "usuario", None),  # 👤 AGREGADO: cliente
                "tecnico": getattr(obj, "tecnico", None),  # 👨‍🔧 técnico
                "vehiculo": getattr(obj, "vehiculo", None),  # 🚗 vehículo
                "pagos": getattr(obj, "pagos", None),  # 💵 pago asociado
                "taller": getattr(obj, "taller", None),  # 🏢 taller
                "distancia_metros": getattr(obj, "distancia_metros", None),  # 📏 distancia
                "mensaje_asignacion": getattr(obj, "mensaje_asignacion", None),
                "taller_ofrecido": getattr(obj, "taller_ofrecido", None),
                "candidato_ofrecido_id": getattr(obj, "candidato_ofrecido_id", None),
                "candidato_estado": getattr(obj, "candidato_estado", None),
                "sugerencia_ia_monto": getattr(obj, "sugerencia_ia_monto", None),
                "cotizacion_monto": getattr(obj, "cotizacion_monto", None),
                "cotizacion_tiempo": getattr(obj, "cotizacion_tiempo", None),
                "tiempo_llegada_estimado": getattr(obj, "tiempo_llegada_estimado", None),
                "tiempo_reparacion_estimado": getattr(obj, "tiempo_reparacion_estimado", None),
                "evidencias": getattr(obj, "evidencias", []), # 📷 evidencias
                "calificado": getattr(obj, "calificacion", None) is not None,
            }
        return obj

# Esquemas para la nueva funcionalidad de Cotizaciones Multiples
class CotizacionTallerCreate(BaseModel):
    monto: float
    tiempo_estimado: str

class CotizacionInfo(BaseModel):
    id: int
    taller_id: int
    taller_nombre: Optional[str] = None
    taller_latitud: Optional[float] = None
    taller_longitud: Optional[float] = None
    distancia_metros: Optional[float] = None
    monto: float
    tiempo_estimado: str
    sugerencia_ia_monto: Optional[float] = None
    estado: str
    
    class Config:
        from_attributes = True

class IncidenteConCotizaciones(Incidente):
    cotizaciones: List[CotizacionInfo] = []
