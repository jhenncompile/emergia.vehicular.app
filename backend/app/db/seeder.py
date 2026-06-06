import logging
from datetime import datetime, timedelta, time
from sqlalchemy.orm import Session
from decimal import Decimal
from app.db.session import SessionLocal
from faker import Faker
import random

# =================================================================
# 🚩 BLOQUE DE IMPORTACIONES DE SEGURIDAD (No tocar)
# =================================================================
from app.models.rol import Rol
from app.models.taller import Taller
from app.models.usuario import Usuario, Especialidad
from app.models.vehiculo import Vehiculo   
from app.models.incidente import Incidente 
from app.models.pago import Pago 
from app.models.bitacora import Bitacora
from app.models.notificacion import Notificacion
from app.models.evidencia import Evidencia
from app.models.taller_detalle import HorarioTaller

from app.core.estados import CanceladoPor, EstadoIncidente
from app.core.security import obtener_hash_clave as get_password_hash

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Inicializar Faker
fake = Faker('es_ES')
Faker.seed(42)  # Para reproducibilidad

# =================================================================
# 📍 COORDENADAS GPS DE SANTA CRUZ DE LA SIERRA, BOLIVIA
# =================================================================
# Centro de SC: -17.7869, -63.1904
# Rango aproximado: -17.65 a -17.85 lat, -63.05 a -63.35 lon

ZONAS_SC = [
    {"nombre": "Centro (Av. Banzer)", "lat": -17.786, "lon": -63.190, "radio": 0.02},
    {"nombre": "Plan 3000", "lat": -17.832, "lon": -63.135, "radio": 0.025},
    {"nombre": "Equipetrol", "lat": -17.761, "lon": -63.195, "radio": 0.02},
    {"nombre": "Villa 1ro de Mayo", "lat": -17.815, "lon": -63.182, "radio": 0.015},
    {"nombre": "Av. Santos Dumont", "lat": -17.795, "lon": -63.128, "radio": 0.015},
    {"nombre": "La Guardia Km 9", "lat": -17.865, "lon": -63.245, "radio": 0.03},
    {"nombre": "8vo Anillo Norte", "lat": -17.712, "lon": -63.158, "radio": 0.02},
    {"nombre": "Doble Vía La Guardia", "lat": -17.808, "lon": -63.208, "radio": 0.025},
]

CLASIFICACIONES_INCIDENTES = [
    "Falla de Motor",
    "Mantenimiento Preventivo",
    "Alineación y Balanceo",
    "Sistema de Frenos",
    "Fuga de refrigerante",
    "Aire Acondicionado",
    "Escaneo Computarizado",
    "Bomba de Gasolina",
    "Falla Eléctrica",
    "Revisión de Batería",
    "Sobrecalentamiento",
    "Falla de Embrague",
    "Ruido en Suspensión",
    "Pinchazo",
    "Cambio de Aceite",
    "Pastillas de Freno",
    "Filtro de Aire",
    "Correa de Distribución",
    "Radiador",
    "Bujías",
]

ESPECIALIDADES_NOMBRE = [
    "Mecánica General",
    "Electricidad Automotriz",
    "Llantería",
    "Refrigeración",
    "Transmisiones",
]

def generar_coords_en_zona(zona):
    """Genera coordenadas GPS dentro de una zona de SC"""
    lat = zona["lat"] + random.uniform(-zona["radio"], zona["radio"])
    lon = zona["lon"] + random.uniform(-zona["radio"], zona["radio"])
    return Decimal(str(round(lat, 6))), Decimal(str(round(lon, 6)))


