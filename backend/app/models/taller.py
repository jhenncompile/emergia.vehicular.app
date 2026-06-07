from sqlalchemy import Column, Integer, String, Float, Boolean, Numeric
from sqlalchemy.orm import relationship
from app.db.base_class import Base
from app.models.usuario import Especialidad
from datetime import datetime
class Taller(Base):
    __tablename__ = "taller"
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False)
    direccion = Column(String(200))
    latitud = Column(Numeric(10, 8))
    longitud = Column(Numeric(11, 8))
    telefono = Column(String(20))
    estado = Column(Boolean, default=True) # Activo o Inactivo
    comision_porcentaje = Column(Float, default=10.0) # Tu ganancia [Audio]
    calificacion_promedio = Column(Float, nullable=True, default=None)  # Promedio de calificaciones

    # Relaciones
    usuarios = relationship("Usuario", back_populates="taller")
    horarios = relationship("HorarioTaller", back_populates="taller")
    incidentes = relationship("Incidente", back_populates="taller")
    asignacion_candidatos = relationship(
        "IncidenteAsignacionCandidato",
        back_populates="taller",
        cascade="all, delete-orphan",
    )
    pagos = relationship("Pago", back_populates="taller")
    bitacoras = relationship("Bitacora", back_populates="taller")
    calificaciones = relationship("Calificacion", back_populates="taller")


    @property
    def especialidades_activas(self):
        servicios = set()
        for u in self.usuarios:
            # Si es Técnico (Rol 3) y está activo
            if u.rol_id == 3 and u.esta_activo:
                for esp in u.especialidades:
                    servicios.add(esp.nombre)
        return sorted(list(servicios))

    @property
    def esta_abierto_ahora(self) -> bool:
        """Verifica si el taller está abierto en este momento."""
        ahora = datetime.now()
        hora_actual = ahora.time()
        
        # Mapeo de día en inglés a español
        dias_semana = {
            0: 'lunes', 1: 'martes', 2: 'miércoles', 3: 'jueves',
            4: 'viernes', 5: 'sábado', 6: 'domingo'
        }
        dia_hoy = dias_semana[ahora.weekday()]
        
        # Buscar horario para hoy
        horario_hoy = None
        for horario in self.horarios:
            if horario.dia.lower() == dia_hoy:
                horario_hoy = horario
                break
        
        # Si no hay horario definido para hoy, está cerrado
        if not horario_hoy:
            return False
        
        # Verificar que esté dentro del rango horario
        return horario_hoy.hora_apertura <= hora_actual <= horario_hoy.hora_cierre
