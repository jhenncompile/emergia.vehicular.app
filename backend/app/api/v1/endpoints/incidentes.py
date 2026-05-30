import logging
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Response, Query, UploadFile, File, Form
from sqlalchemy.orm import Session, joinedload
from typing import List
from app.api import deps
from app.crud.crud_incidente import incidente_crud
from app.crud.crud_bitacora import bitacora_crud # 👈 Importante para la Regla de Oro
from app.crud.crud_evidencia import evidencia_crud
from app.schemas.evidencia import EvidenciaCreate
from app.schemas.incidente import Incidente as IncidenteSchema, IncidenteCreate, IncidenteUpdate
from app.models.incidente import Incidente  # 👈 Modelo ORM
from fastapi.encoders import jsonable_encoder
from app.models.usuario import Usuario
from app.models.vehiculo import Vehiculo
from typing import Optional
from datetime import datetime
from fpdf import FPDF
from app.models.pago import Pago
from app.models.bitacora import Bitacora # 👈 Agrega esta importación
from app.services.notificacion_service import NotificacionService # 👈 Servicio de notificaciones
from app.services.ai_service import AIService, AIServiceError, HuggingFaceAPIError

logger = logging.getLogger(__name__)

router = APIRouter()
UPLOADS_DIR = Path("uploads") / "incidentes"
ALLOWED_AUDIO_FORMATS = {"audio/mpeg", "audio/wav", "audio/ogg", "audio/flac", "audio/mp4"}


def _transcribir_audio_si_es_posible(audio_data: bytes) -> tuple[str | None, str | None]:
    try:
        transcripcion = AIService().transcribe_audio(audio_data)
        return transcripcion, None
    except (AIServiceError, HuggingFaceAPIError) as e:
        logger.warning("No se pudo transcribir audio del incidente: %s", str(e))
        return None, str(e)


def _clasificar_por_texto(texto: str) -> str:
    texto_normalizado = texto.lower()
    reglas = [
        ("Pinchazo", ["pinch", "llanta", "neumatico", "neumático", "rueda"]),
        ("Falla Eléctrica", ["elect", "bateria", "batería", "alternador", "luces"]),
        ("Fuga de refrigerante", ["refrigerante", "agua", "fuga", "radiador"]),
        ("Sobrecalentamiento", ["calienta", "sobrecal", "temperatura", "humo"]),
        ("Sistema de Frenos", ["freno", "frenos", "pastilla"]),
        ("Falla de Motor", ["motor", "arranca", "apaga", "aceite"]),
        ("Transmisiones", ["embrague", "caja", "transmision", "transmisión"]),
        ("Aire Acondicionado", ["aire acondicionado", "ac", "climatizador"]),
    ]

    for categoria, palabras in reglas:
        if any(palabra in texto_normalizado for palabra in palabras):
            return categoria

    return "Otro / No clasificado"


def _prioridad_por_texto(texto: str) -> str:
    texto_normalizado = texto.lower()
    alta = ["choque", "accidente", "fuego", "incendio", "herido", "sangre", "humo"]
    if any(palabra in texto_normalizado for palabra in alta):
        return "alta"
    return "media"

# 1. Reportar incidente (IA) - Mantenemos igual
@router.post("/", response_model=IncidenteSchema)
def crear_nuevo_incidente(*, db: Session = Depends(deps.get_db), obj_in: IncidenteCreate):
    return incidente_crud.create(db, obj_in=obj_in, usuario_id=obj_in.usuario_id)


