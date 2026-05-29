"""
Gestor de conexiones WebSocket para notificaciones en tiempo real.

Mantiene un registro de clientes conectados y envía notificaciones
inmediatamente cuando ocurren eventos.
"""

from typing import Dict, Set
import asyncio
import logging

logger = logging.getLogger(__name__)


class WebSocketManager:
    """
    Maneja conexiones WebSocket de usuarios.
    
    Permite:
    - Registrar usuarios cuando se conectan
    - Desregistrar cuando se desconectan
    - Enviar notificaciones a usuarios específicos
    - Broadcast a múltiples usuarios
    """
    
    def __init__(self):
        # Dict[usuario_id] = Set[WebSocket connections]
        # Un usuario puede tener múltiples conexiones (múltiples pestañas)
        self.active_connections: Dict[int, Set] = {}
        self.event_loop = None
        self.logger = logging.getLogger(__name__)
    
    async def connect(self, usuario_id: int, websocket):
        """Registra una nueva conexión WebSocket para un usuario."""
        self.event_loop = asyncio.get_running_loop()
        await websocket.accept()
        
        if usuario_id not in self.active_connections:
            self.active_connections[usuario_id] = set()
        
        self.active_connections[usuario_id].add(websocket)
        self.logger.info(f"✅ Usuario {usuario_id} conectado (total: {len(self.active_connections[usuario_id])} conexiones)")
    
    def disconnect(self, usuario_id: int, websocket):
        """Desregistra una conexión WebSocket."""
        if usuario_id in self.active_connections:
            self.active_connections[usuario_id].discard(websocket)
            
            # Si no quedan conexiones para este usuario, eliminar
            if not self.active_connections[usuario_id]:
                del self.active_connections[usuario_id]
                self.logger.info(f"👋 Usuario {usuario_id} desconectado")
            else:
                self.logger.info(f"📍 Usuario {usuario_id} tiene {len(self.active_connections[usuario_id])} conexiones restantes")
    
    async def send_personal_notification(
        self,
        usuario_id: int,
        data: dict
    ):
        """
        Envía notificación a un usuario específico.
        
        Args:
            usuario_id: ID del usuario a notificar
            data: Dict con {titulo, mensaje, tipo, incidente_id, ...}
        """
        if usuario_id not in self.active_connections:
            self.logger.info(f"ℹ️  Usuario {usuario_id} no conectado, notificación solo en BD")
            return False
        
        # Enviar a todas las conexiones del usuario
        desconectadas = set()
        for websocket in self.active_connections[usuario_id]:
            try:
                await websocket.send_json(data)
                self.logger.info(f"📤 Notificación enviada a usuario {usuario_id}")
            except Exception as e:
                self.logger.error(f"❌ Error enviando a usuario {usuario_id}: {str(e)}")
                desconectadas.add(websocket)
        
        # Limpiar conexiones muertas
        for ws in desconectadas:
            self.disconnect(usuario_id, ws)
        
        return True

    def send_personal_notification_background(self, usuario_id: int, data: dict) -> bool:
        """
        Programa el envío desde endpoints síncronos o asíncronos.
        """
        if usuario_id not in self.active_connections:
            self.logger.info(f"ℹ️  Usuario {usuario_id} no conectado, notificación solo en BD")
            return False

        try:
            loop = asyncio.get_running_loop()
            loop.create_task(self.send_personal_notification(usuario_id, data))
            return True
        except RuntimeError:
            pass

        if self.event_loop and self.event_loop.is_running():
            future = asyncio.run_coroutine_threadsafe(
                self.send_personal_notification(usuario_id, data),
                self.event_loop
            )
            future.add_done_callback(self._log_background_error)
            return True

        self.logger.warning("No hay event loop disponible para enviar notificación WebSocket")
        return False

    def _log_background_error(self, future):
        try:
            future.result()
        except Exception as e:
            self.logger.error(f"❌ Error en envío WebSocket programado: {str(e)}")
    
    async def send_to_multiple_users(
        self,
        usuario_ids: list,
        data: dict
    ):
        """
        Envía notificación a múltiples usuarios.
        
        Args:
            usuario_ids: Lista de IDs de usuarios
            data: Dict con datos de la notificación
        """
        for usuario_id in usuario_ids:
            await self.send_personal_notification(usuario_id, data)
    
    def get_connected_users(self) -> list:
        """Retorna lista de usuarios conectados."""
        return list(self.active_connections.keys())
    
    def is_user_connected(self, usuario_id: int) -> bool:
        """Verifica si un usuario está conectado."""
        return usuario_id in self.active_connections


# Instancia global
manager = WebSocketManager()
