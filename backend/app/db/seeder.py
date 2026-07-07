import logging
import unicodedata
from datetime import datetime, timedelta, time
from sqlalchemy.orm import Session
from decimal import Decimal
from app.db.session import SessionLocal
from faker import Faker
import random

# =================================================================
# 🚩 BLOQUE DE IMPORTACIONES DE SEGURIDAD (No tocar)
# =================================================================
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
from app.models.asignacion_inteligente import IncidenteAsignacionCandidato
from app.models.pago import Pago 
from app.models.bitacora import Bitacora
from app.models.notificacion import Notificacion
from app.models.evidencia import Evidencia
from app.models.taller_detalle import HorarioTaller
from app.models.calificacion import Calificacion

from app.core.estados import CanceladoPor, EstadoIncidente
from app.core.security import obtener_hash_clave as get_password_hash
from app.services.ranking_taller_service import MAPEO_CATEGORIA_ESPECIALIDADES

def get_or_create_stripe_account(email: str, nombre: str):
    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
    if not stripe.api_key:
        return None
    try:
        account = stripe.Account.create(
            type="express",
            country="US",
            email=email,
            capabilities={
                "card_payments": {"requested": True},
                "transfers": {"requested": True},
            },
            business_type="company",
            business_profile={"url": "https://vialia-auxilio.com", "name": nombre}
        )
        return account.id
    except Exception as e:
        print(f"Error creando cuenta stripe: {e}")
        return None

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

CLASIFICACION_ASIGNACION_ALIAS = {
    "Escaneo Computarizado": "Falla Eléctrica",
    "Pastillas de Freno": "Sistema de Frenos",
    "Radiador": "Fuga de refrigerante",
}


def normalizar_especialidad(texto: str) -> str:
    texto = unicodedata.normalize("NFD", texto.lower().strip())
    return "".join(char for char in texto if unicodedata.category(char) != "Mn")


def criterio_especialidades_por_clasificacion(clasificacion: str) -> tuple[set[str], bool]:
    categoria = CLASIFICACION_ASIGNACION_ALIAS.get(clasificacion, clasificacion)
    requeridas = MAPEO_CATEGORIA_ESPECIALIDADES.get(categoria, [])
    obligatorias = [
        nombre
        for nombre, _peso, es_obligatoria in requeridas
        if es_obligatoria
    ]
    if obligatorias:
        return {normalizar_especialidad(nombre) for nombre in obligatorias}, True
    return {
        normalizar_especialidad(nombre)
        for nombre, _peso, _es_obligatoria in requeridas
    }, False


def especialidades_taller_seed(taller: Taller) -> set[str]:
    especialidades = set()
    for usuario in taller.usuarios:
        if usuario.rol_id == 3 and usuario.esta_activo:
            for especialidad in usuario.especialidades:
                especialidades.add(normalizar_especialidad(especialidad.nombre))
    return especialidades


def taller_cubre_clasificacion(taller: Taller, clasificacion: str) -> bool:
    requeridas, exige_todas = criterio_especialidades_por_clasificacion(clasificacion)
    if not requeridas:
        return True
    especialidades = especialidades_taller_seed(taller)
    if exige_todas:
        return requeridas.issubset(especialidades)
    return bool(requeridas & especialidades)


def elegir_taller_para_clasificacion(talleres: list[Taller], clasificacion: str) -> Taller:
    compatibles = [
        taller
        for taller in talleres
        if taller_cubre_clasificacion(taller, clasificacion)
    ]
    return random.choice(compatibles or talleres)


def garantizar_cobertura_especialidades(
    tecnicos: list[Usuario],
    especialidades: list[Especialidad],
) -> None:
    if not tecnicos:
        return

    for index, especialidad in enumerate(especialidades):
        tecnico = tecnicos[index % len(tecnicos)]
        nombres_actuales = {
            normalizar_especialidad(item.nombre)
            for item in tecnico.especialidades
        }
        if normalizar_especialidad(especialidad.nombre) not in nombres_actuales:
            tecnico.especialidades.append(especialidad)


def generar_coords_en_zona(zona):
    """Genera coordenadas GPS dentro de una zona de SC"""
    lat = zona["lat"] + random.uniform(-zona["radio"], zona["radio"])
    lon = zona["lon"] + random.uniform(-zona["radio"], zona["radio"])
    return Decimal(str(round(lat, 6))), Decimal(str(round(lon, 6)))