@router.post("/reportar-audio", response_model=IncidenteSchema)
async def crear_incidente_con_audio(
    *,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_cliente),
    vehiculo_id: int = Form(...),
    descripcion: str = Form(""),
    ubicacion: str = Form("Ubicacion seleccionada en mapa"),
    latitud: float = Form(...),
    longitud: float = Form(...),
    audio: UploadFile | None = File(None),
):
    """Crea un incidente desde movil y procesa audio opcional con IA."""
    vehiculo = db.query(Vehiculo).filter(
        Vehiculo.id == vehiculo_id,
        Vehiculo.usuario_id == current_user.id,
    ).first()
    if not vehiculo:
        raise HTTPException(
            status_code=404,
            detail="Vehiculo no encontrado para el cliente autenticado.",
        )

    transcripcion = None
    error_ia = None
    ruta_audio = None

    if audio is not None:
        if audio.content_type not in ALLOWED_AUDIO_FORMATS:
            raise HTTPException(
                status_code=400,
                detail="Formato de audio no soportado.",
            )

        audio_data = await audio.read()
        if audio_data:
            UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
            extension = Path(audio.filename or "audio.m4a").suffix or ".m4a"
            nombre_archivo = f"{uuid4().hex}{extension}"
            ruta_audio = UPLOADS_DIR / nombre_archivo
            ruta_audio.write_bytes(audio_data)

            transcripcion, error_ia = _transcribir_audio_si_es_posible(audio_data)

    texto_para_ia = " ".join(
        parte for parte in [descripcion, transcripcion] if parte
    )
    clasificacion = _clasificar_por_texto(texto_para_ia)
    resumen = transcripcion or descripcion or "Sin descripcion/transcripcion disponible"
    if error_ia:
        resumen = f"{resumen}\n\nIA audio no disponible: {error_ia}".strip()

    obj_in = IncidenteCreate(
        usuario_id=current_user.id,
        vehiculo_id=vehiculo_id,
        descripcion=descripcion,
        ubicacion=ubicacion,
        latitud=latitud,
        longitud=longitud,
        prioridad=_prioridad_por_texto(texto_para_ia),
        estado="pendiente",
        pago_estado="pendiente",
        telefono_cliente=current_user.telefono or "No disponible",
        transcripcion_audio=transcripcion,
        clasificacion_ia=clasificacion,
        resumen_ia=resumen,
    )
    incidente = incidente_crud.create(db, obj_in=obj_in, usuario_id=current_user.id)

    if ruta_audio is not None:
        evidencia_crud.create(
            db,
            obj_in=EvidenciaCreate(
                incidente_id=incidente.id,
                tipo_archivo="audio",
                url_archivo=str(ruta_audio),
            ),
            usuario_id=current_user.id,
        )

    return incidente

# 2. Pendientes: Solo los que no tienen taller asignado
# Reemplaza tu función leer_incidentes_pendientes por esta:

@router.get("/pendientes", response_model=List[IncidenteSchema])
def leer_incidentes_pendientes(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    """Visualizar auxilios disponibles, filtrando los que este taller ya rechazó."""
    from sqlalchemy.orm import joinedload
    from app.models.taller import Taller
    
    # 1. Traemos todos los incidentes sin taller (taller_id is None) y cargamos taller
    incidentes = db.query(Incidente).filter(
        Incidente.estado == "pendiente"
    ).options(joinedload(Incidente.taller), joinedload(Incidente.vehiculo)).all()
    
    if not current_user.taller_id:
        return incidentes

    # 2. Obtener datos del taller del usuario actual
    taller_actual = db.query(Taller).filter(Taller.id == current_user.taller_id).first()
    
    # 3. Consultamos la Bitácora para ver qué incidentes rechazó este taller
    rechazados_ids = db.query(Bitacora.tabla_id).filter(
        Bitacora.taller_id == current_user.taller_id,
        Bitacora.tabla == "incidente",
        Bitacora.accion.like("RECHAZAR%")
    ).all()
    
    lista_negra = [r[0] for r in rechazados_ids]

    # 4. Filtramos y calculamos distancia
    resultado = []
    for incidente in incidentes:
        if incidente.id not in lista_negra:
            # 📏 Calcular distancia si taller actual existe
            if taller_actual and taller_actual.latitud and taller_actual.longitud:
                distancia = incidente_crud.calcular_distancia_haversine(
                    float(taller_actual.latitud),
                    float(taller_actual.longitud),
                    float(incidente.latitud),
                    float(incidente.longitud)
                )
                incidente.distancia_metros = distancia
            resultado.append(incidente)
    
    # Ordenar por distancia (cercanos primero)
    resultado.sort(key=lambda x: x.distancia_metros if x.distancia_metros else float('inf'))
    return resultado

@router.get("/mis-incidentes", response_model=List[IncidenteSchema])
def leer_mis_incidentes_cliente(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_cliente)
):
    """Lista todos los incidentes del cliente autenticado para el móvil."""
    incidentes = db.query(Incidente).filter(
        Incidente.usuario_id == current_user.id
    ).options(
        joinedload(Incidente.taller),
        joinedload(Incidente.vehiculo),
        joinedload(Incidente.tecnico),
        joinedload(Incidente.pagos)
    ).order_by(Incidente.fecha_creacion.desc()).all()

    return incidentes

