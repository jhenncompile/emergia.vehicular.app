from pydantic import BaseModel, EmailStr, Field
from typing import Optional, List
from .taller import Taller
from app.schemas.taller import TallerCreate
from app.schemas.taller_detalles import Especialidad # 👈 Importamos el schema de especialidad

# Base común
class UsuarioBase(BaseModel):
    nombre: str = Field(..., min_length=3, max_length=100)
    apellido: Optional[str] = Field(None, max_length=100)
    correo: EmailStr
    rol_id: Optional[int] = None
    telefono: Optional[str] = None
    ciudad: Optional[str] = Field(None, max_length=100)
    direccion: Optional[str] = Field(None, max_length=200)
    taller_id: Optional[int] = None
    esta_activo: Optional[bool] = True # 👈 NUEVO: Controla si el técnico aporta especialidades

# Registro
class UsuarioCreate(UsuarioBase):
    clave: str = Field(..., min_length=8)

# Actualización
class UsuarioUpdate(BaseModel):
    nombre: Optional[str] = Field(None, min_length=3, max_length=100)
    apellido: Optional[str] = Field(None, max_length=100)
    correo: Optional[EmailStr] = None
    rol_id: Optional[int] = None
    taller_id: Optional[int] = None
    clave: Optional[str] = Field(None, min_length=8)
    telefono: Optional[str] = None
    ciudad: Optional[str] = Field(None, max_length=100)
    direccion: Optional[str] = Field(None, max_length=200)
    esta_activo: Optional[bool] = None # 👈 NUEVO

class UsuarioPerfilUpdate(BaseModel):
    nombre: Optional[str] = Field(None, min_length=3, max_length=100)
    apellido: Optional[str] = Field(None, max_length=100)
    telefono: Optional[str] = None
    ciudad: Optional[str] = Field(None, max_length=100)
    direccion: Optional[str] = Field(None, max_length=200)

# Respuesta (Lo que va al Frontend)
class Usuario(UsuarioBase):
    id: int
    taller: Optional[Taller] = None
    especialidades: List[Especialidad] = [] # 👈 NUEVO: Retorna las especialidades del técnico

    class Config:
        from_attributes = True

# Para el registro de "Dueño + Taller"
class RegistroSaaS(BaseModel):
    nombre: str
    correo: EmailStr
    password: str
    taller: TallerCreate

class RecuperarClaveRequest(BaseModel):
    correo: EmailStr

class RestablecerClaveInput(BaseModel):
    token: str
    nueva_clave: str

# --- ESQUEMAS PARA TÉCNICOS ---
class TecnicoCreate(UsuarioCreate):
    especialidades_ids: List[int] = []

class TecnicoUpdate(UsuarioUpdate):
    especialidades_ids: Optional[List[int]] = None
    esta_activo: Optional[bool] = None
