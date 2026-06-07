"""
Servicio centralizado de notificaciones para el sistema.

Maneja la lógica de:
- Crear notificaciones en la BD
- Enviar por WebSocket (tiempo real, web)
- Enviar por FCM (push, móvil)
- Notificar a técnicos, talleres y clientes según corresponda
"""

from sqlalchemy.orm import Session
from datetime import datetime
from typing import Dict, List, Optional
import logging
import json

from app.crud.crud_notificacion import notificacion_crud
from app.schemas.notificacion import NotificacionCreate
from app.models.usuario import Usuario
from app.models.incidente import Incidente
from app.websocket.manager import manager
from app.core.estados import EstadoIncidente

logger = logging.getLogger(__name__)


class NotificacionService:
    """
    Servicio de notificaciones automáticas.
    
    NOTA: Los métodos están preparados para llamar a FCM en el futuro,
    pero por ahora solo guardan en la BD.
    """

    @staticmethod
    def crear_notificacion(
        db: Session,
        usuario_id: int,
        titulo: str,
        mensaje: str,
        tipo: str,
        incidente_id: Optional[int] = None,
        extra_data: Optional[Dict[str, object]] = None
    ) -> bool:
        """
        Crea una notificación en la BD y la envía por todos los canales.
        
        Canales:
        1. BD (siempre)
        2. WebSocket (si usuario conectado en web)
        3. FCM (si usuario tiene token FCM registrado)
        
        Args:
            db: Sesión de base de datos
            usuario_id: ID del usuario que recibirá la notificación
            titulo: Título de la notificación
            mensaje: Cuerpo del mensaje
            tipo: Tipo de notificación (ej: 'tecnico_asignado', 'incidente_aceptado', etc)
            incidente_id: ID del incidente relacionado (opcional)
        
        Returns:
            True si se creó correctamente
        """
        try:
            obj_in = NotificacionCreate(
                usuario_id=usuario_id,
                titulo=titulo,
                mensaje=mensaje,
                tipo=tipo,
                incidente_id=incidente_id
            )
            
            # 1️⃣ Crear notificación en BD
            notificacion_db = notificacion_crud.create(db, obj_in=obj_in, usuario_id=usuario_id)
            logger.info(f"✅ Notificación creada en BD: {tipo} para usuario {usuario_id}")
            
            # Datos para enviar
            data = {
                "id": notificacion_db.id,
                "titulo": titulo,
                "mensaje": mensaje,
                "tipo": tipo,
                "incidente_id": incidente_id,
                "fecha_envio": notificacion_db.fecha_envio.isoformat() if notificacion_db.fecha_envio else None
            }
            if extra_data:
                data.update(extra_data)
            
            # 2️⃣ Enviar por WebSocket (si usuario conectado en web)
            try:
                enviado_ws = manager.send_personal_notification_background(usuario_id, data)
                if not enviado_ws:
                    logger.info(f"ℹ️  WebSocket: usuario {usuario_id} no conectado")
                else:
                    logger.info(f"📱 WebSocket: enviando a usuario {usuario_id}")
            except Exception as e:
                logger.info(f"ℹ️  WebSocket no pudo programarse: {str(e)}")
            
            # 3️⃣ Enviar por FCM (si usuario tiene token registrado)
            NotificacionService._enviar_fcm(db, usuario_id, titulo, mensaje, tipo, incidente_id, extra_data)
            
            return True
        except Exception as e:
            logger.error(f"❌ Error creando notificación: {str(e)}")
            return False

    @staticmethod
    def notificar_tecnico_asignado(
        db: Session,
        tecnico_id: int,
        incidente_id: int,
        incidente: Incidente
    ) -> bool:
        """
        Notifica a un técnico cuando se le asigna un incidente.
        
        Destinatario: TÉCNICO
        Evento: Se le asigna un incidente
        """
        tecnico = db.query(Usuario).filter(Usuario.id == tecnico_id).first()
        if not tecnico:
            return False

        titulo = f"🔧 Nuevo incidente asignado"
        mensaje = f"Se te ha asignado el incidente #{incidente_id} en {incidente.taller.nombre if incidente.taller else 'Tu taller'}"
        
        return NotificacionService.crear_notificacion(
            db=db,
            usuario_id=tecnico_id,
            titulo=titulo,
            mensaje=mensaje,
            tipo="tecnico_asignado",
            incidente_id=incidente_id,
            extra_data={
                "evento": "tecnico_asignado",
                "estado_nuevo": incidente.estado,
                "taller_id": incidente.taller_id,
                "tecnico_id": tecnico_id,
            }
        )

    @staticmethod
    def notificar_incidente_aceptado(
        db: Session,
        cliente_id: int,
        incidente_id: int,
        taller_nombre: str,
        tecnico_nombre: Optional[str] = None
    ) -> bool:
        """
        Notifica al cliente cuando un taller acepta su incidente.
        
        Destinatario: CLIENTE
        Evento: Taller acepta el incidente
        """
        titulo = "✅ Tu solicitud fue aceptada"
        mensaje = f"El taller {taller_nombre} ha aceptado tu solicitud de auxilio #{incidente_id}"
        if tecnico_nombre:
            mensaje += f" y ha asignado al técnico {tecnico_nombre}"
        
        return NotificacionService.crear_notificacion(
            db=db,
            usuario_id=cliente_id,
            titulo=titulo,
            mensaje=mensaje,
            tipo="incidente_aceptado",
            incidente_id=incidente_id,
            extra_data={
                "evento": "taller_acepto",
                "estado_nuevo": EstadoIncidente.ASIGNADO_TALLER,
                "taller_nombre": taller_nombre,
                "tecnico_nombre": tecnico_nombre,
            }
        )

    @staticmethod
    def notificar_incidente_rechazado(
        db: Session,
        cliente_id: int,
        incidente_id: int,
        taller_nombre: str,
        motivo: Optional[str] = None
    ) -> bool:
        """
        Notifica al cliente cuando un taller rechaza su incidente.
        
        Destinatario: CLIENTE
        Evento: Taller rechaza el incidente
        """
        titulo = "❌ Solicitud rechazada"
        mensaje = f"El taller {taller_nombre} no puede atender tu solicitud #{incidente_id}"
        if motivo:
            mensaje += f". Motivo: {motivo}"
        mensaje += ". Puedes intentar con otro taller."
        
        return NotificacionService.crear_notificacion(
            db=db,
            usuario_id=cliente_id,
            titulo=titulo,
            mensaje=mensaje,
            tipo="incidente_rechazado",
            incidente_id=incidente_id,
            extra_data={
                "evento": "taller_rechazo",
                "estado_nuevo": EstadoIncidente.BUSCANDO_TALLER,
                "taller_nombre": taller_nombre,
                "motivo": motivo,
            }
        )

    @staticmethod
    def notificar_cambio_estado(
        db: Session,
        incidente: Incidente,
        estado_anterior: str,
        estado_nuevo: str
    ) -> bool:
        """
        Notifica a clientes y técnicos sobre cambios de estado.
        
        Estados y destinatarios:
        - 'buscando_taller' → cliente
        - 'asignado_taller' → cliente
        - 'en_camino' → cliente + técnico
        - 'en_atencion' → cliente + técnico
        - 'finalizado' → cliente + técnico
        - 'cancelado' → cliente + técnico
        """
        resultado = True

        # Siempre notificar al cliente (usuario que reportó)
        cliente_id = incidente.usuario_id
        incidente_id = incidente.id
        titulo_cliente = ""
        mensaje_cliente = ""

        evento = "estado_cambiado"

        if estado_nuevo == EstadoIncidente.BUSCANDO_TALLER:
            evento = "buscando_taller"
            titulo_cliente = "Buscando taller"
            mensaje_cliente = f"Estamos buscando un taller disponible para tu solicitud #{incidente_id}."

        elif estado_nuevo == EstadoIncidente.ASIGNADO_TALLER:
            evento = "taller_asignado"
            titulo_cliente = "Taller asignado"
            mensaje_cliente = f"Un taller acepto tu solicitud #{incidente_id}. Pronto asignara un tecnico."

        elif estado_nuevo == EstadoIncidente.EN_CAMINO:
            evento = "auxilio_en_camino"
            titulo_cliente = "Auxilio en camino"
            mensaje_cliente = f"Tu solicitud #{incidente_id} está siendo atendida. El técnico está en camino."
            
        elif estado_nuevo == EstadoIncidente.EN_ATENCION:
            evento = "tecnico_llego"
            titulo_cliente = "Tecnico en atencion"
            mensaje_cliente = f"El tecnico llego al incidente #{incidente_id} y comenzo la atencion."
            
        elif estado_nuevo == EstadoIncidente.FINALIZADO:
            evento = "servicio_finalizado"
            titulo_cliente = "Servicio finalizado"
            mensaje_cliente = f"Tu solicitud #{incidente_id} ha sido finalizada. Gracias por usar nuestro servicio."
            
        elif estado_nuevo == EstadoIncidente.CANCELADO:
            evento = "servicio_cancelado"
            titulo_cliente = "Solicitud cancelada"
            mensaje_cliente = f"Tu solicitud #{incidente_id} ha sido cancelada."

        # Crear notificación para cliente si hay mensaje
        if titulo_cliente:
            resultado &= NotificacionService.crear_notificacion(
                db=db,
                usuario_id=cliente_id,
                titulo=titulo_cliente,
                mensaje=mensaje_cliente,
                tipo=f"cambio_estado_{estado_nuevo}",
                incidente_id=incidente_id,
                extra_data={
                    "evento": evento,
                    "estado_anterior": estado_anterior,
                    "estado_nuevo": estado_nuevo,
                    "taller_id": incidente.taller_id,
                    "tecnico_id": incidente.tecnico_id,
                    "pago_estado": incidente.pago_estado,
                }
            )

        # Notificar al técnico en estados específicos
        if incidente.tecnico_id:
            tecnico = db.query(Usuario).filter(Usuario.id == incidente.tecnico_id).first()
            if tecnico:
                titulo_tecnico = ""
                mensaje_tecnico = ""

                if estado_nuevo == EstadoIncidente.EN_CAMINO:
                    titulo_tecnico = "Auxilio en camino"
                    mensaje_tecnico = f"Incidente #{incidente_id} ahora esta marcado como en camino."
                    
                elif estado_nuevo == EstadoIncidente.EN_ATENCION:
                    titulo_tecnico = "Atencion iniciada"
                    mensaje_tecnico = f"Incidente #{incidente_id} ahora esta en atencion."

                elif estado_nuevo == EstadoIncidente.FINALIZADO:
                    titulo_tecnico = "Servicio finalizado"
                    mensaje_tecnico = f"Has finalizado el incidente #{incidente_id}."
                    
                elif estado_nuevo == EstadoIncidente.CANCELADO:
                    titulo_tecnico = "Incidente cancelado"
                    mensaje_tecnico = f"El incidente #{incidente_id} ha sido cancelado."

                if titulo_tecnico:
                    resultado &= NotificacionService.crear_notificacion(
                        db=db,
                        usuario_id=incidente.tecnico_id,
                        titulo=titulo_tecnico,
                        mensaje=mensaje_tecnico,
                        tipo=f"cambio_estado_{estado_nuevo}_tecnico",
                        incidente_id=incidente_id,
                        extra_data={
                            "evento": evento,
                            "estado_anterior": estado_anterior,
                            "estado_nuevo": estado_nuevo,
                            "taller_id": incidente.taller_id,
                            "tecnico_id": incidente.tecnico_id,
                            "pago_estado": incidente.pago_estado,
                        }
                    )

        return resultado

    @staticmethod
    def notificar_taller_nuevo_incidente(
        db: Session,
        incidente_id: int,
        incidente: Incidente,
        lista_talleres_cercanos: Optional[List[int]] = None
    ) -> bool:
        """
        Notifica a los admins de los talleres cuando hay un nuevo incidente disponible.
        
        Destinatarios: ADMINS DEL TALLER
        Evento: Nuevo incidente disponible
        
        NOTA: Por ahora no se implementa. Es para fase 2.
        """
        # TODO: Implementar en fase 2
        # - Obtener admins de talleres cercanos
        # - Enviarles notificación de nuevo incidente disponible
        return True

    @staticmethod
    def notificar_taller_aceptacion(
        db: Session,
        taller_id: int,
        incidente_id: int,
        incidente: Incidente
    ) -> bool:
        """
        Notifica a admins del taller cuando se acepta un incidente.
        
        Destinatarios: ADMINS DEL TALLER
        Evento: Incidente aceptado por el taller
        
        NOTA: Por ahora no se implementa. Es para fase 2.
        """
        # TODO: Implementar en fase 2
        # - Obtener admins del taller
        # - Notificarles que su taller aceptó el incidente
        return True

    @staticmethod
    def _enviar_fcm(
        db: Session,
        usuario_id: int,
        titulo: str,
        mensaje: str,
        tipo: str,
        incidente_id: Optional[int] = None,
        extra_data: Optional[Dict[str, object]] = None
    ) -> bool:
        """
        Envía notificación push a través de Firebase Cloud Messaging.
        
        FLUJO:
        1. Obtener todos los tokens FCM del usuario desde tabla token_dispositivo
        2. Enviar push a cada token
        3. Manejar errores (token expirado, dispositivo no disponible, etc)
        
        Args:
            db: Sesión de base de datos
            usuario_id: ID del usuario
            titulo: Título de la notificación
            mensaje: Cuerpo de la notificación
            incidente_id: ID del incidente (opcional)
        
        Returns:
            True si se envió correctamente (o al menos uno de los tokens)
        """
        try:
            from app.core.firebase_config import firebase_disponible
            if not firebase_disponible():
                logger.info("ℹ️  FCM: Firebase no está disponible/inicializado, saltando envío")
                return False

            from app.crud.crud_notificacion import token_crud
            
            # 1. Obtener todos los tokens FCM del usuario
            tokens = token_crud.obtener_tokens_usuario(db, usuario_id=usuario_id)
            
            if not tokens:
                logger.info(f"ℹ️  FCM: usuario {usuario_id} no tiene tokens registrados")
                return False
            
            # 2. Intentar enviar con firebase-admin
            try:
                import firebase_admin
                from firebase_admin import messaging
                
                # Preparar datos para FCM
                data = {
                    "titulo": titulo,
                    "mensaje": mensaje,
                    "tipo": tipo,
                    "incidente_id": str(incidente_id) if incidente_id else ""
                }
                if extra_data:
                    data.update({key: "" if value is None else str(value) for key, value in extra_data.items()})
                
                # Enviar a cada token
                enviados = 0
                for token_obj in tokens:
                    try:
                        message = messaging.Message(
                            notification=messaging.Notification(
                                title=titulo,
                                body=mensaje
                            ),
                            data=data,
                            token=token_obj.token_fcm
                        )
                        
                        response = messaging.send(message)
                        logger.info(f"✅ FCM enviado a {token_obj.plataforma}: {response}")
                        enviados += 1
                    
                    except messaging.InvalidArgumentError as e:
                        logger.warning(f"⚠️  Token FCM inválido para usuario {usuario_id}: {str(e)}")
                        # Eliminar token expirado
                        token_crud.delete(db, id=token_obj.id)
                    except Exception as e:
                        logger.error(f"❌ Error enviando FCM: {str(e)}")
                
                return enviados > 0
            
            except ImportError:
                logger.info("ℹ️  Firebase Admin SDK no instalado, saltando FCM")
                return False
        
        except Exception as e:
            logger.error(f"❌ Error en flujo FCM: {str(e)}")
            return False
