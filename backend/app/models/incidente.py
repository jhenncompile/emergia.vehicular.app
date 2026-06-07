from sqlalchemy import Column, Integer, String, ForeignKey, Numeric, Text, DateTime
from sqlalchemy.orm import relationship
from app.db.base_class import Base
from sqlalchemy.sql import func

class Incidente(Base):
    __tablename__ = "incidente"

    id = Column(Integer, primary_key=True, index=True)
    
    # --- LLAVES FORÁNEAS FÍSICAS ---
    vehiculo_id = Column(Integer, ForeignKey("vehiculo.id", ondelete="RESTRICT"), nullable=False)
    usuario_id = Column(Integer, ForeignKey("usuario.id", ondelete="RESTRICT"), nullable=False)
    
    # ID del taller que toma el servicio
    taller_id = Column(Integer, ForeignKey("taller.id", ondelete="SET NULL"), nullable=True)
    
    # ID del técnico específico asignado
    tecnico_id = Column(Integer, ForeignKey("usuario.id", ondelete="SET NULL"), nullable=True)

    # --- DATOS DE ESTADO Y UBICACIÓN ---
    descripcion = Column(Text, nullable=True)
    ubicacion = Column(String(255), nullable=True)
    latitud = Column(Numeric(10, 8))
    longitud = Column(Numeric(11, 8))
    prioridad = Column(String(20)) # 'baja', 'media', 'alta'
    estado = Column(String(20), default="pendiente") 
    pago_estado = Column(String(20), default="pendiente")
    telefono_cliente = Column(String(20), nullable=True)
    motivo_cancelacion = Column(Text, nullable=True)
    cancelado_por = Column(String(20), nullable=True)
    tiempo_asignacion_segundos = Column(Integer, nullable=True)
    fecha_creacion = Column(DateTime(timezone=True), server_default=func.now())
    fecha_llegada_tecnico = Column(DateTime(timezone=True), nullable=True)

    # --- CAMPOS PARA LA IA ---
    transcripcion_audio = Column(Text)
    clasificacion_ia = Column(String(100))
    resumen_ia = Column(Text)

    # --- RELACIONES EXPLÍCITAS ---
    vehiculo = relationship("Vehiculo", back_populates="incidentes")
    
    # Cliente: indicamos que usa la columna usuario_id
    usuario = relationship("Usuario", back_populates="incidentes", foreign_keys=[usuario_id])
    
    # Técnico: indicamos que usa la columna tecnico_id
    tecnico = relationship("Usuario", foreign_keys=[tecnico_id], back_populates="servicios_asignados")
    
    # Taller: indicamos que usa la columna taller_id
    taller = relationship("Taller", back_populates="incidentes", foreign_keys=[taller_id])

    evidencias = relationship("Evidencia", back_populates="incidente", cascade="all, delete-orphan")
    asignacion_candidatos = relationship(
        "IncidenteAsignacionCandidato",
        back_populates="incidente",
        cascade="all, delete-orphan",
    )
    pagos = relationship("Pago", back_populates="incidente", uselist=False, cascade="all, delete-orphan")
    notificaciones = relationship("Notificacion", back_populates="incidente")
    calificacion = relationship("Calificacion", back_populates="incidente", uselist=False, cascade="all, delete-orphan")