def seed_db(db: Session) -> None:
    logger.info("🌱 Iniciando sembrado avanzado con FAKER (3 meses de movimiento)...")
    
    hash_clave = get_password_hash("password123")
    hoy = datetime.now()
    
    # ---------------------------------------------------------
    # 1. ROLES
    # ---------------------------------------------------------
    logger.info("👥 Creando ROLES...")
    roles_base = [
        {"id": 1, "nombre": "Administrador de Taller"},
        {"id": 2, "nombre": "Cliente"},
        {"id": 3, "nombre": "Técnico"}
    ]
    for r in roles_base:
        if not db.query(Rol).filter(Rol.id == r["id"]).first():
            db.add(Rol(**r))
    db.commit()
    
    # ---------------------------------------------------------
    # 2. ESPECIALIDADES
    # ---------------------------------------------------------
    logger.info("🔧 Creando ESPECIALIDADES...")
    especialidades = []
    for idx, nombre in enumerate(ESPECIALIDADES_NOMBRE, start=1):
        esp = db.query(Especialidad).filter(Especialidad.id == idx).first()
        if not esp:
            esp = Especialidad(id=idx, nombre=nombre, descripcion=f"Especialista en {nombre}")
            db.add(esp)
            especialidades.append(esp)
        else:
            especialidades.append(esp)
    db.commit()
    
    # ---------------------------------------------------------
    # 3. TALLERES (6 talleres en SC)
    # ---------------------------------------------------------
    logger.info("🏢 Creando TALLERES en Santa Cruz...")
    talleres_data = [
        {
            "nombre": "Taller Central SC",
            "direccion": "Av. Banzer 4to Anillo",
            "comision": 10.0,
            "zona": ZONAS_SC[0]
        },
        {
            "nombre": "Super Mecánica Plan 3000",
            "direccion": "Av. 4 Esquina 3er Anillo",
            "comision": 12.0,
            "zona": ZONAS_SC[1]
        },
        {
            "nombre": "Talleres Equipetrol",
            "direccion": "Av. Equipetrol",
            "comision": 11.0,
            "zona": ZONAS_SC[2]
        },
        {
            "nombre": "Mecánica Villa 1ro",
            "direccion": "Villa 1ro de Mayo",
            "comision": 9.5,
            "zona": ZONAS_SC[3]
        },
        {
            "nombre": "Auto Servicio Santos",
            "direccion": "Av. Santos Dumont 3er Anillo",
            "comision": 13.0,
            "zona": ZONAS_SC[4]
        },
        {
            "nombre": "Taller Express La Guardia",
            "direccion": "La Guardia Km 9",
            "comision": 10.5,
            "zona": ZONAS_SC[5]
        },
    ]
    
    talleres = []
    for idx, t_data in enumerate(talleres_data, start=1):
        taller = db.query(Taller).filter(Taller.id == idx).first()
        if not taller:
            lat, lon = generar_coords_en_zona(t_data["zona"])
            taller = Taller(
                id=idx,
                nombre=t_data["nombre"],
                direccion=t_data["direccion"],
                comision_porcentaje=t_data["comision"],
                latitud=lat,
                longitud=lon,
                estado=True
            )
            db.add(taller)
            talleres.append(taller)
        else:
            talleres.append(taller)
            # Guardar zona en objeto para usarlo después
            taller.zona = t_data["zona"]
    db.commit()
    
    # ---------------------------------------------------------
    # 4. USUARIOS (Admins de taller, Técnicos, Clientes)
    # ---------------------------------------------------------
    logger.info("👨‍💼 Creando USUARIOS (Admins, Técnicos, Clientes)...")
    usuario_id_counter = 1
    usuarios = []
    tecnicos = []
    clientes = []
    
    # Admins de taller (1 por taller)
    for idx, taller in enumerate(talleres, start=1):
        usuario = db.query(Usuario).filter(Usuario.correo == f"admin{idx}@taller.com").first()
        if not usuario:
            usuario = Usuario(
                id=usuario_id_counter,
                nombre=f"Admin {taller.nombre}",
                correo=f"admin{idx}@taller.com",
                clave_hash=hash_clave,
                rol_id=1,  # Admin
                taller_id=idx,
                esta_activo=True,
                telefono=fake.phone_number()[:20]  # Teléfono
            )
            db.add(usuario)
            usuarios.append(usuario)
            usuario_id_counter += 1
    db.commit()
    
    # Técnicos por taller (2-3 por taller)
    for taller in talleres:
        num_tecnicos = random.randint(2, 3)
        for t_idx in range(num_tecnicos):
            usuario = db.query(Usuario).filter(
                Usuario.correo == f"tec_{taller.id}_{t_idx}@taller.com"
            ).first()
            if not usuario:
                usuario = Usuario(
                    id=usuario_id_counter,
                    nombre=f"{fake.first_name()} {fake.last_name()}",
                    correo=f"tec_{taller.id}_{t_idx}@taller.com",
                    clave_hash=hash_clave,
                    rol_id=3,  # Técnico
                    taller_id=taller.id,
                    esta_activo=True,
                    telefono=fake.phone_number()[:20]  # Teléfono
                )
                # Asignar especialidades aleatorias
                esp = random.sample(especialidades, k=random.randint(1, 2))
                usuario.especialidades = esp
                db.add(usuario)
                usuarios.append(usuario)
                tecnicos.append(usuario)
                usuario_id_counter += 1
    db.commit()
    
    # Clientes (12-15 clientes que no tienen taller)
    for c_idx in range(12):
        usuario = db.query(Usuario).filter(
            Usuario.correo == f"cliente_{c_idx}@correo.com"
        ).first()
        if not usuario:
            usuario = Usuario(
                id=usuario_id_counter,
                nombre=fake.name(),
                correo=f"cliente_{c_idx}@correo.com",
                clave_hash=hash_clave,
                rol_id=2,  # Cliente
                taller_id=None,  # Sin taller
                esta_activo=True,
                telefono=fake.phone_number()[:20]  # Teléfono
            )
            db.add(usuario)
            usuarios.append(usuario)
            clientes.append(usuario)
            usuario_id_counter += 1
    db.commit()
    
    logger.info(f"✅ Creados {len(usuarios)} usuarios")
    
    # ---------------------------------------------------------
    # 5. VEHÍCULOS (2-3 por cliente)
    # ---------------------------------------------------------
    logger.info("🚗 Creando VEHÍCULOS...")
    vehiculos = []
    marcas = ["Toyota", "Honda", "Ford", "Chevrolet", "Nissan", "Hyundai", "Kia", "BMW", "Mercedes"]
    modelos = ["Corolla", "Civic", "Focus", "Spark", "Versa", "Elantra", "Picanto", "320i", "C200"]
    
    for cliente in clientes:
        num_vehiculos = random.randint(1, 2)
        for v_idx in range(num_vehiculos):
            placa = f"{random.randint(1000, 9999)}-{fake.bothify('???', letters='ABCDEFGHIJKLMNOPQRSTUVWXYZ')}"
            vehiculo = db.query(Vehiculo).filter(Vehiculo.placa == placa).first()
            if not vehiculo:
                vehiculo = Vehiculo(
                    placa=placa,
                    marca=random.choice(marcas),
                    modelo=random.choice(modelos),
                    usuario_id=cliente.id
                )
                db.add(vehiculo)
                vehiculos.append(vehiculo)
    db.commit()
    logger.info(f"✅ Creados {len(vehiculos)} vehículos")
    
    # ---------------------------------------------------------
    # 6. HORARIOS DE TALLERES
    # ---------------------------------------------------------
    logger.info("⏰ Creando HORARIOS...")
    dias_semana = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
    for taller in talleres:
        for dia in dias_semana:
            horario = db.query(HorarioTaller).filter(
                HorarioTaller.taller_id == taller.id,
                HorarioTaller.dia == dia
            ).first()
            if not horario:
                if dia == "domingo":
                    continue  # Cerrado el domingo
                elif dia == "sábado":
                    horario = HorarioTaller(
                        taller_id=taller.id,
                        dia=dia,
                        hora_apertura="09:00",
                        hora_cierre="14:00"
                    )
                else:
                    horario = HorarioTaller(
                        taller_id=taller.id,
                        dia=dia,
                        hora_apertura="08:00",
                        hora_cierre="18:00"
                    )
                db.add(horario)
    db.commit()
    
    # ---------------------------------------------------------
    # 7. INCIDENTES (200-300 incidentes en 1 año)
    # ---------------------------------------------------------
    logger.info("🚨 Creando INCIDENTES (últimos 365 días - 1 AÑO)...")
    incidentes = []
    estados_incidente = [
        EstadoIncidente.PENDIENTE,
        EstadoIncidente.BUSCANDO_TALLER,
        EstadoIncidente.ASIGNADO_TALLER,
        EstadoIncidente.EN_CAMINO,
        EstadoIncidente.EN_ATENCION,
        EstadoIncidente.FINALIZADO,
        EstadoIncidente.CANCELADO,
    ]
    prioridades = ["baja", "media", "alta"]
    
    # Calcular cuántos de cada estado
    num_incidentes = random.randint(250, 350)  # 250-350 incidentes en 1 año
    num_en_camino = 20  # Solo 20 en camino
    
    # Crear primero los 20 en_camino
    incidentes_en_camino = 0
    
    for inc_idx in range(num_incidentes):
        # Fecha aleatoria en los últimos 365 días (1 año)
        dias_atras = random.randint(0, 365)
        fecha_incidente = hoy - timedelta(days=dias_atras)
        
        # Seleccionar cliente y vehículo aleatorio
        cliente = random.choice(clientes)
        vehiculos_cliente = db.query(Vehiculo).filter(Vehiculo.usuario_id == cliente.id).all()
        if not vehiculos_cliente:
            continue
        vehiculo = random.choice(vehiculos_cliente)
        
        # Taller aleatorio
        taller = random.choice(talleres)
        
        # Distribución de estados: 20 en_camino, resto distribuidos
        if incidentes_en_camino < num_en_camino:
            estado = EstadoIncidente.EN_CAMINO
            incidentes_en_camino += 1
        else:
            estado = random.choices(
                estados_incidente,
                weights=[12, 10, 8, 0, 12, 40, 18],
            )[0]
        
        tecnico = None
        if estado in [
            EstadoIncidente.EN_CAMINO,
            EstadoIncidente.EN_ATENCION,
            EstadoIncidente.FINALIZADO,
        ]:
            tecnicos_taller = [t for t in tecnicos if t.taller_id == taller.id]
            if tecnicos_taller:
                tecnico = random.choice(tecnicos_taller)
        
        # Coordenadas en zona del taller o cercana
        zona = taller.zona if hasattr(taller, 'zona') else random.choice(ZONAS_SC)
        lat, lon = generar_coords_en_zona(zona)
        
        # Monto aleatorio
        monto = random.randint(150, 1500) if estado != EstadoIncidente.PENDIENTE else 0
        tiene_taller = estado not in [
            EstadoIncidente.PENDIENTE,
            EstadoIncidente.BUSCANDO_TALLER,
        ]

        incidente = Incidente(
            vehiculo_id=vehiculo.id,
            usuario_id=cliente.id,
            taller_id=taller.id if tiene_taller else None,
            tecnico_id=tecnico.id if tecnico else None,
            latitud=lat,
            longitud=lon,
            prioridad=random.choice(prioridades),
            estado=estado,
            pago_estado="pagado" if estado == EstadoIncidente.FINALIZADO else "pendiente",
            cancelado_por=(
                random.choice([CanceladoPor.CLIENTE, CanceladoPor.TALLER])
                if estado == EstadoIncidente.CANCELADO
                else None
            ),
            motivo_cancelacion=(
                fake.sentence(nb_words=6)
                if estado == EstadoIncidente.CANCELADO
                else None
            ),
            tiempo_asignacion_segundos=(
                random.randint(30, 600)
                if estado in [
                    EstadoIncidente.ASIGNADO_TALLER,
                    EstadoIncidente.EN_CAMINO,
                    EstadoIncidente.EN_ATENCION,
                    EstadoIncidente.FINALIZADO,
                ]
                else None
            ),
            clasificacion_ia=random.choice(CLASIFICACIONES_INCIDENTES),
            resumen_ia=fake.sentence(nb_words=8),
            fecha_creacion=fecha_incidente
        )
        db.add(incidente)
        incidentes.append(incidente)
    
    db.commit()
    logger.info(f"✅ Creados {len(incidentes)} incidentes (20 en_camino)")
    
    # ---------------------------------------------------------
    # 8. PAGOS (para incidentes finalizados)
    # ---------------------------------------------------------
    logger.info("💰 Creando PAGOS...")
    pagos = []
    for incidente in incidentes:
        if incidente.estado == EstadoIncidente.FINALIZADO and incidente.taller_id:
            taller = db.query(Taller).get(incidente.taller_id)
            monto = Decimal(str(random.randint(150, 1500)))
            comision = monto * Decimal(str(taller.comision_porcentaje / 100.0))
            
            pago = Pago(
                incidente_id=incidente.id,
                usuario_id=incidente.usuario_id,
                taller_id=incidente.taller_id,
                monto=monto,
                comision_plataforma=comision,
                metodo_pago=random.choice(["qr", "efectivo", "tarjeta"]),
                estado=random.choice(["completado", "pendiente"]),
                fecha=incidente.fecha_creacion + timedelta(days=random.randint(1, 5))
            )
            db.add(pago)
            pagos.append(pago)
    
    db.commit()
    logger.info(f"✅ Creados {len(pagos)} pagos")
    
    # ---------------------------------------------------------
    # 9. BITÁCORA (registros de actividades)
    # ---------------------------------------------------------
    logger.info("📝 Creando BITÁCORA...")
    bitacoras = []
    acciones = ["crear", "editar", "atender", "cancelar", "aprobar", "rechazar"]
    
    for incidente in incidentes[:100]:  # 100 registros de bitácora (más incidentes = más bitácoras)
        for _ in range(random.randint(1, 3)):
            bitacora = Bitacora(
                usuario_id=incidente.tecnico_id or incidente.usuario_id,
                taller_id=incidente.taller_id,
                tabla="incidente",
                tabla_id=incidente.id,
                accion=random.choice(acciones),
                valor_anterior={"estado": "pendiente"},
                valor_nuevo={"estado": incidente.estado},
                fecha_hora=incidente.fecha_creacion + timedelta(hours=random.randint(1, 72))
            )
            db.add(bitacora)
            bitacoras.append(bitacora)
    
    db.commit()
    logger.info(f"✅ Creados {len(bitacoras)} registros de bitácora")
    
    # ---------------------------------------------------------
    # 10. EVIDENCIAS (fotos de incidentes)
    # ---------------------------------------------------------
    logger.info("📷 Creando EVIDENCIAS...")
    evidencias = []
    
    for incidente in incidentes[:80]:  # 80 incidentes con evidencia (más con 1 año de datos)
        if incidente.estado in [EstadoIncidente.EN_CAMINO, EstadoIncidente.FINALIZADO]:
            num_fotos = random.randint(1, 3)
            for foto_idx in range(num_fotos):
                evidencia = Evidencia(
                    incidente_id=incidente.id,
                    tipo_archivo="imagen",
                    url_archivo=f"https://placeholder.com/300?text=Evidencia+{foto_idx+1}",
                    fecha_registro=incidente.fecha_creacion + timedelta(hours=random.randint(2, 48))
                )
                db.add(evidencia)
                evidencias.append(evidencia)
    
    db.commit()
    logger.info(f"✅ Creados {len(evidencias)} registros de evidencia")
    
    # ---------------------------------------------------------
    # 11. NOTIFICACIONES (para incidentes cercanos)
    # ---------------------------------------------------------
    logger.info("🔔 Creando NOTIFICACIONES...")
    notificaciones = []
    
    for incidente in incidentes[:60]:  # 60 notificaciones (más con 1 año)
        if incidente.taller_id:
            notificacion = Notificacion(
                usuario_id=incidente.usuario_id,
                incidente_id=incidente.id,
                titulo="Incidente cercano reportado",
                mensaje=f"Se reportó un {incidente.clasificacion_ia} cerca de tu ubicación",
                tipo="incidente_cercano",
                leido=random.choice([True, False]),
                fecha_envio=incidente.fecha_creacion
            )
            db.add(notificacion)
            notificaciones.append(notificacion)
    
    db.commit()
    logger.info(f"✅ Creados {len(notificaciones)} registros de notificación")
    
    # ---------------------------------------------------------
    # RESUMEN FINAL
    # ---------------------------------------------------------
    logger.info("\n" + "="*70)
    logger.info("✨ SEMBRADO COMPLETADO EXITOSAMENTE")
    logger.info("="*70)
    logger.info(f"📍 Roles: {db.query(Rol).count()}")
    logger.info(f"🔧 Especialidades: {db.query(Especialidad).count()}")
    logger.info(f"🏢 Talleres: {db.query(Taller).count()}")
    logger.info(f"👥 Usuarios: {db.query(Usuario).count()}")
    logger.info(f"🚗 Vehículos: {db.query(Vehiculo).count()}")
    logger.info(f"⏰ Horarios: {db.query(HorarioTaller).count()}")
    logger.info(f"🚨 Incidentes: {db.query(Incidente).count()}")
    logger.info(f"💰 Pagos: {db.query(Pago).count()}")
    logger.info(f"📝 Bitácora: {db.query(Bitacora).count()}")
    logger.info(f"📷 Evidencias: {db.query(Evidencia).count()}")
    logger.info(f"🔔 Notificaciones: {db.query(Notificacion).count()}")
    logger.info("="*70)
    logger.info("📊 Datos de 1 AÑO COMPLETO de movimiento en Santa Cruz de la Sierra")
    logger.info("="*70 + "\n")



if __name__ == "__main__":
    # Permite ejecutar `python seeder.py` directamente
    db = SessionLocal()
    try:
        seed_db(db)
        print("[OK] Seeder ejecutado con exito!")
    except Exception as e:
        print(f"❌ Error al ejecutar el seeder: {e}")
        import traceback
        traceback.print_exc()
        db.rollback()
    finally:
        db.close()
