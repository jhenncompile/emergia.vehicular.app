import logging
import unicodedata
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
from app.models.asignacion_inteligente import IncidenteAsignacionCandidato
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
from app.services.ranking_taller_service import RankingTallerService
from app.schemas.asignacion_inteligente import IncidenteAsignacionCandidatoOut

logger = logging.getLogger(__name__)

router = APIRouter()
UPLOADS_DIR = Path("uploads") / "incidentes"
AUDIO_UPLOADS_DIR = UPLOADS_DIR / "audio"
IMAGE_UPLOADS_DIR = UPLOADS_DIR / "imagenes"
PUBLIC_UPLOADS_BASE = "/uploads/incidentes"
ALLOWED_AUDIO_FORMATS = {
    "audio/mpeg",
    "audio/wav",
    "audio/x-wav",
    "audio/ogg",
    "audio/flac",
    "audio/mp4",
    "audio/m4a",
    "audio/x-m4a",
    "audio/aac",
}
ALLOWED_IMAGE_FORMATS = {"image/jpeg", "image/png", "image/webp"}

VISION_LABELS_ES = {
    "truck": "vehículo",
    "car": "vehículo",
    "bus": "vehículo",
    "motorcycle": "motocicleta",
    "bicycle": "bicicleta",
    "person": "persona",
    "traffic light": "semáforo",
    "stop sign": "señal de pare",
    "parking meter": "parquímetro",
    "bench": "banco",
    "fire hydrant": "hidrante",
}

ACCIONES_POR_CATEGORIA = {
    "Accidente / Colisión": "Evaluar seguridad, daños por impacto y posible necesidad de grúa.",
    "Pinchazo": "Enviar apoyo para cambio o reparación de llanta.",
    "Daño en Rueda o Rin": "Revisar llanta, rin, válvula y tren delantero antes de circular.",
    "Falla Eléctrica": "Revisar batería, alternador, fusibles y sistema de arranque.",
    "Revisión de Batería": "Revisar carga de batería, bornes y sistema de arranque.",
    "Alternador": "Revisar carga del alternador, correa y testigo de batería.",
    "Fuga de refrigerante": "Revisar radiador, mangueras, deposito y nivel de refrigerante.",
    "Fuga de Aceite": "Revisar nivel de aceite, cárter, retenes y empaques.",
    "Fuga de Combustible": "Evitar encender el vehículo y revisar fugas en líneas o tanque.",
    "Sobrecalentamiento": "Detener el vehículo y revisar temperatura, fugas y ventilación.",
    "Sistema de Frenos": "Priorizar atención por riesgo de seguridad y revisar frenos.",
    "Falla de Motor": "Enviar mecánico para diagnóstico de motor y sistema de encendido.",
    "Motor no arranca": "Revisar batería, arranque, combustible, chispa y sensores básicos.",
    "Bomba de Gasolina": "Revisar presión de combustible, bomba, relé y filtro.",
    "Transmisiones": "Revisar caja, embrague y transmisión antes de mover el vehículo.",
    "Falla de Embrague": "Revisar embrague, cable/bomba, pedal y cambios.",
    "Dirección": "Revisar dirección, terminales, bomba hidráulica/eléctrica y volante.",
    "Ruido en Suspensión": "Revisar suspensión, dirección, tren delantero y daños por impacto.",
    "Alineación y Balanceo": "Revisar alineación, balanceo, vibraciones y desgaste irregular.",
    "Aire Acondicionado": "Derivar a revisión de climatización si el vehículo puede circular.",
    "Llave o Inmovilizador": "Revisar llave, chip, inmovilizador, control y antena lectora.",
    "Cerrajería Vehicular": "Enviar apoyo para apertura segura o recuperación de llave.",
    "Escape / Catalizador": "Revisar escape, catalizador, sensores y ruidos anormales.",
    "Cristales / Parabrisas": "Revisar daño en vidrio y seguridad para circular.",
    "Carrocería": "Revisar daños visibles de carrocería, parachoques o chapa.",
    "Mantenimiento Preventivo": "Programar revisión general y mantenimiento preventivo.",
    "Cambio de Aceite": "Revisar aceite, filtro y kilometraje de mantenimiento.",
    "Filtro de Aire": "Revisar filtro de aire, admisión y pérdida de potencia.",
    "Correa de Distribución": "Revisar correa/banda y evitar encender si hay riesgo de ruptura.",
    "Bujías": "Revisar bujías, bobinas, cables y chispa.",
    "Otro / No clasificado": "Revisar manualmente el caso y asignar taller según evidencia.",
}

