import secrets
from datetime import datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from fastapi_mail import FastMail, MessageSchema, MessageType, ConnectionConfig

from app.core import security
from app.core.config import settings
from app.db.session import get_db
from app.crud.crud_usuario import usuario_crud
from app.crud.crud_taller import taller_crud
from app.crud.crud_bitacora import bitacora_crud
from app.schemas.token import Token
from app.schemas.usuario import RegistroSaaS, UsuarioCreate, RecuperarClaveRequest, RestablecerClaveInput

# Asegúrate de que tu modelo Usuario también esté importado aquí
from app.models.usuario import PasswordResetToken, Usuario 

router = APIRouter()

# --- CONFIGURACIÓN DE CORREO ---
mail_conf = ConnectionConfig(
    MAIL_USERNAME=settings.MAIL_USERNAME,
    MAIL_PASSWORD=settings.MAIL_PASSWORD,
    MAIL_FROM=settings.MAIL_FROM,
    MAIL_PORT=settings.MAIL_PORT,
    MAIL_SERVER=settings.MAIL_SERVER,
    MAIL_FROM_NAME=settings.MAIL_FROM_NAME,
    MAIL_STARTTLS=True,
    MAIL_SSL_TLS=False,
    USE_CREDENTIALS=True
)

async def enviar_email_recuperacion(email_to: str, token: str):
    link = f"http://localhost:4200/reset-password?token={token}"
    html = f"""
    <div style="font-family: sans-serif; max-width: 450px; border: 1px solid #ddd; padding: 20px; border-radius: 10px;">
        <h2 style="color: #2c3e50;">Recuperar Contraseña</h2>
        <p>Has solicitado restablecer tu clave en <strong>TallerPro</strong>.</p>
        <p>Haz clic en el botón de abajo para continuar. Este enlace expira en 15 minutos.</p>
        <div style="text-align: center; margin: 25px 0;">
            <a href="{link}" style="background-color: #007bff; color: white; padding: 12px 20px; text-decoration: none; border-radius: 5px; font-weight: bold;">
                Restablecer mi clave
            </a>
        </div>
        <p style="font-size: 0.8em; color: #7f8c8d;">Si no solicitaste este cambio, puedes ignorar este correo.</p>
    </div>
    """
    message = MessageSchema(
        subject="Restablecer Contraseña - TallerPro",
        recipients=[email_to],
        body=html,
        subtype=MessageType.html
    )
    fm = FastMail(mail_conf)
    await fm.send_message(message)


# --- ENDPOINTS EXISTENTES (Register y Login) ---

@router.post("/register-taller", response_model=Token)
def registrar_empresa_y_admin(
    *,
    db: Session = Depends(get_db),
    datos: RegistroSaaS
):
    user_db = usuario_crud.get_by_email(db, email=datos.correo)
    if user_db:
        raise HTTPException(status_code=400, detail="El correo ya está registrado.")

    try:
        nuevo_taller = taller_crud.create(db, obj_in=datos.taller)
        
        user_in = UsuarioCreate(
            nombre=datos.nombre,
            correo=datos.correo,
            clave=datos.password,
            rol_id=1,
            taller_id=nuevo_taller.id
        )
        nuevo_usuario = usuario_crud.create(db, obj_in=user_in)

        bitacora_crud.registrar(
            db,
            usuario_id=nuevo_usuario.id,
            taller_id=nuevo_taller.id,
            tabla="taller",
            tabla_id=nuevo_taller.id,
            accion="REGISTRO_SAAS",
            nuevo={"nombre_taller": nuevo_taller.nombre, "admin": nuevo_usuario.correo}
        )
        
        access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        return {
            "access_token": security.crear_token_acceso(
                nuevo_usuario.id, expires_delta=access_token_expires
            ),
            "token_type": "bearer",
            "rol_id": nuevo_usuario.rol_id,
            "usuario_id": nuevo_usuario.id,
            "nombre": nuevo_usuario.nombre,
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error en el registro: {str(e)}")


@router.post("/login", response_model=Token)
def login_access_token(
    db: Session = Depends(get_db),
    form_data: OAuth2PasswordRequestForm = Depends()
) -> Any:
    usuario = usuario_crud.authenticate(
        db, correo=form_data.username, clave=form_data.password
    )
    if not usuario:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Correo o contraseña incorrectos",
        )

    plataforma = form_data.client_id 

    if plataforma == "web" and usuario.rol_id == 2:
        raise HTTPException(status_code=403, detail="Acceso denegado: Use la App Móvil.")
    if plataforma == "movil" and usuario.rol_id != 2:
        raise HTTPException(status_code=403, detail="Acceso denegado: La app móvil es solo para clientes.")

    bitacora_crud.registrar(
        db,
        usuario_id=usuario.id,
        taller_id=usuario.taller_id,
        tabla="usuario",
        tabla_id=usuario.id,
        accion="LOGIN",
        nuevo={"plataforma": plataforma}
    )

    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return {
        "access_token": security.crear_token_acceso(
            usuario.id, expires_delta=access_token_expires
        ),
        "token_type": "bearer",
        "rol_id": usuario.rol_id,
        "usuario_id": usuario.id,
        "nombre": usuario.nombre,
    }


# --- NUEVOS ENDPOINTS DE RECUPERACIÓN ---

@router.post("/forgot-password")
async def solicitar_recuperacion(
    datos: RecuperarClaveRequest, 
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    usuario = usuario_crud.get_by_email(db, email=datos.correo)
    
    # Por seguridad, siempre devolvemos 200 aunque el correo no exista
    if not usuario:
        return {"msg": "Si el correo está registrado, recibirá un enlace en breve."}

    # Generar token único y expiración (15 min)
    token_str = secrets.token_urlsafe(32)
    expiracion = datetime.utcnow() + timedelta(minutes=15)

    db_token = PasswordResetToken(
        usuario_id=usuario.id,
        token=token_str,
        expira_en=expiracion
    )
    db.add(db_token)
    db.commit()

    # Tarea en segundo plano para no bloquear la respuesta de la API
    background_tasks.add_task(enviar_email_recuperacion, usuario.correo, token_str)
    
    return {"msg": "Correo enviado con éxito."}


@router.post("/reset-password")
def restablecer_clave(datos: RestablecerClaveInput, db: Session = Depends(get_db)):
    # 1. Validar Token
    token_record = db.query(PasswordResetToken).filter(
        PasswordResetToken.token == datos.token,
        PasswordResetToken.usado == False,
        PasswordResetToken.expira_en > datetime.utcnow()
    ).first()

    if not token_record:
        raise HTTPException(status_code=400, detail="El enlace es inválido o ha expirado.")

    usuario = db.query(Usuario).filter(Usuario.id == token_record.usuario_id).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")

    # 2. Actualizar Clave (Usando tu lógica de hash en CRUD)
    usuario_crud.update_password(db, db_obj=usuario, nueva_clave=datos.nueva_clave)

    # 3. Marcar token como usado
    token_record.usado = True
    
    # 4. REGLA DE ORO: Bitácora
    bitacora_crud.registrar(
        db,
        usuario_id=usuario.id,
        taller_id=usuario.taller_id,
        tabla="usuario",
        tabla_id=usuario.id,
        accion="RESET_PASSWORD",
        nuevo={"motivo": "Recuperación por email"}
    )

    db.commit()
    return {"msg": "Contraseña actualizada correctamente."}
