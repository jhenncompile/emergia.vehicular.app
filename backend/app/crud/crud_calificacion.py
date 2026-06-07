from sqlalchemy.orm import Session
from sqlalchemy import func
from app.models.calificacion import Calificacion
from app.models.incidente import Incidente
from app.models.taller import Taller
from app.schemas.calificacion import CalificacionCreate
from fastapi import HTTPException, status


class CRUDCalificacion:

    def crear(self, db: Session, *, obj: CalificacionCreate, usuario_id: int) -> Calificacion:
        # 1. Verificar que el incidente exista y esté finalizado
        incidente = db.query(Incidente).filter(Incidente.id == obj.incidente_id).first()
        if not incidente:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Incidente no encontrado.",
            )
        if incidente.estado not in ("finalizado", "completado"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Solo se puede calificar un incidente finalizado.",
            )
        if incidente.usuario_id != usuario_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Solo el cliente del incidente puede calificarlo.",
            )

        # 2. Verificar duplicado
        existente = (
            db.query(Calificacion)
            .filter(Calificacion.incidente_id == obj.incidente_id)
            .first()
        )
        if existente:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Ya existe una calificación para este incidente.",
            )

        # 3. Crear calificación
        calificacion = Calificacion(
            incidente_id=obj.incidente_id,
            taller_id=incidente.taller_id,
            usuario_id=usuario_id,
            puntuacion=obj.puntuacion,
            comentario=obj.comentario,
        )
        db.add(calificacion)
        db.flush()  # Obtener el ID antes de commit

        # 4. Recalcular y guardar promedio en el taller
        self._actualizar_promedio_taller(db, taller_id=incidente.taller_id)

        db.commit()
        db.refresh(calificacion)
        return calificacion

    def obtener_por_incidente(self, db: Session, incidente_id: int) -> Calificacion | None:
        return (
            db.query(Calificacion)
            .filter(Calificacion.incidente_id == incidente_id)
            .first()
        )

    def promedio_taller(self, db: Session, taller_id: int) -> dict:
        resultado = (
            db.query(
                func.avg(Calificacion.puntuacion).label("promedio"),
                func.count(Calificacion.id).label("total"),
            )
            .filter(Calificacion.taller_id == taller_id)
            .one()
        )
        return {
            "taller_id": taller_id,
            "promedio": round(float(resultado.promedio), 2) if resultado.promedio else None,
            "total_calificaciones": resultado.total or 0,
        }

    def _actualizar_promedio_taller(self, db: Session, taller_id: int) -> None:
        """Calcula el promedio actual y lo persiste en taller.calificacion_promedio."""
        resultado = (
            db.query(func.avg(Calificacion.puntuacion))
            .filter(Calificacion.taller_id == taller_id)
            .scalar()
        )
        taller = db.query(Taller).filter(Taller.id == taller_id).first()
        if taller:
            taller.calificacion_promedio = round(float(resultado), 2) if resultado else None

    def obtener_por_taller(self, db: Session, taller_id: int):
        from app.models.usuario import Usuario
        from app.models.vehiculo import Vehiculo
        
        calificaciones = (
            db.query(Calificacion, Usuario, Vehiculo)
            .join(Usuario, Calificacion.usuario_id == Usuario.id)
            .join(Incidente, Calificacion.incidente_id == Incidente.id)
            .outerjoin(Vehiculo, Incidente.vehiculo_id == Vehiculo.id)
            .filter(Calificacion.taller_id == taller_id)
            .order_by(Calificacion.fecha_creacion.desc())
            .all()
        )
        
        resultado = []
        for cal, usu, veh in calificaciones:
            item = {
                "id": cal.id,
                "incidente_id": cal.incidente_id,
                "taller_id": cal.taller_id,
                "usuario_id": cal.usuario_id,
                "puntuacion": cal.puntuacion,
                "comentario": cal.comentario,
                "fecha_creacion": cal.fecha_creacion,
                "cliente_nombre": usu.nombre,
                "cliente_apellido": usu.apellido,
                "vehiculo_marca": veh.marca if veh else None,
                "vehiculo_modelo": veh.modelo if veh else None,
            }
            resultado.append(item)
            
        return resultado


calificacion_crud = CRUDCalificacion()