# 3. MI PANEL: Emergencias que YO (como taller) estoy atendiendo
@router.get("/mis-atenciones", response_model=List[IncidenteSchema])
def leer_mis_atenciones(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    """Filtra incidentes por el taller_id del usuario logueado"""
    from sqlalchemy.orm import joinedload
    from app.models.taller import Taller
    
    if not current_user.taller_id:
        raise HTTPException(status_code=400, detail="El usuario no pertenece a un taller")
    
    # Cargar incidentes con taller
    incidentes = db.query(Incidente).filter(
        Incidente.taller_id == current_user.taller_id
    ).options(joinedload(Incidente.taller), joinedload(Incidente.vehiculo)).all()
    
    # Obtener datos del taller actual
    taller_actual = db.query(Taller).filter(Taller.id == current_user.taller_id).first()
    
    # 📏 Calcular distancia para cada incidente
    for incidente in incidentes:
        if taller_actual and taller_actual.latitud and taller_actual.longitud:
            distancia = incidente_crud.calcular_distancia_haversine(
                float(taller_actual.latitud),
                float(taller_actual.longitud),
                float(incidente.latitud),
                float(incidente.longitud)
            )
            incidente.distancia_metros = distancia
    
    # Ordenar por distancia (cercanos primero)
    incidentes.sort(key=lambda x: x.distancia_metros if x.distancia_metros else float('inf'))
    return incidentes

# 4. ACEPTAR: El taller toma el incidente
@router.patch("/{id}/aceptar", response_model=IncidenteSchema)
def aceptar_incidente(
    *,
    db: Session = Depends(deps.get_db),
    id: int,
    current_user = Depends(deps.get_current_active_user)
):
    """El taller del token se asigna el incidente automáticamente"""
    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")
    
    if incidente_db.taller_id:
        raise HTTPException(status_code=400, detail="Este incidente ya fue tomado por otro taller")

    # Guardamos estado anterior para bitácora
    anterior = jsonable_encoder(incidente_db)

    # Asignamos el taller del usuario logueado
    actualizado = incidente_crud.asignar_taller(
        db, 
        db_obj=incidente_db, 
        taller_id=current_user.taller_id
    )

    # 📝 BITÁCORA DE AUDITORÍA
    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="incidente",
        tabla_id=id,
        accion="ACEPTAR_INCIDENTE",
        anterior=anterior,
        nuevo=jsonable_encoder(actualizado)
    )
    
    # 🔔 NOTIFICACIÓN: Avisar al cliente que su incidente fue aceptado
    taller = db.query(Usuario).filter(Usuario.id == current_user.id).first()
    taller_nombre = taller.nombre if taller else "Taller"
    
    NotificacionService.notificar_incidente_aceptado(
        db=db,
        cliente_id=incidente_db.usuario_id,
        incidente_id=id,
        taller_nombre=taller_nombre
    )

    # Al aceptar, el CRUD mueve el incidente a "en_proceso"; esto equivale a
    # avisar al cliente que el auxilio ya está en camino.
    NotificacionService.notificar_cambio_estado(
        db=db,
        incidente=actualizado,
        estado_anterior=anterior.get("estado"),
        estado_nuevo=actualizado.estado
    )
    
    return actualizado
