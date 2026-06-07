from sqlalchemy import Column, Integer, ForeignKey, Text, DateTime, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.base_class import Base


class Calificacion(Base):
    __tablename__ = "calificacion"

    id = Column(Integer, primary_key=True, index=True)
    incidente_id = Column(
        Integer,
        ForeignKey("incidente.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,  # Solo una calificación por incidente
    )
    taller_id = Column(
        Integer,
        ForeignKey("taller.id", ondelete="CASCADE"),
        nullable=False,
    )
    usuario_id = Column(
        Integer,
        ForeignKey("usuario.id", ondelete="CASCADE"),
        nullable=False,
    )
    puntuacion = Column(Integer, nullable=False)  # 1-5
    comentario = Column(Text, nullable=True)
    fecha_creacion = Column(DateTime(timezone=True), server_default=func.now())

    # Relaciones
    incidente = relationship("Incidente", back_populates="calificacion")
    taller = relationship("Taller", back_populates="calificaciones")
    usuario = relationship("Usuario", foreign_keys=[usuario_id])