def seed_db(
    db: Session,
    *,
    talleres_count: int = 6,
    clientes_count: int = 12,
    incidentes_count: int | None = None,
    incidentes_min: int = 250,
    incidentes_max: int = 350,
    tecnicos_por_taller_min: int = 2,
    tecnicos_por_taller_max: int = 3,
    vehiculos_por_cliente_min: int = 1,
    vehiculos_por_cliente_max: int = 2,
    bitacoras_count: int = 100,
    evidencias_count: int = 80,
    notificaciones_count: int = 60,
    dias_historial: int = 365,
    seed: int | None = None,
) -> None:
    talleres_count = max(1, talleres_count)
    clientes_count = max(1, clientes_count)
    incidentes_min = max(0, incidentes_min)
    incidentes_max = max(incidentes_min, incidentes_max)
    tecnicos_por_taller_min = max(1, tecnicos_por_taller_min)
    tecnicos_por_taller_max = max(tecnicos_por_taller_min, tecnicos_por_taller_max)
    vehiculos_por_cliente_min = max(1, vehiculos_por_cliente_min)
    vehiculos_por_cliente_max = max(
        vehiculos_por_cliente_min,
        vehiculos_por_cliente_max,
    )
    bitacoras_count = max(0, bitacoras_count)
    evidencias_count = max(0, evidencias_count)
    notificaciones_count = max(0, notificaciones_count)
    dias_historial = max(1, dias_historial)

    if seed is None:
        seed = random.SystemRandom().randint(1, 999_999_999)
    random.seed(seed)
    Faker.seed(seed)
    fake.seed_instance(seed)

    logger.info("🌱 Iniciando sembrado avanzado con FAKER")
    logger.info(f"🎲 Semilla de datos: {seed}")
    logger.info(
        "⚙️ Configuración: "
        f"talleres={talleres_count}, "
        f"clientes={clientes_count}, "
        f"incidentes={incidentes_count or f'{incidentes_min}-{incidentes_max}'}, "
        f"técnicos/taller={tecnicos_por_taller_min}-{tecnicos_por_taller_max}, "
        f"vehículos/cliente={vehiculos_por_cliente_min}-{vehiculos_por_cliente_max}"
    )
    
    hash_clave = get_password_hash("password123")
    # UTC para ser consistente con func.now() que usa la app (evita desfase de zona horaria)
    hoy = datetime.utcnow()
    
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
    # 3. TALLERES
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

    for idx in range(len(talleres_data) + 1, talleres_count + 1):
        zona = random.choice(ZONAS_SC)
        talleres_data.append(
            {
                "nombre": f"{fake.company()} Taller {idx}",
                "direccion": f"{fake.street_address()} - {zona['nombre']}",
                "comision": round(random.uniform(8.0, 14.0), 2),
                "zona": zona,
            }
        )
    talleres_data = talleres_data[:talleres_count]
    
    talleres = []
    for idx, t_data in enumerate(talleres_data, start=1):
        taller = db.query(Taller).filter(Taller.id == idx).first()
        if not taller:
            lat, lon = generar_coords_en_zona(t_data["zona"])
            
            # Asignar cuenta Stripe
            cuenta_stripe = t_data.get("stripe_account_id")
            if not cuenta_stripe:
                if idx == 1:
                    cuenta_stripe = "acct_1TfpJPRFvD93OkDf" # La cuenta conectada por defecto
                else:
                    # Para no spamear la API, los demas talleres los dejamos sin stripe o creamos on the fly
                    # cuenta_stripe = get_or_create_stripe_account(f"taller{idx}@emergencia.com", t_data["nombre"])
                    cuenta_stripe = None
                    
            taller = Taller(
                id=idx,
                nombre=t_data["nombre"],
                direccion=t_data["direccion"],
                comision_porcentaje=t_data["comision"],
                latitud=lat,
                longitud=lon,
                estado=True,
                stripe_account_id=cuenta_stripe
            )
            taller.zona = t_data["zona"]
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
    
    # Técnicos por taller
    for taller in talleres:
        num_tecnicos = random.randint(
            tecnicos_por_taller_min,
            tecnicos_por_taller_max,
        )
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

    garantizar_cobertura_especialidades(tecnicos, especialidades)
    db.commit()
    
    # Clientes que no tienen taller
    for c_idx in range(clientes_count):
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
    # 5. VEHÍCULOS
    # ---------------------------------------------------------
    logger.info("🚗 Creando VEHÍCULOS...")
    vehiculos = []
    marcas = ["Toyota", "Honda", "Ford", "Chevrolet", "Nissan", "Hyundai", "Kia", "BMW", "Mercedes"]
    modelos = ["Corolla", "Civic", "Focus", "Spark", "Versa", "Elantra", "Picanto", "320i", "C200"]
    
    for cliente in clientes:
        num_vehiculos = random.randint(
            vehiculos_por_cliente_min,
            vehiculos_por_cliente_max,
        )
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
                        hora_apertura=time(9, 0),
                        hora_cierre=time(14, 0),
                    )
                else:
                    horario = HorarioTaller(
                        taller_id=taller.id,
                        dia=dia,
                        hora_apertura=time(8, 0),
                        hora_cierre=time(18, 0),
                    )
                db.add(horario)
    db.commit()
    
    # ---------------------------------------------------------
    # 7. INCIDENTES FINALIZADOS
    # ---------------------------------------------------------
    logger.info("🚨 Creando INCIDENTES FINALIZADOS...")
    incidentes = []
    prioridades = ["baja", "media", "alta"]
    
    if incidentes_count is None:
        num_incidentes = random.randint(incidentes_min, incidentes_max)
    else:
        num_incidentes = max(0, incidentes_count)
    
    for inc_idx in range(num_incidentes):
        # Fecha aleatoria dentro del historial configurado
        dias_atras = random.randint(0, dias_historial)
        fecha_incidente = hoy - timedelta(days=dias_atras)
        
        # Seleccionar cliente y vehículo aleatorio
        cliente = random.choice(clientes)
        vehiculos_cliente = db.query(Vehiculo).filter(Vehiculo.usuario_id == cliente.id).all()
        if not vehiculos_cliente:
            continue
        vehiculo = random.choice(vehiculos_cliente)
        
        clasificacion = random.choice(CLASIFICACIONES_INCIDENTES)
        taller = elegir_taller_para_clasificacion(talleres, clasificacion)
        
        estado = EstadoIncidente.FINALIZADO
        
        tecnico = None
        tecnicos_taller = [t for t in tecnicos if t.taller_id == taller.id]
        if tecnicos_taller:
            tecnico = random.choice(tecnicos_taller)
        
        # Coordenadas en zona del taller o cercana
        zona = taller.zona if hasattr(taller, 'zona') else random.choice(ZONAS_SC)
        lat, lon = generar_coords_en_zona(zona)
        
        incidente = Incidente(
            vehiculo_id=vehiculo.id,
            usuario_id=cliente.id,
            taller_id=taller.id,
            tecnico_id=tecnico.id if tecnico else None,
            descripcion=fake.sentence(nb_words=10),
            ubicacion=zona["nombre"],
            latitud=lat,
            longitud=lon,
            prioridad=random.choice(prioridades),
            estado=estado,
            pago_estado="pagado",
            cancelado_por=None,
            motivo_cancelacion=None,
            tiempo_asignacion_segundos=random.randint(30, 600),
            clasificacion_ia=clasificacion,
            resumen_ia=fake.sentence(nb_words=8),
            fecha_creacion=fecha_incidente,
            fecha_llegada_tecnico=fecha_incidente + timedelta(
                minutes=random.randint(20, 120)
            ),
        )
        db.add(incidente)
        incidentes.append(incidente)
    
    db.commit()
    logger.info(f"✅ Creados {len(incidentes)} incidentes finalizados")
    
    # ---------------------------------------------------------
    # 7.5 INCIDENTES BUSCANDO TALLER (Subasta para pruebas)
    # ---------------------------------------------------------
    logger.info("🚨 Creando INCIDENTES EN SUBASTA (Para pruebas)...")
    incidentes_subasta = []
    
    for inc_idx in range(2):
        fecha_incidente = hoy - timedelta(minutes=random.randint(5, 30))
        cliente = random.choice(clientes)
        vehiculos_cliente = db.query(Vehiculo).filter(Vehiculo.usuario_id == cliente.id).all()
        if not vehiculos_cliente: continue
        vehiculo = random.choice(vehiculos_cliente)
        
        clasificacion = random.choice(CLASIFICACIONES_INCIDENTES)
        zona = random.choice(ZONAS_SC)
        lat, lon = generar_coords_en_zona(zona)
        
        incidente = Incidente(
            vehiculo_id=vehiculo.id,
            usuario_id=cliente.id,
            descripcion=fake.sentence(nb_words=10),
            ubicacion=zona["nombre"],
            latitud=lat,
            longitud=lon,
            prioridad=random.choice(["alta", "media"]),
            estado=EstadoIncidente.BUSCANDO_TALLER,
            pago_estado="pendiente",
            clasificacion_ia=clasificacion,
            resumen_ia=fake.sentence(nb_words=8),
            fecha_creacion=fecha_incidente,
        )
        db.add(incidente)
        db.commit()
        db.refresh(incidente)
        incidentes_subasta.append(incidente)
        
        # Asignar a todos los talleres como sugeridos para que puedan enviar cotización
        for i, taller in enumerate(talleres):
            candidato = IncidenteAsignacionCandidato(
                incidente_id=incidente.id,
                taller_id=taller.id,
                orden=i+1,
                estado="sugerido",
                score_total=round(random.uniform(0.7, 0.99), 2),
                score_distancia=round(random.uniform(0.5, 0.99), 2),
                sugerencia_ia_monto=round(random.uniform(50.0, 200.0), 2),
                fecha_creacion=fecha_incidente,
            )
            db.add(candidato)
    
    db.commit()
    logger.info(f"✅ Creados {len(incidentes_subasta)} incidentes en subasta")

    # ---------------------------------------------------------
    # 7.6 INCIDENTES CANCELADOS CON PENALIDAD (feature de cancelación)
    # ---------------------------------------------------------
    logger.info("🚫 Creando INCIDENTES CANCELADOS con PENALIDAD...")
    # Debe coincidir con MONTO_PENALIDAD_CANCELACION del endpoint de incidentes.
    MONTO_PENALIDAD_CANCELACION = Decimal("20.00")
    motivos_cancelacion = [
        "Ya conseguí ayuda por mi cuenta.",
        "El problema se resolvió solo.",
        "La espera fue demasiado larga.",
        "Me equivoqué al reportar.",
    ]
    incidentes_cancelados = []
    pagos_penalidad = []
    for _ in range(5):
        cliente = random.choice(clientes)
        vehiculos_cliente = db.query(Vehiculo).filter(Vehiculo.usuario_id == cliente.id).all()
        if not vehiculos_cliente:
            continue
        vehiculo = random.choice(vehiculos_cliente)
        clasificacion = random.choice(CLASIFICACIONES_INCIDENTES)
        taller = elegir_taller_para_clasificacion(talleres, clasificacion)
        zona = taller.zona if hasattr(taller, "zona") else random.choice(ZONAS_SC)
        lat, lon = generar_coords_en_zona(zona)

        # El cliente canceló pasados más de 5 min desde la creación → aplica penalidad.
        fecha_incidente = hoy - timedelta(days=random.randint(0, dias_historial))
        incidente = Incidente(
            vehiculo_id=vehiculo.id,
            usuario_id=cliente.id,
            taller_id=taller.id,
            descripcion=fake.sentence(nb_words=10),
            ubicacion=zona["nombre"],
            latitud=lat,
            longitud=lon,
            prioridad=random.choice(prioridades),
            estado=EstadoIncidente.CANCELADO,
            pago_estado="pendiente",
            cancelado_por=CanceladoPor.CLIENTE,
            motivo_cancelacion=random.choice(motivos_cancelacion),
            clasificacion_ia=clasificacion,
            resumen_ia=fake.sentence(nb_words=8),
            fecha_creacion=fecha_incidente,
        )
        db.add(incidente)
        db.flush()  # obtener id para el pago de penalidad

        pago = Pago(
            incidente_id=incidente.id,
            usuario_id=incidente.usuario_id,
            taller_id=incidente.taller_id,
            monto=MONTO_PENALIDAD_CANCELACION,
            comision_plataforma=MONTO_PENALIDAD_CANCELACION * Decimal("0.10"),
            metodo_pago="penalidad",
            estado="pendiente",
            fecha=fecha_incidente + timedelta(minutes=random.randint(6, 20)),
        )
        db.add(pago)
        incidentes_cancelados.append(incidente)
        pagos_penalidad.append(pago)
    db.commit()
    logger.info(
        f"✅ Creados {len(incidentes_cancelados)} incidentes cancelados "
        f"con {len(pagos_penalidad)} pagos de penalidad"
    )

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
                estado="completado",
                fecha=incidente.fecha_creacion + timedelta(days=random.randint(1, 5))
            )
            db.add(pago)
            pagos.append(pago)
    
    db.commit()
    logger.info(f"✅ Creados {len(pagos)} pagos")

    # ---------------------------------------------------------
    # 8.5 CALIFICACIONES (para ~70% de incidentes finalizados)
    # ---------------------------------------------------------
    logger.info("⭐ Creando CALIFICACIONES...")
    calificaciones = []
    comentarios_positivos = [
        "Excelente servicio, muy rápido.",
        "El técnico fue muy amable y profesional.",
        "Quedé muy satisfecho, lo recomiendo.",
        "Buen trabajo, precio justo.",
        "Atendieron rápido y resolvieron el problema.",
    ]
    comentarios_neutros = [
        "Servicio correcto, sin quejas.",
        "Cumplieron con lo acordado.",
        "Normal, nada especial.",
    ]
    comentarios_negativos = [
        "Tardaron más de lo esperado.",
        "El precio me pareció alto.",
        "Tuve que llamar varias veces para que atendieran.",
    ]

    for incidente in incidentes:
        # Solo ~70% de los incidentes tienen calificación
        if random.random() > 0.70:
            continue
        if not incidente.taller_id:
            continue

        puntuacion = random.choices(
            [1, 2, 3, 4, 5],
            weights=[5, 10, 15, 35, 35],
        )[0]

        if puntuacion >= 4:
            comentario = random.choice(comentarios_positivos) if random.random() > 0.4 else None
        elif puntuacion == 3:
            comentario = random.choice(comentarios_neutros) if random.random() > 0.5 else None
        else:
            comentario = random.choice(comentarios_negativos) if random.random() > 0.3 else None

        calificacion = Calificacion(
            incidente_id=incidente.id,
            taller_id=incidente.taller_id,
            usuario_id=incidente.usuario_id,
            puntuacion=puntuacion,
            comentario=comentario,
            fecha_creacion=incidente.fecha_creacion + timedelta(hours=random.randint(1, 48)),
        )
        db.add(calificacion)
        calificaciones.append(calificacion)

    db.commit()
    logger.info(f"✅ Creadas {len(calificaciones)} calificaciones")

    # Recalcular promedios de talleres
    logger.info("📊 Actualizando promedios de calificación por taller...")
    from sqlalchemy import func as sql_func
    for taller in talleres:
        promedio = (
            db.query(sql_func.avg(Calificacion.puntuacion))
            .filter(Calificacion.taller_id == taller.id)
            .scalar()
        )
        if promedio is not None:
            taller.calificacion_promedio = round(float(promedio), 2)
        else:
            # Garantizar que todos los talleres tengan una calificacion inicial atractiva
            taller.calificacion_promedio = round(random.uniform(3.8, 5.0), 2)
    db.commit()
    logger.info("✅ Promedios actualizados")
    
    # ---------------------------------------------------------
    # 9. BITÁCORA (registros de actividades)
    # ---------------------------------------------------------
    logger.info("📝 Creando BITÁCORA...")
    bitacoras = []
    acciones = ["crear", "asignar_taller", "asignar_tecnico", "atender", "finalizar"]
    
    for _ in range(bitacoras_count):
        if not incidentes:
            break
        incidente = random.choice(incidentes)
        bitacora = Bitacora(
            usuario_id=incidente.tecnico_id or incidente.usuario_id,
            taller_id=incidente.taller_id,
            tabla="incidente",
            tabla_id=incidente.id,
            accion=random.choice(acciones),
            valor_anterior={"estado": EstadoIncidente.EN_ATENCION},
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
    
    for foto_idx in range(evidencias_count):
        if not incidentes:
            break
        incidente = random.choice(incidentes)
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
    
    for _ in range(notificaciones_count):
        if not incidentes:
            break
        incidente = random.choice(incidentes)
        notificacion = Notificacion(
            usuario_id=incidente.usuario_id,
            incidente_id=incidente.id,
            titulo="Incidente finalizado",
            mensaje=f"Tu incidente de {incidente.clasificacion_ia} fue finalizado.",
            tipo="incidente_finalizado",
            leido=random.choice([True, False]),
            fecha_envio=incidente.fecha_creacion + timedelta(hours=random.randint(1, 96))
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
    logger.info(f"⭐ Calificaciones: {db.query(Calificacion).count()}")
    logger.info(f"📝 Bitácora: {db.query(Bitacora).count()}")
    logger.info(f"📷 Evidencias: {db.query(Evidencia).count()}")
    logger.info(f"🔔 Notificaciones: {db.query(Notificacion).count()}")
    logger.info("="*70)
    logger.info(f"📊 Datos variables de {dias_historial} días de movimiento en Santa Cruz")
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