@router.patch("/{id}/asignar-tecnico", response_model=IncidenteSchema)
def asignar_tecnico_a_incidente(
    *,
    db: Session = Depends(deps.get_db),
    id: int,
    tecnico_id: int, # Recibimos el ID del técnico por parámetro
    current_user = Depends(deps.get_current_admin_taller)
):
    """Asigna un técnico del taller a una emergencia ya aceptada."""
    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db or incidente_db.taller_id != current_user.taller_id:
        raise HTTPException(status_code=403, detail="No puedes asignar técnicos a este incidente.")

    # Opcional: Validar que el técnico pertenezca al mismo taller
    tecnico = db.query(Usuario).filter(Usuario.id == tecnico_id, Usuario.taller_id == current_user.taller_id).first()
    if not tecnico:
        raise HTTPException(status_code=400, detail="El técnico no pertenece a tu taller.")

    anterior = jsonable_encoder(incidente_db)
    actualizado = incidente_crud.asignar_tecnico(db, db_obj=incidente_db, tecnico_id=tecnico_id)

    bitacora_crud.registrar(db, usuario_id=current_user.id, taller_id=current_user.taller_id,
                            tabla="incidente", tabla_id=id, accion="ASIGNAR_TECNICO",
                            anterior=anterior, nuevo=jsonable_encoder(actualizado))
    
    # 🔔 NOTIFICACIÓN: Avisar al técnico que se le asignó un incidente
    NotificacionService.notificar_tecnico_asignado(
        db=db,
        tecnico_id=tecnico_id,
        incidente_id=id,
        incidente=actualizado
    )
    
    return actualizado

@router.patch("/{id}/rechazar", response_model=IncidenteSchema)
def rechazar_pedido_auxilio(
    *,
    db: Session = Depends(deps.get_db),
    id: int,
    motivo: str,
    current_user = Depends(deps.get_current_admin_taller)
):
    """Rechaza el auxilio y lo devuelve a la lista global de pendientes."""
    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")
    
    # Seguridad: Solo el taller que lo tiene o si está libre se puede rechazar
    if incidente_db.taller_id and incidente_db.taller_id != current_user.taller_id:
        raise HTTPException(status_code=403, detail="No puedes rechazar un incidente de otro taller.")

    anterior = jsonable_encoder(incidente_db)

    # 🚩 LA CLAVE DEL ÉXITO: Liberar el incidente
    # Al poner taller y técnico en None y estado en 'pendiente', vuelve a "Disponibles"
    incidente_db.taller_id = None
    incidente_db.tecnico_id = None
    incidente_db.estado = "pendiente"
    incidente_db.motivo_cancelacion = motivo
    
    db.add(incidente_db)
    db.commit()
    db.refresh(incidente_db)

    # 📝 BITÁCORA DE AUDITORÍA (Regla de Oro)
    bitacora_crud.registrar(
        db, 
        usuario_id=current_user.id, 
        taller_id=current_user.taller_id,
        tabla="incidente", 
        tabla_id=id, 
        accion="RECHAZAR_Y_LIBERAR",
        anterior=anterior, 
        nuevo=jsonable_encoder(incidente_db)
    )
    
    # 🔔 NOTIFICACIÓN: Avisar al cliente que su incidente fue rechazado
    taller = db.query(Usuario).filter(Usuario.id == current_user.id).first()
    taller_nombre = taller.nombre if taller else "Taller"
    
    NotificacionService.notificar_incidente_rechazado(
        db=db,
        cliente_id=incidente_db.usuario_id,
        incidente_id=id,
        taller_nombre=taller_nombre,
        motivo=motivo
    )
    
    return incidente_db