CATEGORIA_REGLAS = [
    (
        "Pinchazo",
        [
            "pinch",
            "pinchazo",
            "llanta",
            "neumatico",
            "rueda",
            "goma",
            "cubierta",
            "desinflada",
            "sin aire",
            "revento",
            "reventada",
            "se bajo",
            "se vacio",
            "cambio de llanta",
            "auxilio de llanta",
        ],
    ),
    (
        "Daño en Rueda o Rin",
        [
            "rin",
            "aro",
            "valvula",
            "bache",
            "hueco",
            "cuneta",
            "bordillo",
            "golpe en la rueda",
            "doblo la rueda",
            "rueda torcida",
        ],
    ),
    (
        "Sistema de Frenos",
        [
            "freno",
            "frenos",
            "pastilla",
            "disco",
            "tambor",
            "pedal de freno",
            "liquido de freno",
            "abs",
            "no frena",
            "se fue el freno",
        ],
    ),
    (
        "Accidente / Colisión",
        [
            "accidente",
            "choque",
            "choco",
            "colision",
            "impacto fuerte",
            "volco",
            "vuelco",
            "atropello",
            "siniestro",
            "herido",
            "sangre",
            "atrapado",
            "parachoque roto",
        ],
    ),
    (
        "Sobrecalentamiento",
        [
            "calienta",
            "recalienta",
            "sobrecal",
            "temperatura",
            "humo",
            "vapor",
            "aguja de temperatura",
            "ventilador",
        ],
    ),
    (
        "Fuga de refrigerante",
        [
            "refrigerante",
            "anticongelante",
            "radiador",
            "manguera",
            "agua verde",
            "agua roja",
            "pierde agua",
            "bota agua",
        ],
    ),
    (
        "Fuga de Aceite",
        [
            "fuga de aceite",
            "pierde aceite",
            "bota aceite",
            "gotea aceite",
            "mancha de aceite",
            "carter",
            "reten",
        ],
    ),
    (
        "Fuga de Combustible",
        [
            "fuga de gasolina",
            "pierde gasolina",
            "olor a gasolina",
            "combustible derramado",
            "tanque",
            "manguera de gasolina",
        ],
    ),
    (
        "Revisión de Batería",
        [
            "bateria",
            "bateria descargada",
            "sin bateria",
            "pasar corriente",
            "bornes",
            "no da contacto",
            "luces debiles",
        ],
    ),
    (
        "Alternador",
        [
            "alternador",
            "no carga",
            "testigo de bateria",
            "se descarga andando",
            "correa del alternador",
        ],
    ),
    (
        "Falla Eléctrica",
        [
            "electrico",
            "electrica",
            "fusible",
            "corto",
            "cable",
            "tablero",
            "sensor",
            "luces",
            "alarma",
            "vidrios electricos",
        ],
    ),
    (
        "Motor no arranca",
        [
            "no arranca",
            "no prende",
            "no enciende",
            "no da arranque",
            "no gira el motor",
            "starter",
            "arranque",
        ],
    ),
    (
        "Falla de Motor",
        [
            "motor",
            "se apago",
            "se paro",
            "se detuvo",
            "perdio fuerza",
            "tiembla",
            "jalonea",
            "check engine",
            "aceite",
            "ruido de motor",
            "dejo de funcionar",
        ],
    ),
    (
        "Bomba de Gasolina",
        [
            "bomba de gasolina",
            "bomba de combustible",
            "no llega gasolina",
            "no pasa gasolina",
            "filtro de gasolina",
            "presion de combustible",
        ],
    ),
    (
        "Transmisiones",
        [
            "transmision",
            "caja",
            "cambio",
            "marcha",
            "no entra cambio",
            "no entran los cambios",
            "patina la caja",
            "aceite de caja",
        ],
    ),
    (
        "Falla de Embrague",
        [
            "embrague",
            "clutch",
            "pedal de embrague",
            "no embraga",
            "disco de embrague",
            "bomba de embrague",
        ],
    ),
    (
        "Dirección",
        [
            "direccion",
            "volante duro",
            "no gira",
            "hidraulica",
            "direccion asistida",
            "cremallera",
        ],
    ),
    (
        "Ruido en Suspensión",
        [
            "suspension",
            "amortiguador",
            "tren delantero",
            "ruido abajo",
            "golpe abajo",
            "rotula",
            "terminal",
            "bujes",
        ],
    ),
    (
        "Alineación y Balanceo",
        [
            "alineacion",
            "balanceo",
            "vibra",
            "vibracion",
            "se va a un lado",
            "desgaste irregular",
            "tiembla a velocidad",
        ],
    ),
    (
        "Llave o Inmovilizador",
        [
            "llave",
            "chip",
            "inmovilizador",
            "control",
            "no reconoce la llave",
            "anti robo",
        ],
    ),
    (
        "Cerrajería Vehicular",
        [
            "llaves adentro",
            "puerta cerrada",
            "no abre",
            "cerradura",
            "apertura",
            "perdi la llave",
        ],
    ),
    (
        "Escape / Catalizador",
        [
            "escape",
            "catalizador",
            "humo negro",
            "humo azul",
            "olor a escape",
            "ruido de escape",
        ],
    ),
    (
        "Aire Acondicionado",
        [
            "aire acondicionado",
            "climatizador",
            "compresor",
            "no enfria",
            "gas del aire",
        ],
    ),
    (
        "Cristales / Parabrisas",
        [
            "parabrisas",
            "vidrio",
            "cristal",
            "ventana rota",
            "luneta",
        ],
    ),
    (
        "Carrocería",
        [
            "abolladura",
            "chapa",
            "parachoque",
            "guardabarro",
            "rayon",
            "puerta golpeada",
        ],
    ),
    (
        "Cambio de Aceite",
        [
            "cambio de aceite",
            "aceite vencido",
            "filtro de aceite",
            "kilometraje",
        ],
    ),
    (
        "Filtro de Aire",
        [
            "filtro de aire",
            "admision",
            "no respira",
            "pierde potencia",
        ],
    ),
    (
        "Correa de Distribución",
        [
            "correa de distribucion",
            "banda de distribucion",
            "cadena de distribucion",
            "correa rota",
        ],
    ),
    (
        "Bujías",
        [
            "bujia",
            "bujias",
            "chispa",
            "bobina",
            "cables de bujia",
        ],
    ),
    (
        "Mantenimiento Preventivo",
        [
            "mantenimiento",
            "revision general",
            "servicio preventivo",
            "chequeo",
        ],
    ),
]


