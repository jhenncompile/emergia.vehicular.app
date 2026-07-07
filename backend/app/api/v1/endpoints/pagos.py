import stripe
import os
import logging
from dotenv import load_dotenv
load_dotenv() # Forzar lectura de .env en caso de que uvicorn no se haya reiniciado

from fastapi import APIRouter, Depends, HTTPException, Request

logger = logging.getLogger(__name__)
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel

from app.models.incidente import Incidente
from app.models.taller import Taller
from app.models.pago import Pago as PagoModel
from app.api import deps
from app.crud.crud_pago import pago_crud
from app.crud.crud_bitacora import bitacora_crud
from app.crud.crud_incidente import incidente_crud
from app.schemas.pago import Pago, PagoCreate
from app.core.estados import EstadoIncidente
from app.services.notificacion_service import NotificacionService

router = APIRouter()

# 1. LISTAR TODOS LOS PAGOS DE MI TALLER (Para el nuevo historial)
@router.get("/mi-historial", response_model=List[Pago])
def listar_pagos_taller(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    return pago_crud.obtener_por_taller(db, taller_id=current_user.taller_id)

# 2. PASO A: GENERAR EL COBRO (Queda en estado PENDIENTE)
@router.post("/generar-cobro/{incidente_id}")
def generar_cobro_incidente(
    incidente_id: int,
    monto: float,
    metodo: str, 
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    incidente = db.query(Incidente).filter(Incidente.id == incidente_id).first()
    if not incidente or incidente.taller_id != current_user.taller_id:
        raise HTTPException(status_code=403, detail="No tienes permiso")

    # Cambiamos el estado del incidente para saber que ya se emitió una "factura/cobro"
    incidente.pago_estado = "por_cobrar" 
    db.add(incidente)

    # Creamos el pago SIEMPRE como pendiente
    nuevo_pago = pago_crud.create(db, obj_in=PagoCreate(
        incidente_id=incidente_id,
        usuario_id=incidente.usuario_id,
        taller_id=current_user.taller_id,
        monto=monto,
        metodo_pago=metodo,
        estado="pendiente"
    ))

    # 🚩 BITÁCORA
    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="pago",
        tabla_id=nuevo_pago.id,
        accion="GENERAR_COBRO",
        nuevo={"monto": monto, "metodo": metodo, "estado": "pendiente"}
    )

    # 🚩 NOTIFICACIÓN AL CLIENTE
    NotificacionService.crear_notificacion(
        db,
        usuario_id=incidente.usuario_id,
        titulo="Nuevo Cobro Pendiente",
        mensaje=f"El taller ha generado un cobro de {monto} Bs por el incidente #{incidente_id}.",
        tipo="cobro_generado",
        extra_data={"evento": "cobro_generado", "pago_id": nuevo_pago.id, "incidente_id": incidente_id}
    )

    return {"status": "success", "mensaje": "Cobro generado", "pago_id": nuevo_pago.id}

# --- ENDPOINTS PARA EL CLIENTE ---

@router.get("/cliente/pendientes")
def listar_pagos_pendientes_cliente(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    pagos = db.query(PagoModel).filter(PagoModel.usuario_id == current_user.id, PagoModel.estado == 'pendiente').order_by(PagoModel.id.desc()).all()
    resultado = []
    for p in pagos:
        taller = db.query(Taller).filter(Taller.id == p.taller_id).first()
        resultado.append({
            "id": p.id,
            "incidente_id": p.incidente_id,
            "monto": float(p.monto),
            "estado": p.estado,
            "metodo_pago": p.metodo_pago,
            "fecha_pago": str(p.fecha),
            "taller": {"nombre": taller.nombre if taller else "Desconocido"}
        })
    return resultado

@router.get("/cliente/historial")
def listar_historial_pagos_cliente(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    pagos = db.query(PagoModel).filter(PagoModel.usuario_id == current_user.id, PagoModel.estado != 'pendiente').order_by(PagoModel.id.desc()).all()
    resultado = []
    for p in pagos:
        taller = db.query(Taller).filter(Taller.id == p.taller_id).first()
        resultado.append({
            "id": p.id,
            "incidente_id": p.incidente_id,
            "monto": float(p.monto),
            "estado": p.estado,
            "metodo_pago": p.metodo_pago,
            "fecha_pago": str(p.fecha),
            "taller": {"nombre": taller.nombre if taller else "Desconocido"}
        })
    return resultado


@router.post("/cliente/{pago_id}/confirmar")
def confirmar_pago_cliente(
    pago_id: int,
    metodo_pago: Optional[str] = "Stripe / Tarjeta",
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    pago = db.query(PagoModel).filter(PagoModel.id == pago_id, PagoModel.usuario_id == current_user.id).first()
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    
    if pago.estado != "pendiente":
        return {"status": "success", "mensaje": "El pago ya fue procesado"}

    pago.estado = "completado"
    pago.metodo_pago = metodo_pago
    db.add(pago)

    incidente = db.query(Incidente).filter(Incidente.id == pago.incidente_id).first()
    if incidente:
        incidente.pago_estado = "pagado"
        incidente.estado = EstadoIncidente.FINALIZADO
        db.add(incidente)

    db.commit()

    from app.crud.crud_bitacora import bitacora_crud
    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=pago.taller_id,
        tabla="pago",
        tabla_id=pago.id,
        accion="CONFIRMAR_PAGO",
        anterior={"estado": "pendiente"},
        nuevo={"estado": "completado"}
    )
    return {"status": "success", "mensaje": "Pago completado"}


# STRIPE: Generar PaymentIntent
@router.post("/intent/{pago_id}")
def create_payment_intent(
    pago_id: int,
    db: Session = Depends(deps.get_db)
):
    pago = db.query(PagoModel).filter(PagoModel.id == pago_id).first()
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    if pago.estado != "pendiente":
        raise HTTPException(status_code=400, detail="El pago ya no está pendiente")
        
    taller = db.query(Taller).filter(Taller.id == pago.taller_id).first()
    if not taller:
        raise HTTPException(status_code=404, detail="Taller no encontrado")

    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
    monto_centavos = int(pago.monto * 100)
    
    try:
        if taller.stripe_account_id:
            # Flujo Stripe Connect (Divide fondos)
            comision_centavos = int(monto_centavos * (taller.comision_porcentaje / 100))
            intent = stripe.PaymentIntent.create(
                amount=monto_centavos,
                currency="usd",
                application_fee_amount=comision_centavos,
                transfer_data={
                    "destination": taller.stripe_account_id,
                },
                metadata={"pago_id": pago.id, "incidente_id": pago.incidente_id}
            )
        else:
            # Flujo Normal (Para probar si no hay cuenta connect)
            intent = stripe.PaymentIntent.create(
                amount=monto_centavos,
                currency="usd",
                metadata={"pago_id": pago.id, "incidente_id": pago.incidente_id}
            )
        
        return {
            "paymentIntent": intent.client_secret,
            "ephemeralKey": "",
            "customer": "",
            "publishableKey": os.getenv("STRIPE_PUBLIC_KEY")
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# STRIPE: Webhook
@router.post("/webhook")
async def stripe_webhook(request: Request, db: Session = Depends(deps.get_db)):
    try:
        payload = await request.body()
        sig_header = request.headers.get("stripe-signature")
        endpoint_secret = os.getenv("STRIPE_WEBHOOK_SECRET")

        stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

        try:
            event = stripe.Webhook.construct_event(
                payload, sig_header, endpoint_secret
            )
        except ValueError as e:
            raise HTTPException(status_code=400, detail="Invalid payload")
        except stripe.error.SignatureVerificationError as e:
            raise HTTPException(status_code=400, detail="Invalid signature")

        # Manejar eventos de Stripe
        if event['type'] == 'payment_intent.succeeded':
            payment_intent = event['data']['object']
            try:
                pago_id = payment_intent['metadata']['pago_id']
            except (KeyError, TypeError):
                pago_id = None

            if pago_id:
                try:
                    # 1. Obtener pago e incidente
                    pago = pago_crud.get(db, int(pago_id))
                    if not pago:
                        logger.error(f"Pago {pago_id} no encontrado en DB.")
                        return {"status": "error", "message": "Pago no encontrado"}

                    # 2. Actualizar estado del pago a 'completado'
                    pago_actualizado = pago_crud.update(
                        db,
                        db_obj=pago,
                        obj_in={"estado": "completado"}
                    )

                    # 3. Marcar incidente como pagado y finalizado.
                    #    "pagado" NO es un EstadoIncidente válido: el estado del
                    #    ciclo de vida pasa a FINALIZADO y el pago se refleja en
                    #    pago_estado, igual que en confirmar_pago_cliente.
                    incidente = pago.incidente
                    incidente_crud.update(
                        db,
                        db_obj=incidente,
                        obj_in={
                            "pago_estado": "pagado",
                            "estado": EstadoIncidente.FINALIZADO,
                        }
                    )

                    logger.info(f"✅ Pago {pago_id} y su Incidente {incidente.id} marcados como completados.")
                except Exception as e:
                    logger.error(f"Error procesando webhook success: {str(e)}")
                    return {"status": "error", "message": str(e)}
            else:
                logger.warning("payment_intent.succeeded sin pago_id en metadata.")
                
        elif event['type'] == 'checkout.session.completed':
            session = event['data']['object']
            try:
                taller_id = session['metadata']['taller_id']
                subscription_id = session['subscription']
            except (KeyError, TypeError):
                taller_id = None
                subscription_id = None
            logger.info(f"🚀 DIAGNOSTICO - Checkout Completado | taller_id: {taller_id} | sub_id: {subscription_id}")
            if taller_id and subscription_id:
                taller = db.query(Taller).filter(Taller.id == int(taller_id)).first()
                if taller:
                    taller.plan_suscripcion = 'premium'
                    taller.stripe_subscription_id = subscription_id
                    db.commit()
                    logger.info(f"Taller {taller_id} actualizado a plan premium (Sub: {subscription_id})")

        else:
            logger.info(f"Evento no manejado: {event['type']}")
        
        return {"status": "success"}
    except Exception as e:
        import traceback
        with open("webhook_error.log", "w") as f:
            f.write(traceback.format_exc())
        raise e


# 3. PASO B: CONFIRMAR EL PAGO (Marca como COMPLETADO)
@router.put("/{pago_id}/confirmar")
def confirmar_pago(
    pago_id: int,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    pago = db.query(PagoModel).filter(PagoModel.id == pago_id, PagoModel.taller_id == current_user.taller_id).first()
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    
    if pago.estado != "pendiente":
        raise HTTPException(status_code=400, detail="El pago ya fue procesado o cancelado")

    pago.estado = "completado"
    db.add(pago)

    # Actualizamos el incidente a pagado final
    incidente = db.query(Incidente).filter(Incidente.id == pago.incidente_id).first()
    if incidente:
        incidente.pago_estado = "pagado"
        incidente.estado = EstadoIncidente.FINALIZADO
        db.add(incidente)

    db.commit()

    # 🚩 BITÁCORA
    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="pago",
        tabla_id=pago.id,
        accion="CONFIRMAR_PAGO",
        anterior={"estado": "pendiente"},
        nuevo={"estado": "completado"}
    )
    return {"status": "success", "mensaje": "Pago completado"}

# 4. PASO C: CANCELAR EL PAGO (Mantiene historial, revierte estado)
@router.put("/{pago_id}/cancelar")
def cancelar_pago(
    pago_id: int,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    pago = db.query(PagoModel).filter(PagoModel.id == pago_id, PagoModel.taller_id == current_user.taller_id).first()
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")

    if pago.estado == "cancelado":
        raise HTTPException(status_code=400, detail="El cobro ya estaba cancelado")

    estado_anterior = pago.estado
    pago.estado = "cancelado"
    db.add(pago)

    # El incidente vuelve a quedar pendiente de cobro
    incidente = db.query(Incidente).filter(Incidente.id == pago.incidente_id).first()
    if incidente:
        incidente.pago_estado = "pendiente"
        if incidente.estado == EstadoIncidente.FINALIZADO:
            incidente.estado = EstadoIncidente.EN_ATENCION
        db.add(incidente)

    db.commit()

    # 🚩 BITÁCORA
    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="pago",
        tabla_id=pago.id,
        accion="CANCELAR_PAGO",
        anterior={"estado": estado_anterior},
        nuevo={"estado": "cancelado"}
    )
    return {"status": "success", "mensaje": "Pago cancelado"}

class PagoEdit(BaseModel):
    monto: float
    metodo_pago: str
    estado: str

@router.put("/{pago_id}")
def editar_pago(
    pago_id: int,
    datos: PagoEdit,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller)
):
    # 1. Buscamos el pago
    pago = db.query(PagoModel).filter(PagoModel.id == pago_id, PagoModel.taller_id == current_user.taller_id).first()
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    
    # 2. Seguridad: Solo editamos si estaba pendiente
    if pago.estado != "pendiente":
        raise HTTPException(status_code=400, detail="Solo se pueden editar cobros pendientes")

    # Guardamos los datos anteriores para la bitácora
    anterior_data = {"monto": pago.monto, "metodo": pago.metodo_pago, "estado": pago.estado}

    # 3. Actualizamos los valores del pago
    pago.monto = datos.monto
    pago.metodo_pago = datos.metodo_pago
    pago.estado = datos.estado
    db.add(pago)

    # 4. Sincronizamos el Incidente si el estado cambió desde el selector
    if datos.estado == "completado":
        incidente = db.query(Incidente).filter(Incidente.id == pago.incidente_id).first()
        if incidente:
            incidente.pago_estado = "pagado"
            incidente.estado = EstadoIncidente.FINALIZADO
            db.add(incidente)
    elif datos.estado == "cancelado":
        incidente = db.query(Incidente).filter(Incidente.id == pago.incidente_id).first()
        if incidente:
            incidente.pago_estado = "pendiente" # Vuelve a poder cobrarse
            if incidente.estado == EstadoIncidente.FINALIZADO:
                incidente.estado = EstadoIncidente.EN_ATENCION
            db.add(incidente)

    # 5. Guardamos en BD y registramos en la Bitácora
    db.commit()
    bitacora_crud.registrar(
        db, usuario_id=current_user.id, taller_id=current_user.taller_id,
        tabla="pago", tabla_id=pago.id, accion="EDITAR_PAGO",
        anterior=anterior_data,
        nuevo={"monto": datos.monto, "metodo": datos.metodo_pago, "estado": datos.estado}
    )

    return {"status": "success", "mensaje": "Pago actualizado correctamente"}
