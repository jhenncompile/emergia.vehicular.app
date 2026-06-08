from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.db.base_class import Base


class CategoriaIncidente(Base):
    __tablename__ = "categoria_incidente"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), unique=True, nullable=False, index=True)
    descripcion = Column(Text, nullable=True)
    prioridad_default = Column(String(20), nullable=False, default="media")
    activa = Column(Boolean, nullable=False, default=True)
    fecha_creacion = Column(DateTime(timezone=True), server_default=func.now())

    especialidades = relationship(
        "CategoriaEspecialidad",
        back_populates="categoria",
        cascade="all, delete-orphan",
    )


class CategoriaEspecialidad(Base):
    __tablename__ = "categoria_especialidad"
    __table_args__ = (
        UniqueConstraint(
            "categoria_id",
            "especialidad_id",
            name="uq_categoria_especialidad",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    categoria_id = Column(
        Integer,
        ForeignKey("categoria_incidente.id", ondelete="CASCADE"),
        nullable=False,
    )
    especialidad_id = Column(
        Integer,
        ForeignKey("especialidad.id", ondelete="CASCADE"),
        nullable=False,
    )
    peso = Column(Float, nullable=False, default=1.0)
    es_obligatoria = Column(Boolean, nullable=False, default=False)

    categoria = relationship("CategoriaIncidente", back_populates="especialidades")
    especialidad = relationship("Especialidad", back_populates="categorias_incidente")


class IncidenteAsignacionCandidato(Base):
    __tablename__ = "incidente_asignacion_candidato"
    __table_args__ = (
        UniqueConstraint(
            "incidente_id",
            "taller_id",
            name="uq_incidente_taller_candidato",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    incidente_id = Column(
        Integer,
        ForeignKey("incidente.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    taller_id = Column(
        Integer,
        ForeignKey("taller.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    orden = Column(Integer, nullable=False)
    score_total = Column(Float, nullable=False, default=0)
    score_distancia = Column(Float, nullable=False, default=0)
    score_especialidad = Column(Float, nullable=False, default=0)
    score_disponibilidad = Column(Float, nullable=False, default=0)
    estado = Column(String(20), nullable=False, default="pendiente", index=True)
    explicacion = Column(Text, nullable=True)
    fecha_creacion = Column(DateTime(timezone=True), server_default=func.now())
    fecha_oferta = Column(DateTime(timezone=True), nullable=True)
    fecha_respuesta = Column(DateTime(timezone=True), nullable=True)
    expira_en = Column(DateTime(timezone=True), nullable=True)
    motivo_rechazo = Column(Text, nullable=True)
    
    # Nuevos campos para cotizacion multiple
    cotizacion_monto = Column(Float, nullable=True)
    cotizacion_tiempo = Column(String(100), nullable=True)
    sugerencia_ia_monto = Column(Float, nullable=True)

    incidente = relationship("Incidente", back_populates="asignacion_candidatos")
    taller = relationship("Taller", back_populates="asignacion_candidatos")