def _transcribir_audio_si_es_posible(
    audio_data: bytes,
    content_type: str | None,
) -> tuple[str | None, str | None]:
    try:
        transcripcion = AIService().transcribe_audio(audio_data, content_type)
        return transcripcion, None
    except (AIServiceError, HuggingFaceAPIError) as e:
        logger.warning("No se pudo transcribir audio del incidente: %s", str(e))
        return None, str(e)


def _analizar_imagen_si_es_posible(
    imagen_data: bytes,
    content_type: str | None,
) -> tuple[list, str | None]:
    try:
        detecciones = AIService().detect_objects_in_image(
            imagen_data,
            content_type,
        )
        return detecciones, None
    except (AIServiceError, HuggingFaceAPIError) as e:
        logger.warning("No se pudo analizar imagen del incidente: %s", str(e))
        return [], str(e)


def _extension_archivo(nombre: str | None, extension_default: str) -> str:
    extension = Path(nombre or "").suffix.lower()
    return extension if extension else extension_default


def _guardar_archivo(
    *,
    carpeta: Path,
    subcarpeta_publica: str,
    data: bytes,
    nombre_original: str | None,
    extension_default: str,
) -> str:
    carpeta.mkdir(parents=True, exist_ok=True)
    extension = _extension_archivo(nombre_original, extension_default)
    nombre_archivo = f"{uuid4().hex}{extension}"
    ruta = carpeta / nombre_archivo
    ruta.write_bytes(data)
    return f"{PUBLIC_UPLOADS_BASE}/{subcarpeta_publica}/{nombre_archivo}"


def _labels_detecciones(detecciones: list) -> list[str]:
    labels = []
    for item in detecciones:
        if isinstance(item, dict) and item.get("label"):
            label = str(item["label"]).strip().lower()
            label = VISION_LABELS_ES.get(label, label)
            if label and label not in labels:
                labels.append(label)
    return labels


def _normalizar_texto(texto: str) -> str:
    texto = unicodedata.normalize("NFD", texto.lower())
    return "".join(char for char in texto if unicodedata.category(char) != "Mn")


def _contiene_alguna(texto_normalizado: str, palabras: list[str]) -> bool:
    return any(_normalizar_texto(palabra) in texto_normalizado for palabra in palabras)


def _sumar_puntaje(
    puntajes: dict[str, int],
    motivos: dict[str, list[str]],
    categoria: str,
    puntaje: int,
    motivo: str,
) -> None:
    puntajes[categoria] = puntajes.get(categoria, 0) + puntaje
    motivos.setdefault(categoria, [])
    if motivo not in motivos[categoria]:
        motivos[categoria].append(motivo)


def _peso_palabra(palabra: str) -> int:
    return 3 if " " in palabra.strip() else 1


