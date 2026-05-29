from sqlalchemy.orm import Session
from app.crud.base import CRUDBase
from app.models.notificacion import Notificacion, TokenDispositivo
from app.schemas.notificacion import (
    NotificacionCreate, NotificacionUpdate, 
    TokenDispositivoCreate
)

# CRUD para Notificaciones
class CRUDNotificacion(CRUDBase[Notificacion, NotificacionCreate, NotificacionUpdate]):
    def obtener_no_leidas(self, db: Session, *, usuario_id: int):
        return db.query(self.model).filter(
            self.model.usuario_id == usuario_id, 
            self.model.leido == False
        ).all()

    def obtener_historial(self, db: Session, *, usuario_id: int):
        """Obtiene TODAS las notificaciones (leídas y no leídas) del usuario"""
        return db.query(self.model).filter(
            self.model.usuario_id == usuario_id
        ).order_by(self.model.fecha_envio.desc()).all()

notificacion_crud = CRUDNotificacion(Notificacion)

# CRUD para Tokens
class CRUDToken(CRUDBase[TokenDispositivo, TokenDispositivoCreate, TokenDispositivoCreate]):
    def obtener_tokens_usuario(self, db: Session, *, usuario_id: int):
        return db.query(self.model).filter(self.model.usuario_id == usuario_id).all()

## cuando el usuario vuelve a iniciar sesión, solemos hacer un "Upsert" (actualizar si existe, crear si no). 
# Por ahora, con el create genérico estamos bien para el avance, pero tenlo en mente para la versión final.
token_crud = CRUDToken(TokenDispositivo)