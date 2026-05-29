from fastapi import APIRouter, Depends, HTTPException,  Response, Query
from sqlalchemy.orm import Session, joinedload
from typing import List
from app.api import deps
from app.crud.crud_incidente import incidente_crud
from app.crud.crud_bitacora import bitacora_crud # 👈 Importante para la Regla de Oro
from app.schemas.incidente import Incidente as IncidenteSchema, IncidenteCreate, IncidenteUpdate
from app.models.incidente import Incidente  # 👈 Modelo ORM
from fastapi.encoders import jsonable_encoder
from app.models.usuario import Usuario
from typing import Optional
from datetime import datetime
from fpdf import FPDF
from app.models.pago import Pago
from app.models.bitacora import Bitacora # 👈 Agrega esta importación
from app.services.notificacion_service import NotificacionService # 👈 Servicio de notificaciones

router = APIRouter()

# 1. Reportar incidente (IA) - Mantenemos igual
@router.post("/", response_model=IncidenteSchema)
def crear_nuevo_incidente(*, db: Session = Depends(deps.get_db), obj_in: IncidenteCreate):
    return incidente_crud.create(db, obj_in=obj_in, usuario_id=obj_in.usuario_id)

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