def _patron_pincha_por_movimiento(texto_normalizado: str) -> bool:
    golpe_o_derrape = _contiene_alguna(
        texto_normalizado,
        ["derrape", "derrapo", "golpe", "bache", "hueco", "cuneta", "bordillo"],
    )
    motor_funciona = _contiene_alguna(
        texto_normalizado,
        [
            "enciende",
            "arranca",
            "funciona",
            "esta funcionando",
            "prende",
            "motor funciona",
        ],
    )
    no_puede_avanzar = _contiene_alguna(
        texto_normalizado,
        [
            "no avanza",
            "no podemos avanzar",
            "no puede avanzar",
            "no se mueve",
            "no puedo mover",
            "nos tuvimos que apartar",
        ],
    )
    senales_accidente_fuerte = _contiene_alguna(
        texto_normalizado,
        [
            "herido",
            "sangre",
            "volco",
            "vuelco",
            "atropello",
            "choque fuerte",
            "colision fuerte",
        ],
    )
    return golpe_o_derrape and motor_funciona and no_puede_avanzar and not senales_accidente_fuerte


def _analizar_categoria(texto: str) -> dict[str, str | list[str]]:
    texto_normalizado = _normalizar_texto(texto)
    puntajes: dict[str, int] = {}
    motivos: dict[str, list[str]] = {}

    for categoria, palabras in CATEGORIA_REGLAS:
        coincidencias = [
            palabra
            for palabra in palabras
            if _normalizar_texto(palabra) in texto_normalizado
        ]
        if not coincidencias:
            continue

        puntaje = sum(_peso_palabra(palabra) for palabra in coincidencias)
        _sumar_puntaje(
            puntajes,
            motivos,
            categoria,
            puntaje,
            "coincidencias: " + ", ".join(coincidencias[:5]),
        )

    if _patron_pincha_por_movimiento(texto_normalizado):
        _sumar_puntaje(
            puntajes,
            motivos,
            "Pinchazo",
            6,
            "patrón: el vehículo enciende/funciona, pero no puede avanzar tras golpe o derrape",
        )
        _sumar_puntaje(
            puntajes,
            motivos,
            "Daño en Rueda o Rin",
            3,
            "patrón compatible con daño en rueda/rin",
        )

    if not puntajes:
        return {
            "categoria": "Otro / No clasificado",
            "confianza": "Baja",
            "motivos_categoria": ["no se encontraron señales suficientes"],
            "alternativas": [],
        }

    ordenadas = sorted(puntajes.items(), key=lambda item: item[1], reverse=True)
    categoria, puntaje = ordenadas[0]
    segundo_puntaje = ordenadas[1][1] if len(ordenadas) > 1 else 0
    diferencia = puntaje - segundo_puntaje
    alternativas = [item[0] for item in ordenadas[1:4] if item[1] >= 2]

    if (
        categoria == "Pinchazo"
        and _patron_pincha_por_movimiento(texto_normalizado)
        and not _contiene_alguna(texto_normalizado, ["llanta", "rueda", "pinch"])
    ):
        confianza = "Media"
    elif puntaje >= 5 and diferencia >= 2:
        confianza = "Alta"
    elif puntaje >= 2:
        confianza = "Media"
    else:
        confianza = "Baja"

    return {
        "categoria": categoria,
        "confianza": confianza,
        "motivos_categoria": motivos.get(categoria, []),
        "alternativas": alternativas,
    }


def _clasificar_por_texto(texto: str) -> str:
    return str(_analizar_categoria(texto)["categoria"])


def _prioridad_por_texto(texto: str) -> str:
    return _analizar_criticidad(texto)["prioridad"]


def _analizar_criticidad(texto: str) -> dict[str, str | list[str]]:
    texto_normalizado = _normalizar_texto(texto)
    criticas = [
        "herido",
        "herida",
        "sangre",
        "atrapado",
        "atrapada",
        "incendio",
        "fuego",
        "explosion",
        "volco",
        "vuelco",
        "atropello",
    ]
    altas = [
        "choque",
        "choco",
        "colision",
        "impacto",
        "golpe",
        "derrape",
        "derrapo",
        "accidente",
        "humo",
        "freno",
        "frenos",
        "no avanza",
        "no podemos avanzar",
        "varado",
        "inmovilizado",
        "fire",
        "smoke",
        "person",
        "persona",
        "accident",
    ]
    medias = [
        "motor",
        "arranca",
        "enciende",
        "apaga",
        "bateria",
        "llanta",
        "pinch",
        "radiador",
        "fuga",
    ]

    if _contiene_alguna(texto_normalizado, criticas):
        return {
            "criticidad": "Crítica",
            "prioridad": "alta",
            "motivo_criticidad": "hay indicios de riesgo inmediato para personas o incendio",
        }
    if _contiene_alguna(texto_normalizado, altas):
        return {
            "criticidad": "Alta",
            "prioridad": "alta",
            "motivo_criticidad": "hay indicios de accidente o vehículo inmovilizado",
        }
    if _contiene_alguna(texto_normalizado, medias):
        return {
            "criticidad": "Media",
            "prioridad": "media",
            "motivo_criticidad": "hay una falla mecánica o eléctrica reportada",
        }
    return {
        "criticidad": "Media",
        "prioridad": "media",
        "motivo_criticidad": "información insuficiente para elevar la criticidad",
    }