# 5. FINALIZAR: Cambiar el estado a "atendido"
@router.put("/{id}", response_model=IncidenteSchema)
def actualizar_estado_incidente(
    *,
    db: Session = Depends(deps.get_db),
    id: int,
    obj_in: IncidenteUpdate, # Usamos el schema de actualización
    current_user = Depends(deps.get_current_active_user)
):
    """Actualiza el estado de un incidente (Finalizar servicio)"""
    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")
    
    # QA: Verificar que solo el taller asignado pueda finalizarlo
    if incidente_db.taller_id != current_user.taller_id:
        raise HTTPException(
            status_code=403, 
            detail="No tienes permiso para finalizar un auxilio que no te pertenece."
        )

    # Guardamos estado anterior para notificaciones
    estado_anterior = incidente_db.estado
    anterior = jsonable_encoder(incidente_db)

    # Actualizamos usando el CRUD
    actualizado = incidente_crud.update(db, db_obj=incidente_db, obj_in=obj_in)

    # 📝 BITÁCORA DE AUDITORÍA
    bitacora_crud.registrar(
        db,
        usuario_id=current_user.id,
        taller_id=current_user.taller_id,
        tabla="incidente",
        tabla_id=id,
        accion="FINALIZAR_AUXILIO",
        anterior=anterior,
        nuevo=jsonable_encoder(actualizado)
    )
    
    # 🔔 NOTIFICACIÓN: Enviar solo si el estado cambió realmente.
    if obj_in.estado and estado_anterior != actualizado.estado:
        NotificacionService.notificar_cambio_estado(
            db=db,
            incidente=actualizado,
            estado_anterior=estado_anterior,
            estado_nuevo=actualizado.estado
        )
    
    return actualizado

