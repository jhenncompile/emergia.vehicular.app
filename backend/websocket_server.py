"""
Servidor WebSocket standalone para notificaciones en tiempo real.
Corre en paralelo con FastAPI en puerto 8001.
"""

import asyncio
import json
import logging
import websockets
from websockets.asyncio.server import serve

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class WebSocketServer:
    def __init__(self):
        self.connections = {}
    
    async def handle_client(self, websocket):
        """Manejar cliente WebSocket."""
        # Extraer usuario_id del request path
        path = websocket.request.path
        
        try:
            usuario_id = int(path.split('/')[-1])
        except:
            logger.error(f"❌ Path inválido: {path}")
            await websocket.close()
            return
        
        logger.info(f"✅ Usuario {usuario_id} conectado")
        self.connections[usuario_id] = websocket
        
        try:
            async for message in websocket:
                if message == "ping":
                    await websocket.send("pong")
                logger.debug(f"📨 Mensaje de {usuario_id}: {message}")
        
        except Exception as e:
            logger.info(f"👋 Usuario {usuario_id} desconectado")
        finally:
            if usuario_id in self.connections:
                del self.connections[usuario_id]
    
    async def run(self, host='0.0.0.0', port=8001):
        """Iniciar servidor."""
        logger.info(f"🚀 Iniciando WebSocket Server en ws://{host}:{port}")
        
        async with serve(self.handle_client, host, port):
            logger.info(f"✅ WebSocket Server corriendo en ws://{host}:{port}")
            await asyncio.Future()  # run forever


if __name__ == "__main__":
    ws_server = WebSocketServer()
    asyncio.run(ws_server.run())