def _detectar_motivos(texto: str, labels_imagen: list[str]) -> list[str]:
    texto_normalizado = _normalizar_texto(texto)
    motivos = []
    reglas = [
        ("golpe o impacto", ["golpe", "impacto", "choque", "choco", "colision"]),
        ("derrape", ["derrape", "derrapo"]),
        (
            "vehículo no puede avanzar",
            ["no avanza", "no podemos avanzar", "varado", "inmovilizado"],
        ),
        (
            "vehículo enciende pero presenta falla",
            ["enciende", "arranca", "dejo de funcionar", "no funciona"],
        ),
        ("posible problema de frenos", ["freno", "frenos"]),
        ("posible pinchazo o daño en llanta", ["pinch", "llanta", "neumatico", "rueda"]),
        ("posible sobrecalentamiento", ["humo", "calienta", "temperatura", "sobrecal"]),
    ]
    for motivo, palabras in reglas:
        if _contiene_alguna(texto_normalizado, palabras):
            motivos.append(motivo)

    if _patron_pincha_por_movimiento(texto_normalizado):
        motivos.insert(
            0,
            "patrón compatible con pinchazo o daño de rueda",
        )

    if labels_imagen:
        motivos.append("evidencia visual: " + ", ".join(labels_imagen[:4]))

    return motivos[:6]


def _resumen_situacion(categoria: str, texto: str) -> str:
    texto_normalizado = _normalizar_texto(texto)
    no_avanza = _contiene_alguna(
        texto_normalizado,
        ["no avanza", "no podemos avanzar", "varado", "inmovilizado"],
    )
    enciende = _contiene_alguna(texto_normalizado, ["enciende", "arranca"])
    golpe = _contiene_alguna(
        texto_normalizado,
        ["golpe", "impacto", "choque", "choco", "colision", "derrape", "derrapo"],
    )

    if categoria == "Pinchazo" and _patron_pincha_por_movimiento(texto_normalizado):
        return (
            "El relato sugiere un posible pinchazo o daño en rueda: el vehículo "
            "enciende/funciona, pero no puede avanzar tras un golpe o derrape."
        )
    if categoria == "Accidente / Colisión":
        if golpe and no_avanza and enciende:
            return (
                "El vehículo sufrió un golpe o derrape; enciende, pero no puede avanzar."
            )
        if golpe and no_avanza:
            return "El vehículo tuvo un golpe o derrape y quedó sin poder avanzar."
        return "Se reporta un posible accidente o impacto vehicular."
    if categoria == "Falla de Motor" and no_avanza:
        return "El vehículo presenta una falla mecánica y no puede continuar circulando."
    if categoria == "Pinchazo":
        return "Se reporta un problema relacionado con llanta o rueda."
    if categoria == "Sistema de Frenos":
        return "Se reporta un posible problema en el sistema de frenos."
    if categoria == "Falla Eléctrica":
        return "Se reporta una posible falla eléctrica o de batería."

    resumenes = {
        "Daño en Rueda o Rin": "Se reportan señales compatibles con daño en rueda, rin o tren delantero.",
        "Revisión de Batería": "Se reportan señales compatibles con batería descargada o bajo voltaje.",
        "Alternador": "Se reportan señales compatibles con problema de carga del alternador.",
        "Fuga de refrigerante": "Se reporta posible pérdida de refrigerante o problema de radiador.",
        "Fuga de Aceite": "Se reporta posible pérdida de aceite o fuga en el motor.",
        "Fuga de Combustible": "Se reporta posible fuga de combustible; debe atenderse con precaución.",
        "Sobrecalentamiento": "Se reportan señales de temperatura elevada o sobrecalentamiento.",
        "Motor no arranca": "El vehículo no arranca o no logra encender correctamente.",
        "Bomba de Gasolina": "Se reportan señales compatibles con falta de suministro de combustible.",
        "Transmisiones": "Se reportan señales de problema en caja, cambios o transmisión.",
        "Falla de Embrague": "Se reportan señales compatibles con falla de embrague.",
        "Dirección": "Se reportan señales de problema en dirección o volante.",
        "Ruido en Suspensión": "Se reportan ruidos o golpes compatibles con suspensión o tren delantero.",
        "Alineación y Balanceo": "Se reportan vibraciones o desvío de dirección al circular.",
        "Llave o Inmovilizador": "Se reporta posible problema con llave, chip o inmovilizador.",
        "Cerrajería Vehicular": "Se requiere apoyo de apertura o cerrajería vehicular.",
        "Escape / Catalizador": "Se reportan señales de problema en escape, catalizador o emisiones.",
        "Aire Acondicionado": "Se reporta problema de climatización del vehículo.",
        "Cristales / Parabrisas": "Se reporta daño en cristal, vidrio o parabrisas.",
        "Carrocería": "Se reporta daño visible de carrocería o partes exteriores.",
        "Mantenimiento Preventivo": "Se solicita revisión general o mantenimiento preventivo.",
        "Cambio de Aceite": "Se solicita o requiere revisión de aceite y filtro.",
        "Filtro de Aire": "Se reporta posible problema de admisión o filtro de aire.",
        "Correa de Distribución": "Se reportan señales relacionadas con correa o cadena de distribución.",
        "Bujías": "Se reportan señales compatibles con falla de chispa, bujías o bobinas.",
    }
    return resumenes.get(
        categoria,
        "Se recibió evidencia del incidente y requiere revisión del taller.",
    )