# ==========================================
# 📊 NUEVO: HISTORIAL Y MÉTRICAS
# ==========================================
@router.get("/historial/lista", response_model=List[IncidenteSchema])
def obtener_historial(
    fecha_inicio: Optional[datetime] = None,
    fecha_fin: Optional[datetime] = None,
    estados: Optional[List[str]] = Query(None), # 👈 Recibe ?estados=atendido&estados=cancelado
    tecnico_id: Optional[int] = None,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    if not current_user.taller_id:
        raise HTTPException(status_code=403, detail="El usuario no pertenece a un taller")
        
    return incidente_crud.obtener_historial_taller(
        db=db, 
        taller_id=current_user.taller_id,
        fecha_inicio=fecha_inicio,
        fecha_fin=fecha_fin,
        estados=estados,
        tecnico_id=tecnico_id
    )

@router.get("/historial/metricas")
def obtener_kpis(
    fecha_inicio: Optional[datetime] = None,
    fecha_fin: Optional[datetime] = None,
    estados: Optional[List[str]] = Query(None),
    tecnico_id: Optional[int] = None,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    """Retorna las estadísticas del dashboard de historial, con filtros aplicados."""
    if not current_user.taller_id:
        raise HTTPException(status_code=403, detail="El usuario no pertenece a un taller")
        
    return incidente_crud.obtener_metricas_taller(
        db=db, 
        taller_id=current_user.taller_id,
        fecha_inicio=fecha_inicio,
        fecha_fin=fecha_fin,
        estados=estados,
        tecnico_id=tecnico_id
    )

# ==========================================
# 📄 NUEVO: GENERACIÓN DE PDF
# ==========================================
@router.get("/{id}/reporte-pdf")
def descargar_reporte_tecnico(
    id: int, 
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    inc = incidente_crud.get(db, id=id)
    if not inc or inc.taller_id != current_user.taller_id:
        raise HTTPException(status_code=403, detail="No autorizado")

    pago = db.query(Pago).filter(Pago.incidente_id == id).first()
    monto_pago = pago.monto if pago else "No registrado"
    tecnico_nombre = inc.tecnico.nombre if inc.tecnico else "Sin asignar"

    pdf = FPDF()
    pdf.add_page()

    # Cabecera
    pdf.set_font("helvetica", style="B", size=16)
    pdf.set_text_color(59, 130, 246)
    pdf.cell(0, 10, "REPORTE TECNICO DE AUXILIO", new_x="LMARGIN", new_y="NEXT", align="C")

    pdf.set_font("helvetica", size=11)
    pdf.set_text_color(100, 116, 139)
    pdf.cell(0, 8, f"Taller: {inc.taller.nombre}", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.cell(0, 8, f"ID Incidente: #{inc.id}  |  Fecha: {inc.fecha_creacion.strftime('%d/%m/%Y')}", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(10)

    # Cuerpo
    pdf.set_font("helvetica", style="B", size=12)
    pdf.set_text_color(15, 23, 42)
    pdf.cell(0, 10, "Resumen del Servicio", new_x="LMARGIN", new_y="NEXT")

    pdf.set_font("helvetica", size=11)
    pdf.cell(45, 8, "Estado:")
    pdf.cell(0, 8, f"{inc.estado.upper()}", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(45, 8, "Prioridad:")
    pdf.cell(0, 8, f"{inc.prioridad.upper()}", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(45, 8, "Tecnico:")
    pdf.cell(0, 8, f"{tecnico_nombre}", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(45, 8, "Monto Cobrado:")
    pdf.cell(0, 8, f"Bs. {monto_pago}", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(8)

    pdf.set_font("helvetica", style="B", size=12)
    pdf.cell(0, 10, "Diagnostico de IA", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("helvetica", size=11)
    
    # 👇 Corrección aplicada aquí con new_x y new_y
    pdf.multi_cell(0, 8, f"Clasificacion: {inc.clasificacion_ia or 'Sin clasificar'}", new_x="LMARGIN", new_y="NEXT")
    pdf.multi_cell(0, 8, f"Resumen IA: {inc.resumen_ia or 'No se genero resumen automatico.'}", new_x="LMARGIN", new_y="NEXT")
    
    pdf.ln(20)
    pdf.set_font("helvetica", style="I", size=9)
    pdf.set_text_color(148, 163, 184)
    pdf.cell(0, 10, "Este documento es un reporte generado automaticamente por Taller Pro SaaS.", new_x="LMARGIN", new_y="NEXT", align="C")

    return Response(
        content=bytes(pdf.output()),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=reporte_tecnico_{id}.pdf"}
    )
# ==========================================
# 🔧 NUEVOS: ENDPOINTS PARA TÉCNICO
# ==========================================
# 🔧 NUEVOS: ENDPOINTS PARA TÉCNICO
# ==========================================

@router.get("/tecnico/mis-incidentes", response_model=List[IncidenteSchema])
def obtener_incidentes_del_tecnico(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    """
    Obtiene todos los incidentes asignados al técnico autenticado.
    Solo rol_id = 3 (Técnico) puede acceder.
    """
    if current_user.rol_id != 3:
        raise HTTPException(status_code=403, detail="Solo técnicos pueden acceder a esta sección.")
    
    incidentes = db.query(Incidente).filter(
        Incidente.tecnico_id == current_user.id
    ).order_by(Incidente.fecha_creacion.desc()).all()
    
    return incidentes

@router.get("/{id}", response_model=IncidenteSchema)
def obtener_incidente_por_id(
    id: int,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_active_user)
):
    """
    Obtiene los detalles de un incidente específico con todas sus relaciones.
    El técnico solo puede ver incidentes asignados a él.
    El admin puede ver cualquier incidente.
    """
    from sqlalchemy.orm import joinedload
    
    incidente = db.query(Incidente).filter(
        Incidente.id == id
    ).options(
        joinedload(Incidente.usuario),
        joinedload(Incidente.taller),
        joinedload(Incidente.vehiculo),
        joinedload(Incidente.tecnico)
    ).first()
    
    if not incidente:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")
    
    # Control de acceso: solo técnico (rol_id=3) puede ver sus propios incidentes, admin (rol_id=1) ve todos
    if current_user.rol_id == 3 and incidente.tecnico_id != current_user.id:
        raise HTTPException(status_code=403, detail="No tienes permiso para ver este incidente")
    
    return incidente
