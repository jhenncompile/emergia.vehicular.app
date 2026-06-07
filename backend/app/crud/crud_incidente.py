from sqlalchemy.orm import Session, joinedload
from app.crud.base import CRUDBase
from app.models.incidente import Incidente
from app.schemas.incidente import IncidenteCreate, IncidenteUpdate
from typing import List, Optional, Dict, Any
from datetime import datetime
from sqlalchemy import func, and_
from app.models.usuario import Usuario
from app.models.pago import Pago
from app.models.calificacion import Calificacion
from app.core.estados import CanceladoPor, EstadoIncidente
from math import radians, cos, sin, asin, sqrt

class CRUDIncidente(CRUDBase[Incidente, IncidenteCreate, IncidenteUpdate]):
    
    @staticmethod
    def calcular_distancia_haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """
        Calcula la distancia en metros entre dos puntos usando la fórmula de Haversine.
        Parámetros: lat1, lon1, lat2, lon2 (en grados decimales)
        Retorna: distancia en metros
        """
        # Convertir grados a radianes
        lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
        
        # Fórmula de Haversine
        dlon = lon2 - lon1
        dlat = lat2 - lat1
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * asin(sqrt(a))
        
        # Radio de la Tierra en metros
        r = 6371000  # Radio en metros
        return c * r
    
    # Función para que un taller "tome" el incidente
    def asignar_taller(
        self,
        db: Session,
        *,
        db_obj: Incidente,
        taller_id: int,
        tiempo_asignacion_segundos: Optional[int] = None,
    ) -> Incidente:
        update_data = {
            "taller_id": taller_id,
            "estado": EstadoIncidente.ASIGNADO_TALLER,
        }
        if tiempo_asignacion_segundos is not None:
            update_data["tiempo_asignacion_segundos"] = tiempo_asignacion_segundos
        return self.update(db, db_obj=db_obj, obj_in=update_data)

    # Función para obtener incidentes pendientes (Para que los talleres los vean)
    def obtener_pendientes(self, db: Session):
        return db.query(self.model).filter(self.model.estado == EstadoIncidente.PENDIENTE).all()
    
    def obtener_por_taller(self, db: Session, *, taller_id: int):
        return db.query(self.model).filter(self.model.taller_id == taller_id).all()


    # Función para filtrar por el cliente (Para que el usuario vea su historial)
    def obtener_por_usuario(self, db: Session, *, usuario_id: int):
        return db.query(self.model).filter(self.model.usuario_id == usuario_id).all()
    
    def asignar_tecnico(self, db: Session, *, db_obj: Incidente, tecnico_id: int) -> Incidente:
        """Asigna un técnico específico del taller al incidente."""
        return self.update(
            db,
            db_obj=db_obj,
            obj_in={
                "tecnico_id": tecnico_id,
                "estado": EstadoIncidente.EN_CAMINO,
            },
        )

    def rechazar_incidente(self, db: Session, *, db_obj: Incidente, motivo: str) -> Incidente:
        """Compatibilidad: marca el incidente como cancelado por el taller."""
        update_data = {
            "estado": EstadoIncidente.CANCELADO,
            "cancelado_por": CanceladoPor.TALLER,
            "motivo_cancelacion": motivo,
        }
        return self.update(db, db_obj=db_obj, obj_in=update_data)
    
    def obtener_historial_taller(
        self, 
        db: Session, 
        *, 
        taller_id: int, 
        fecha_inicio: Optional[datetime] = None, 
        fecha_fin: Optional[datetime] = None,
        estados: Optional[List[str]] = None, # 👈 Lista de estados
        tecnico_id: Optional[int] = None      # 👈 ID de técnico
    ) -> List[Incidente]:
        query = db.query(self.model).filter(self.model.taller_id == taller_id)
        
        # Cargar las relaciones de técnico y pagos
        query = query.options(joinedload(self.model.tecnico), joinedload(self.model.pagos))
        
        # Filtrado por múltiples estados
        if estados and len(estados) > 0:
            query = query.filter(self.model.estado.in_(estados))
        else:
            # Comportamiento por defecto si no hay nada seleccionado
            query = query.filter(self.model.estado.in_([
                EstadoIncidente.FINALIZADO,
                EstadoIncidente.CANCELADO,
            ]))

        # Filtrado por técnico
        if tecnico_id:
            query = query.filter(self.model.tecnico_id == tecnico_id)

        if fecha_inicio:
            query = query.filter(self.model.fecha_creacion >= fecha_inicio)
        if fecha_fin:
            query = query.filter(self.model.fecha_creacion <= fecha_fin)
            
        return query.order_by(self.model.fecha_creacion.desc()).all()
    

    def obtener_metricas_taller(self, db: Session, *, taller_id: int, fecha_inicio: Optional[datetime] = None, fecha_fin: Optional[datetime] = None, estados: Optional[List[str]] = None, tecnico_id: Optional[int] = None) -> Dict[str, Any]:
        """Calcula los KPIs para la pestaña de historial, respetando filtros aplicados."""
        
        # 1. Atenciones por Técnico
        query_tecnico = db.query(
            Usuario.nombre, func.count(self.model.id).label("total")
        ).join(Usuario, self.model.tecnico_id == Usuario.id)\
         .filter(self.model.taller_id == taller_id, self.model.estado == EstadoIncidente.FINALIZADO)
        
        # Aplicar filtros a atenciones por técnico
        if tecnico_id:
            query_tecnico = query_tecnico.filter(self.model.tecnico_id == tecnico_id)
        if fecha_inicio:
            query_tecnico = query_tecnico.filter(self.model.fecha_creacion >= fecha_inicio)
        if fecha_fin:
            query_tecnico = query_tecnico.filter(self.model.fecha_creacion <= fecha_fin)
        
        por_tecnico = query_tecnico.group_by(Usuario.nombre).all()

        # 2. Recaudación Total del Taller (Restando el 10% de la plataforma)
        # Filtramos pagos que correspondan a incidentes del taller y aplicamos filtros
        query_pago = db.query(Pago).filter(
            Pago.taller_id == taller_id, 
            Pago.estado == "completado"
        )
        
        # Aplicar filtros de incidentes a pagos
        if estados or fecha_inicio or fecha_fin or tecnico_id:
            query_pago = query_pago.join(
                Incidente, Pago.incidente_id == Incidente.id
            )
            
            if estados:
                query_pago = query_pago.filter(Incidente.estado.in_(estados))
            if tecnico_id:
                query_pago = query_pago.filter(Incidente.tecnico_id == tecnico_id)
            if fecha_inicio:
                query_pago = query_pago.filter(Incidente.fecha_creacion >= fecha_inicio)
            if fecha_fin:
                query_pago = query_pago.filter(Incidente.fecha_creacion <= fecha_fin)
        
        pagos = query_pago.all()
        
        total_bruto = sum(p.monto for p in pagos) if pagos else 0
        total_comision = sum(p.comision_plataforma for p in pagos) if pagos else 0

        tiempo_query = db.query(
            self.model.tiempo_asignacion_segundos,
            self.model.fecha_creacion,
            self.model.fecha_llegada_tecnico
        ).filter(
            self.model.taller_id == taller_id,
        )
        if fecha_inicio:
            tiempo_query = tiempo_query.filter(self.model.fecha_creacion >= fecha_inicio)
        if fecha_fin:
            tiempo_query = tiempo_query.filter(self.model.fecha_creacion <= fecha_fin)
            
        tiempos = tiempo_query.all()
        
        asignaciones = [t[0] for t in tiempos if t[0] is not None]
        tiempo_promedio = sum(asignaciones) / len(asignaciones) if asignaciones else None
        
        llegadas = []
        llegadas_dentro_sla = 0
        SLA_LLEGADA_SEGUNDOS = 60 * 60 # 60 minutos como meta de SLA

        for t_asig, f_creacion, f_llegada in tiempos:
            if f_llegada and f_creacion and t_asig is not None:
                delta = (f_llegada - f_creacion).total_seconds() - t_asig
                if delta >= 0:
                    llegadas.append(delta)
                    if delta <= SLA_LLEGADA_SEGUNDOS:
                        llegadas_dentro_sla += 1
        
        tiempo_promedio_llegada = sum(llegadas) / len(llegadas) if llegadas else None
        cumplimiento_sla_porcentaje = (llegadas_dentro_sla / len(llegadas)) * 100 if llegadas else 0.0

        # 3. Conteo de incidentes por estado
        query_estados = db.query(
            self.model.estado, func.count(self.model.id).label("total")
        ).filter(self.model.taller_id == taller_id)
        if fecha_inicio:
            query_estados = query_estados.filter(self.model.fecha_creacion >= fecha_inicio)
        if fecha_fin:
            query_estados = query_estados.filter(self.model.fecha_creacion <= fecha_fin)
        if tecnico_id:
            query_estados = query_estados.filter(self.model.tecnico_id == tecnico_id)
        conteo_estados = query_estados.group_by(self.model.estado).all()
        
        # 4. Calificación Promedio del Taller
        query_calif = db.query(func.avg(Calificacion.puntuacion))\
                        .join(Incidente, Calificacion.incidente_id == Incidente.id)\
                        .filter(Incidente.taller_id == taller_id)
        
        if fecha_inicio:
            query_calif = query_calif.filter(Incidente.fecha_creacion >= fecha_inicio)
        if fecha_fin:
            query_calif = query_calif.filter(Incidente.fecha_creacion <= fecha_fin)
        if tecnico_id:
            query_calif = query_calif.filter(Incidente.tecnico_id == tecnico_id)
                                     
        promedio_calif = query_calif.scalar()

        print(f"DEBUG METRICAS: Taller={taller_id}, FI={fecha_inicio}, FF={fecha_fin}, Estados={conteo_estados}", flush=True)

        return {
            "atenciones_por_tecnico": [{"tecnico": t[0], "cantidad": t[1]} for t in por_tecnico],
            "finanzas": {
                "recaudado_neto": float(total_bruto - total_comision),
                "recaudado_bruto": float(total_bruto)
            },
            "tiempo_promedio_asignacion_segundos": (
                round(float(tiempo_promedio), 2)
                if tiempo_promedio is not None
                else None
            ),
            "tiempo_promedio_llegada_segundos": (
                round(float(tiempo_promedio_llegada), 2)
                if tiempo_promedio_llegada is not None
                else None
            ),
            "cumplimiento_sla_porcentaje": round(cumplimiento_sla_porcentaje, 1),
            "promedio_calificacion": round(float(promedio_calif), 1) if promedio_calif is not None else 0.0,
            "conteo_por_estado": [{"estado": e[0], "cantidad": e[1]} for e in conteo_estados],
            "total_incidentes": sum(e[1] for e in conteo_estados),
        }
    
incidente_crud = CRUDIncidente(Incidente)