def _resumen_imagen(labels_imagen: list[str]) -> str:
    if not labels_imagen:
        return ""

    vehiculos = {"vehículo", "motocicleta", "bicicleta"}
    solo_vehiculos = all(label in vehiculos for label in labels_imagen)
    if solo_vehiculos:
        return "Imagen: vehículo detectado."

    return "Imagen: objetos detectados: " + ", ".join(labels_imagen[:8]) + "."


def _construir_resumen_ia(
    *,
    descripcion: str,
    transcripcion: str | None,
    labels_imagen: list[str],
    categoria: str,
    confianza_categoria: str,
    motivos_categoria: list[str],
    alternativas: list[str],
    criticidad: str,
    motivo_criticidad: str,
    error_audio_ia: str | None,
    error_imagen_ia: str | None,
) -> str:
    texto_base = " ".join(parte for parte in [descripcion, transcripcion or ""] if parte)
    motivos = _detectar_motivos(
        " ".join(parte for parte in [texto_base, " ".join(labels_imagen)] if parte),
        labels_imagen,
    )
    accion = ACCIONES_POR_CATEGORIA.get(
        categoria,
        ACCIONES_POR_CATEGORIA["Otro / No clasificado"],
    )

    partes = [
        f"Resumen: {_resumen_situacion(categoria, texto_base)}",
        f"Categoría sugerida: {categoria} (confianza {confianza_categoria.lower()}).",
        f"Criticidad: {criticidad} ({motivo_criticidad}).",
    ]

    if motivos_categoria:
        partes.append(
            "Señales usadas para clasificar: "
            + "; ".join(motivos_categoria[:4])
            + "."
        )

    if motivos:
        partes.append("Motivos detectados: " + "; ".join(motivos) + ".")

    resumen_imagen = _resumen_imagen(labels_imagen)
    if resumen_imagen:
        partes.append(resumen_imagen)
        if set(labels_imagen).issubset({"vehículo", "motocicleta", "bicicleta"}):
            partes.append(
                "Nota visual: la imagen confirma presencia de vehículo, pero no confirma el tipo de falla."
            )

    if alternativas:
        partes.append("También revisar: " + ", ".join(alternativas[:3]) + ".")

    partes.append(f"Acción sugerida: {accion}")

    if error_audio_ia:
        partes.append(f"Nota audio: {error_audio_ia}")
    if error_imagen_ia:
        partes.append(f"Nota imagen: {error_imagen_ia}")

    return "\n".join(partes)


