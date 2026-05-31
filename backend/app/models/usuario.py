from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Boolean, Table, Text
from sqlalchemy.orm import relationship
from datetime import datetime, timedelta
from app.db.base_class import Base

# 1. TABLA INTERMEDIA
usuario_especialidad = Table(
    "usuario_especialidad",
    Base.metadata,
    Column("usuario_id", Integer, ForeignKey("usuario.id", ondelete="CASCADE"), primary_key=True),
    Column("especialidad_id", Integer, ForeignKey("especialidad.id", ondelete="CASCADE"), primary_key=True),
)

# 2. MODELO DE ESPECIALIDAD
class Especialidad(Base):
    __tablename__ = "especialidad"
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(50), unique=True, nullable=False)
    descripcion = Column(Text, nullable=True)
    usuarios = relationship("Usuario", secondary=usuario_especialidad, back_populates="especialidades")
    categorias_incidente = relationship(
        "CategoriaEspecialidad",
        back_populates="especialidad",
        cascade="all, delete-orphan",
    )

# 3. MODELO DE USUARIO
class Usuario(Base):
    __tablename__ = "usuario"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String, nullable=False)
    apellido = Column(String(100), nullable=True)
    correo = Column(String, unique=True, index=True, nullable=False)
    clave_hash = Column(String, nullable=False)
    telefono = Column(String(20), nullable=True)
    ciudad = Column(String(100), nullable=True)
    direccion = Column(String(200), nullable=True)
    esta_activo = Column(Boolean, default=True) 

    rol_id = Column(Integer, ForeignKey("rol.id", ondelete="RESTRICT"), nullable=False)
    taller_id = Column(Integer, ForeignKey("taller.id", ondelete="SET NULL"), nullable=True)

    # --- RELACIONES ---
    rol = relationship("Rol", back_populates="usuarios")
    taller = relationship("Taller", back_populates="usuarios")
    especialidades = relationship("Especialidad", secondary=usuario_especialidad, back_populates="usuarios")
    vehiculos = relationship("Vehiculo", back_populates="usuario", cascade="all, delete-orphan")
    
    # 🚩 RELACIÓN CORREGIDA: Apunta explícitamente a usuario_id en Incidente
    incidentes = relationship(
        "Incidente", 
        back_populates="usuario", 
        foreign_keys="[Incidente.usuario_id]"
    )
    
    # Relación opcional para ver qué servicios tiene asignados como técnico
    servicios_asignados = relationship(
        "Incidente", 
        foreign_keys="[Incidente.tecnico_id]",
        back_populates="tecnico"
    )
    
    pagos = relationship("Pago", back_populates="usuario")
    bitacoras = relationship("Bitacora", back_populates="usuario")
    notificaciones = relationship("Notificacion", back_populates="usuario", cascade="all, delete-orphan")
    tokens = relationship("TokenDispositivo", back_populates="usuario", cascade="all, delete-orphan")

# 4. TOKEN DE RESTABLECIMIENTO
class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"
    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuario.id", ondelete="CASCADE"), nullable=False)
    token = Column(String, unique=True, index=True, nullable=False)
    expira_en = Column(DateTime, nullable=False, default=lambda: datetime.utcnow() + timedelta(hours=1))
    usado = Column(Boolean, default=False)
    usuario = relationship("Usuario")
