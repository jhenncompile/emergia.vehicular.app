import os
import stripe
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.api import deps
from app.models.taller import Taller
from app.models.usuario import Usuario

router = APIRouter()

@router.post("/checkout-premium")
def crear_checkout_premium(
    current_user: Usuario = Depends(deps.get_current_admin_taller),
    db: Session = Depends(deps.get_db),
):
    
    taller = db.query(Taller).filter(Taller.id == current_user.taller_id).first()
    if not taller:
        raise HTTPException(status_code=404, detail="Taller no encontrado")

    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
    if not stripe.api_key:
        raise HTTPException(status_code=500, detail="Stripe no configurado")

    try:
        # Simularemos que cobramos una suscripción. Creamos un Session de Checkout.
        # En vez de crear Price programaticamente, usaremos price_data.
        session = stripe.checkout.Session.create(
            payment_method_types=["card"],
            line_items=[{
                "price_data": {
                    "currency": "usd",
                    "product_data": {
                        "name": "Suscripción Premium VialIA",
                        "description": "Técnicos e incidentes ilimitados"
                    },
                    "unit_amount": 4999, # $49.99
                    "recurring": {"interval": "month"}
                },
                "quantity": 1,
            }],
            mode="subscription",
            success_url="http://localhost:4200/perfil-taller?session_id={CHECKOUT_SESSION_ID}",
            cancel_url="http://localhost:4200/perfil-taller",
            metadata={
                "taller_id": str(taller.id)
            }
        )
        return {"checkout_url": session.url}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/cancelar")
def cancelar_suscripcion(
    current_user: Usuario = Depends(deps.get_current_admin_taller),
    db: Session = Depends(deps.get_db),
):
    
    taller = db.query(Taller).filter(Taller.id == current_user.taller_id).first()
    if not taller:
        raise HTTPException(status_code=404, detail="Taller no encontrado")

    if taller.plan_suscripcion == 'gratuito':
        raise HTTPException(status_code=400, detail="Ya estás en el plan gratuito")

    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
    try:
        if taller.stripe_subscription_id:
            try:
                stripe.Subscription.delete(taller.stripe_subscription_id)
            except stripe.error.InvalidRequestError:
                # Si el ID no existe en Stripe (ej: inyectado manualmente), lo ignoramos
                pass
        
        taller.plan_suscripcion = 'gratuito'
        taller.stripe_subscription_id = None
        db.commit()
        return {"msg": "Suscripción cancelada. Estás en el plan gratuito."}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