async def _crear_incidente_multimedia(
    *,
    db: Session,
    current_user,
    vehiculo_id: int,
    descripcion: str,
    ubicacion: str,
    latitud: float,
    longitud: float,
    audio: UploadFile | None = None,
    imagen: UploadFile | None = None,
) -> Incidente:
    descripcion = descripcion.strip()
    if not descripcion and audio is None and imagen is None:
        raise HTTPException(
            status_code=400,
            detail="Envia una descripcion, un audio o una imagen.",
        )

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
    error_audio_ia = None
    detecciones_imagen = []
    error_imagen_ia = None
    url_audio = None
    url_imagen = None

    if audio is not None:
        if audio.content_type not in ALLOWED_AUDIO_FORMATS:
            raise HTTPException(
                status_code=400,
                detail="Formato de audio no soportado.",
            )

        audio_data = await audio.read()
        if not audio_data:
            raise HTTPException(status_code=400, detail="El audio esta vacio.")

        url_audio = _guardar_archivo(
            carpeta=AUDIO_UPLOADS_DIR,
            subcarpeta_publica="audio",
            data=audio_data,
            nombre_original=audio.filename,
            extension_default=".wav",
        )
        transcripcion, error_audio_ia = _transcribir_audio_si_es_posible(
            audio_data,
            audio.content_type,
        )

    if imagen is not None:
        if imagen.content_type not in ALLOWED_IMAGE_FORMATS:
            raise HTTPException(
                status_code=400,
                detail="Formato de imagen no soportado.",
            )

        imagen_data = await imagen.read()
        if not imagen_data:
            raise HTTPException(status_code=400, detail="La imagen esta vacia.")

        url_imagen = _guardar_archivo(
            carpeta=IMAGE_UPLOADS_DIR,
            subcarpeta_publica="imagenes",
            data=imagen_data,
            nombre_original=imagen.filename,
            extension_default=".jpg",
        )
        detecciones_imagen, error_imagen_ia = _analizar_imagen_si_es_posible(
            imagen_data,
            imagen.content_type,
        )

    labels_imagen = _labels_detecciones(detecciones_imagen)
    texto_imagen = " ".join(labels_imagen)
    texto_para_ia = " ".join(
        parte for parte in [descripcion, transcripcion, texto_imagen] if parte
    )
    analisis_categoria = _analizar_categoria(texto_para_ia)
    clasificacion = str(analisis_categoria["categoria"])
    criticidad = _analizar_criticidad(texto_para_ia)
    resumen = _construir_resumen_ia(
        descripcion=descripcion,
        transcripcion=transcripcion,
        labels_imagen=labels_imagen,
        categoria=clasificacion,
        confianza_categoria=str(analisis_categoria["confianza"]),
        motivos_categoria=list(analisis_categoria["motivos_categoria"]),
        alternativas=list(analisis_categoria["alternativas"]),
        criticidad=str(criticidad["criticidad"]),
        motivo_criticidad=str(criticidad["motivo_criticidad"]),
        error_audio_ia=error_audio_ia,
        error_imagen_ia=error_imagen_ia,
    )

    obj_in = IncidenteCreate(
        usuario_id=current_user.id,
        vehiculo_id=vehiculo_id,
        descripcion=descripcion,
        ubicacion=ubicacion,
        latitud=latitud,
        longitud=longitud,
        prioridad=str(criticidad["prioridad"]),
        estado="pendiente",
        pago_estado="pendiente",
        telefono_cliente=current_user.telefono or "No disponible",
        transcripcion_audio=transcripcion,
        clasificacion_ia=clasificacion,
        resumen_ia=resumen,
    )
    incidente = incidente_crud.create(db, obj_in=obj_in, usuario_id=current_user.id)

    if url_audio is not None:
        evidencia_crud.create(
            db,
            obj_in=EvidenciaCreate(
                incidente_id=incidente.id,
                tipo_archivo="audio",
                url_archivo=url_audio,
            ),
            usuario_id=current_user.id,
        )

    if url_imagen is not None:
        evidencia_crud.create(
            db,
            obj_in=EvidenciaCreate(
                incidente_id=incidente.id,
                tipo_archivo="imagen",
                url_archivo=url_imagen,
            ),
            usuario_id=current_user.id,
        )

    try:
        RankingTallerService(db).generar_y_ofrecer(incidente)
        db.refresh(incidente)
    except Exception as exc:
        db.rollback()
        logger.exception(
            "No se pudo generar ranking automatico para incidente %s: %s",
            incidente.id,
            exc,
        )
        incidente = incidente_crud.get(db, id=incidente.id)

    return incidente

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
    return await _crear_incidente_multimedia(
        db=db,
        current_user=current_user,
        vehiculo_id=vehiculo_id,
        descripcion=descripcion,
        ubicacion=ubicacion,
        latitud=latitud,
        longitud=longitud,
        audio=audio,
    )


