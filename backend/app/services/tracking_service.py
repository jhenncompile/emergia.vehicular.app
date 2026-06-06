"""
Servicio de tracking y detección de llegada del técnico
"""
from math import radians, sin, cos, sqrt, atan2
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from sqlalchemy.orm import Session
from app.models.incidente import Incidente
from app.models.usuario import Usuario
from app.core.estados import EstadoIncidente


class TecnicoUbicacionRecord:
    """Registro de ubicación del técnico (para histórico)"""
    def __init__(self, incidente_id: int, tecnico_id: int, latitud: float, 
                 longitud: float, distancia_metros: float, dentro_umbral: bool):
        self.incidente_id = incidente_id
        self.tecnico_id = tecnico_id
        self.latitud = latitud
        self.longitud = longitud
        self.distancia_metros = distancia_metros
        self.dentro_umbral = dentro_umbral
        self.timestamp = datetime.utcnow()


class TrackingService:
    """Servicio de tracking y detección automática de llegada"""
    
    UMBRAL_LLEGADA = 100  # metros
    LECTURAS_REQUERIDAS = 2  # 2 lecturas consecutivas dentro del umbral
    VENTANA_TIEMPO = 30  # segundos para agrupar lecturas
    
    # Almacenamiento en memoria de ubicaciones recientes (en producción usar Redis)
    _ubicaciones_recientes: Dict[int, list] = {}
    
    @staticmethod
    def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """
        Calcular distancia en metros entre 2 puntos GPS usando la fórmula de Haversine
        
        Args:
            lat1, lon1: Coordenadas del punto 1
            lat2, lon2: Coordenadas del punto 2
            
        Returns:
            Distancia en metros
        """
        R = 6371000  # Radio de la Tierra en metros
        
        # Convertir a radianes
        lat1_rad = radians(lat1)
        lon1_rad = radians(lon1)
        lat2_rad = radians(lat2)
        lon2_rad = radians(lon2)
        
        # Diferencias
        dlat = lat2_rad - lat1_rad
        dlon = lon2_rad - lon1_rad
        
        # Fórmula de Haversine
        a = sin(dlat/2)**2 + cos(lat1_rad) * cos(lat2_rad) * sin(dlon/2)**2
        c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R * c  # Distancia en metros
    
    @staticmethod
    def guardar_ubicacion(
        db: Session,
        incidente_id: int,
        tecnico_id: int,
        latitud: float,
        longitud: float
    ) -> Dict[str, Any]:
        """
        Guardar ubicación del técnico y detectar si llegó automáticamente
        
        Validaciones previas (deben hacer antes de llamar):
        - Incidente existe
        - Incidente está en estado en_camino
        - Usuario es el técnico asignado
        
        Returns:
            {
                "distancia_metros": float,
                "llego_automaticamente": bool,
                "estado_nuevo": str | None,  # "en_atencion" si llegó
                "puede_marcar_manual": bool,  # si está dentro del umbral
                "mensaje": str
            }
        """
        # 1. Obtener incidente
        incidente = db.query(Incidente).filter(
            Incidente.id == incidente_id
        ).first()
        
        if not incidente:
            raise ValueError(f"Incidente {incidente_id} no encontrado")
        
        # 2. Calcular distancia
        distancia = TrackingService.haversine(
            float(incidente.latitud), float(incidente.longitud),
            latitud, longitud
        )
        
        # 3. Guardar en histórico en memoria (en producción sería Redis o DB)
        if incidente_id not in TrackingService._ubicaciones_recientes:
            TrackingService._ubicaciones_recientes[incidente_id] = []
        
        ubicacion = {
            "tecnico_id": tecnico_id,
            "latitud": latitud,
            "longitud": longitud,
            "distancia_metros": distancia,
            "dentro_umbral": distancia < TrackingService.UMBRAL_LLEGADA,
            "timestamp": datetime.utcnow()
        }
        
        TrackingService._ubicaciones_recientes[incidente_id].append(ubicacion)
        
        # Limpiar ubicaciones antiguas (> VENTANA_TIEMPO)
        ahora = datetime.utcnow()
        TrackingService._ubicaciones_recientes[incidente_id] = [
            loc for loc in TrackingService._ubicaciones_recientes[incidente_id]
            if (ahora - loc["timestamp"]).total_seconds() <= TrackingService.VENTANA_TIEMPO
        ]
        
        # 4. Validar 2-3 lecturas consecutivas dentro del umbral
        estado_nuevo = None
        llego_automaticamente = False
        
        lecturas_dentro = [
            loc for loc in TrackingService._ubicaciones_recientes[incidente_id]
            if loc["dentro_umbral"]
        ]
        
        if len(lecturas_dentro) >= TrackingService.LECTURAS_REQUERIDAS:
            # ✅ Cambiar automáticamente a en_atencion
            incidente.estado = EstadoIncidente.EN_ATENCION
            incidente.fecha_llegada_tecnico = datetime.utcnow()
            db.commit()
            
            estado_nuevo = EstadoIncidente.EN_ATENCION
            llego_automaticamente = True
        
        return {
            "distancia_metros": round(distancia, 2),
            "llego_automaticamente": llego_automaticamente,
            "estado_nuevo": estado_nuevo,
            "puede_marcar_manual": distancia < TrackingService.UMBRAL_LLEGADA,
            "mensaje": (
                "¡Llegada detectada automáticamente!" if llego_automaticamente
                else f"A {round(distancia, 0)}m del incidente" if distancia < 500
                else f"A {round(distancia / 1000, 1)}km del incidente"
            )
        }
    
    @staticmethod
    def limpiar_ubicaciones_incidente(incidente_id: int) -> None:
        """Limpiar histórico de ubicaciones de un incidente (al cancelar/finalizar)"""
        if incidente_id in TrackingService._ubicaciones_recientes:
            del TrackingService._ubicaciones_recientes[incidente_id]
