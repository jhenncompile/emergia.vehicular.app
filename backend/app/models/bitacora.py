from sqlalchemy import Column, Integer, String, JSON, DateTime, ForeignKey
from sqlalchemy.sql import func
from app.db.base_class import Base
from sqlalchemy.orm import relationship

class Bitacora(Base):
    __tablename__ = "bitacora" # Asegúrate de definir el nombre de la tabla
    
    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuario.id"), nullable=True)
    # NUEVO: Vínculo con el taller (Tenant)
    taller_id = Column(Integer, ForeignKey("taller.id"), nullable=True) 
    
    tabla = Column(String(50)) 
    tabla_id = Column(Integer) 
    accion = Column(String(50))
    
    valor_anterior = Column(JSON, nullable=True)
    valor_nuevo = Column(JSON, nullable=True)
    fecha_hora = Column(DateTime(timezone=True), server_default=func.now())

    # Relaciones
    usuario = relationship("Usuario", back_populates="bitacoras")
    taller = relationship("Taller", back_populates="bitacoras") # Opcional, pero recomendado