@router.post("/reportar", response_model=IncidenteSchema)
async def crear_incidente_con_evidencias(
    *,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_cliente),
    vehiculo_id: int = Form(...),
    descripcion: str = Form(""),
    ubicacion: str = Form("Ubicacion seleccionada en mapa"),
    latitud: float = Form(...),
    longitud: float = Form(...),
    audio: UploadFile | None = File(None),
    imagen: UploadFile | None = File(None),
):
    """Crea un incidente desde movil con audio/imagen opcionales como evidencias."""
    return await _crear_incidente_multimedia(
        db=db,
        current_user=current_user,
        vehiculo_id=vehiculo_id,
        descripcion=descripcion,
        ubicacion=ubicacion,
        latitud=latitud,
        longitud=longitud,
        audio=audio,
        imagen=imagen,
    )

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

    incidentes_query = db.query(Incidente).filter(
        Incidente.estado == "pendiente"
    ).options(joinedload(Incidente.taller), joinedload(Incidente.vehiculo))

    if current_user.taller_id:
        candidatos_ofrecidos = db.query(
            IncidenteAsignacionCandidato.incidente_id
        ).filter(
            IncidenteAsignacionCandidato.taller_id == current_user.taller_id,
            IncidenteAsignacionCandidato.estado == "ofrecido",
        ).all()
        ofrecidos_ids = [item[0] for item in candidatos_ofrecidos]
        if ofrecidos_ids:
            incidentes_query = incidentes_query.filter(Incidente.id.in_(ofrecidos_ids))
        else:
            incidentes_con_ranking = db.query(
                IncidenteAsignacionCandidato.incidente_id
            ).distinct()
            incidentes_query = incidentes_query.filter(
                ~Incidente.id.in_(incidentes_con_ranking)
            )

    incidentes = incidentes_query.all()

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


@router.post(
    "/{id}/generar-ranking",
    response_model=List[IncidenteAsignacionCandidatoOut],
)
def generar_ranking_incidente(
    *,
    db: Session = Depends(deps.get_db),
    id: int,
    current_user = Depends(deps.get_current_active_user),
):
    """Genera o regenera la cola ordenada de talleres candidatos."""
    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")

    if current_user.rol_id == 2 and incidente_db.usuario_id != current_user.id:
        raise HTTPException(status_code=403, detail="No puedes generar ranking para este incidente.")

    return RankingTallerService(db).generar_y_ofrecer(incidente_db)


@router.get(
    "/{id}/candidatos",
    response_model=List[IncidenteAsignacionCandidatoOut],
)
def listar_candidatos_incidente(
    *,
    db: Session = Depends(deps.get_db),
    id: int,
    current_user = Depends(deps.get_current_active_user),
):
    """Lista los talleres candidatos ordenados por relevancia."""
    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")

    if current_user.rol_id == 2 and incidente_db.usuario_id != current_user.id:
        raise HTTPException(status_code=403, detail="No puedes ver este ranking.")

    return RankingTallerService(db).obtener_candidatos(id)


@router.post(
    "/{id}/ofrecer-siguiente",
    response_model=Optional[IncidenteAsignacionCandidatoOut],
)
def ofrecer_siguiente_taller(
    *,
    db: Session = Depends(deps.get_db),
    id: int,
    current_user = Depends(deps.get_current_active_user),
):
    """Avanza manualmente al siguiente taller candidato si no hay oferta vigente."""
    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")

    if current_user.rol_id == 2 and incidente_db.usuario_id != current_user.id:
        raise HTTPException(status_code=403, detail="No puedes modificar este ranking.")

    return RankingTallerService(db).ofrecer_siguiente(incidente_db)

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
    if not current_user.taller_id:
        raise HTTPException(status_code=400, detail="El usuario no pertenece a un taller")

    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")
    
    if incidente_db.taller_id:
        raise HTTPException(status_code=400, detail="Este incidente ya fue tomado por otro taller")

    ranking_service = RankingTallerService(db)
    if ranking_service.tiene_candidatos(id):
        candidato = ranking_service.obtener_candidato_taller(id, current_user.taller_id)
        if not candidato or candidato.estado != "ofrecido":
            raise HTTPException(
                status_code=403,
                detail="Este incidente no esta ofrecido a tu taller en este momento.",
            )

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

    if ranking_service.tiene_candidatos(id):
        ranking_service.marcar_aceptado(id, current_user.taller_id)
    
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
    if not current_user.taller_id:
        raise HTTPException(status_code=400, detail="El usuario no pertenece a un taller")

    incidente_db = incidente_crud.get(db, id=id)
    if not incidente_db:
        raise HTTPException(status_code=404, detail="Incidente no encontrado")

    ranking_service = RankingTallerService(db)
    if ranking_service.tiene_candidatos(id):
        candidato = ranking_service.obtener_candidato_taller(id, current_user.taller_id)
        if not candidato or candidato.estado not in ["ofrecido", "pendiente"]:
            raise HTTPException(
                status_code=403,
                detail="Este incidente no esta disponible para tu taller.",
            )
    
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

    if ranking_service.tiene_candidatos(id):
        ranking_service.rechazar_y_ofrecer_siguiente(
            incidente=incidente_db,
            taller_id=current_user.taller_id,
            motivo=motivo,
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
