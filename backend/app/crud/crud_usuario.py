from sqlalchemy.orm import Session
from typing import Optional, Union, Dict, Any
from fastapi.encoders import jsonable_encoder
from app.core.security import obtener_hash_clave

from app.core.security import verificar_clave
from app.crud.base import CRUDBase
from app.models.usuario import Usuario
from app.schemas.usuario import UsuarioCreate, UsuarioUpdate
from app.core.security import obtener_hash_clave
from app.crud.crud_bitacora import bitacora_crud

class CRUDUsuario(CRUDBase[Usuario, UsuarioCreate, UsuarioUpdate]):
    
    # --- CREATE con Hash y Bitácora ---
    def create(self, db: Session, *, obj_in: UsuarioCreate, usuario_id: Optional[int] = None) -> Usuario:
        db_obj = Usuario(
            nombre=obj_in.nombre,
            apellido=obj_in.apellido,
            correo=obj_in.correo,
            telefono=obj_in.telefono,
            ciudad=obj_in.ciudad,
            direccion=obj_in.direccion,
            clave_hash=obtener_hash_clave(obj_in.clave),
            rol_id=obj_in.rol_id,
            taller_id=obj_in.taller_id
        )
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)

        # Registro en Bitácora
        bitacora_crud.registrar(
            db,
            usuario_id=usuario_id or db_obj.id,
            tabla="usuario",
            accion="crear",
            nuevo={"nombre": db_obj.nombre, "correo": db_obj.correo, "rol_id": db_obj.rol_id}
        )
        return db_obj

    # --- UPDATE con Lógica de Clave y Bitácora Comparativa ---
    def update(
        self, 
        db: Session, 
        *, 
        db_obj: Usuario, 
        obj_in: Union[UsuarioUpdate, Dict[str, Any]], 
        usuario_id: Optional[int] = None
    ) -> Usuario:
        # 1. Estado anterior para QA
        datos_anteriores = jsonable_encoder(db_obj)
        
        # 2. Preparar datos nuevos
        update_data = obj_in if isinstance(obj_in, dict) else obj_in.dict(exclude_unset=True)

        # 3. Tratamiento especial de la clave
        if "clave" in update_data and update_data["clave"]:
            db_obj.clave_hash = obtener_hash_clave(update_data["clave"])
            update_data["clave"] = "****** (Actualizada)" # Para la bitácora

        # 4. Actualizar campos dinámicamente
        for field in update_data:
            if hasattr(db_obj, field) and field != "clave":
                setattr(db_obj, field, update_data[field])

        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)

        # 5. Registro explícito en Bitácora
        bitacora_crud.registrar(
            db,
            usuario_id=usuario_id or db_obj.id,
            tabla="usuario",
            accion="actualizar",
            anterior=datos_anteriores,
            nuevo=update_data
        )
        return db_obj

    # --- READ Específicos ---
    def obtener_por_correo(self, db: Session, *, correo: str) -> Optional[Usuario]:
        return db.query(Usuario).filter(Usuario.correo == correo).first()
    
    def get_by_email(self, db: Session, *, email: str):
        # Asegúrate de que el campo en tu modelo se llame 'correo'
        return db.query(Usuario).filter(Usuario.correo == email).first()
    
    def authenticate(self, db: Session, *, correo: str, clave: str) -> Optional[Usuario]:
        # 1. Buscamos al usuario por correo
        usuario = db.query(Usuario).filter(Usuario.correo == correo).first()
        if not usuario:
            return None
        
        # 2. Verificamos si la clave coincide usando la función de security.py
        if not verificar_clave(clave, usuario.clave_hash):
            return None
        
        return usuario
    
    def update_password(self, db: Session, *, db_obj: Usuario, nueva_clave: str) -> Usuario:
        """
        Actualiza la clave del usuario de forma segura.
        """
        db_obj.clave_hash = obtener_hash_clave(nueva_clave)
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        return db_obj
    
    def get_admins_taller(self, db: Session, *, taller_id: int):
        return db.query(Usuario).filter(Usuario.taller_id == taller_id, Usuario.rol_id == 1).all()
    
usuario_crud = CRUDUsuario(Usuario)
