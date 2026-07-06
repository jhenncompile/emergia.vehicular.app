import logging
import unicodedata
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session, joinedload

from app.crud.crud_incidente import incidente_crud
from app.core.estados import EstadoIncidente
from app.models.asignacion_inteligente import (
    CategoriaEspecialidad,
    CategoriaIncidente,
    IncidenteAsignacionCandidato,
)
from app.models.incidente import Incidente
from app.models.taller import Taller
from app.models.usuario import Especialidad, Usuario
from app.services.notificacion_service import NotificacionService

logger = logging.getLogger(__name__)


MAPEO_CATEGORIA_ESPECIALIDADES = {
    "Accidente / Colisión": [("Mecánica General", 1.0, True)],
    "Pinchazo": [("Llantería", 1.0, True)],
    "Daño en Rueda o Rin": [
        ("Llantería", 0.8, True),
        ("Mecánica General", 0.4, False),
    ],
    "Falla Eléctrica": [("Electricidad Automotriz", 1.0, True)],
    "Revisión de Batería": [
        ("Electricidad Automotriz", 1.0, True),
        ("Mecánica General", 0.2, False),
    ],
    "Alternador": [
        ("Electricidad Automotriz", 0.8, True),
        ("Mecánica General", 0.4, False),
    ],
    "Fuga de refrigerante": [
        ("Refrigeración", 0.8, True),
        ("Mecánica General", 0.6, False),
    ],
    "Fuga de Aceite": [("Mecánica General", 1.0, True)],
    "Fuga de Combustible": [("Mecánica General", 1.0, True)],
    "Sobrecalentamiento": [
        ("Refrigeración", 0.8, True),
        ("Mecánica General", 0.6, False),
    ],
    "Sistema de Frenos": [("Mecánica General", 1.0, True)],
    "Falla de Motor": [("Mecánica General", 1.0, True)],
    "Motor no arranca": [
        ("Mecánica General", 0.7, False),
        ("Electricidad Automotriz", 0.6, False),
    ],
    "Bomba de Gasolina": [
        ("Mecánica General", 0.8, True),
        ("Electricidad Automotriz", 0.3, False),
    ],
    "Transmisiones": [("Transmisiones", 1.0, True)],
    "Falla de Embrague": [
        ("Transmisiones", 0.7, True),
        ("Mecánica General", 0.5, False),
    ],
    "Dirección": [("Mecánica General", 1.0, True)],
    "Ruido en Suspensión": [("Mecánica General", 1.0, True)],
    "Alineación y Balanceo": [
        ("Llantería", 0.8, True),
        ("Mecánica General", 0.4, False),
    ],
    "Aire Acondicionado": [
        ("Refrigeración", 1.0, True),
        ("Electricidad Automotriz", 0.3, False),
    ],
    "Llave o Inmovilizador": [("Electricidad Automotriz", 1.0, True)],
    "Cerrajería Vehicular": [
        ("Electricidad Automotriz", 0.4, False),
        ("Mecánica General", 0.3, False),
    ],
    "Escape / Catalizador": [("Mecánica General", 1.0, True)],
    "Cristales / Parabrisas": [("Mecánica General", 0.4, False)],
    "Carrocería": [("Mecánica General", 0.4, False)],
    "Mantenimiento Preventivo": [("Mecánica General", 1.0, True)],
    "Cambio de Aceite": [("Mecánica General", 1.0, True)],
    "Filtro de Aire": [("Mecánica General", 1.0, True)],
    "Correa de Distribución": [("Mecánica General", 1.0, True)],
    "Bujías": [
        ("Mecánica General", 0.5, False),
        ("Electricidad Automotriz", 0.5, False),
    ],
    "Otro / No clasificado": [("Mecánica General", 0.4, False)],
}

PRIORIDAD_DEFAULT_CATEGORIA = {
    "Accidente / Colisión": "alta",
    "Fuga de Combustible": "alta",
    "Sistema de Frenos": "alta",
    "Sobrecalentamiento": "alta",
    "Pinchazo": "media",
    "Motor no arranca": "media",
    "Falla de Motor": "media",
}


def _normalizar(texto: str) -> str:
    texto = unicodedata.normalize("NFD", texto.lower().strip())
    return "".join(char for char in texto if unicodedata.category(char) != "Mn")


def _ahora() -> datetime:
    return datetime.now(timezone.utc)


class RankingTallerService:
    def __init__(self, db: Session):
        self.db = db

    def asegurar_catalogo_base(self) -> None:
        especialidades = self.db.query(Especialidad).all()
        especialidades_por_nombre = {
            _normalizar(especialidad.nombre): especialidad
            for especialidad in especialidades
        }

        for nombre_categoria, especialidades_requeridas in MAPEO_CATEGORIA_ESPECIALIDADES.items():
            categoria = self._obtener_categoria_por_nombre(nombre_categoria)
            if categoria is None:
                categoria = CategoriaIncidente(
                    nombre=nombre_categoria,
                    descripcion=f"Categoria usada para asignar incidentes de tipo {nombre_categoria}.",
                    prioridad_default=PRIORIDAD_DEFAULT_CATEGORIA.get(
                        nombre_categoria,
                        "media",
                    ),
                    activa=True,
                )
                self.db.add(categoria)
                self.db.flush()

            for nombre_especialidad, peso, obligatoria in especialidades_requeridas:
                especialidad = especialidades_por_nombre.get(_normalizar(nombre_especialidad))
                if especialidad is None:
                    continue

                existe = (
                    self.db.query(CategoriaEspecialidad)
                    .filter(
                        CategoriaEspecialidad.categoria_id == categoria.id,
                        CategoriaEspecialidad.especialidad_id == especialidad.id,
                    )
                    .first()
                )
                if existe:
                    continue

                self.db.add(
                    CategoriaEspecialidad(
                        categoria_id=categoria.id,
                        especialidad_id=especialidad.id,
                        peso=peso,
                        es_obligatoria=obligatoria,
                    )
                )

        self.db.commit()

    def generar_y_ofrecer(
        self,
        incidente: Incidente,
        *,
        timeout_minutos: int = 5,
        radio_max_km: float = 40,
    ) -> list[IncidenteAsignacionCandidato]:
        self.asegurar_catalogo_base()
        categoria = self._resolver_categoria(incidente.clasificacion_ia)
        especialidades_requeridas = self._obtener_especialidades_requeridas(categoria)

        talleres = (
            self.db.query(Taller)
            .options(
                joinedload(Taller.usuarios).joinedload(Usuario.especialidades),
                joinedload(Taller.horarios),
            )
            .filter(Taller.estado == True)
            .all()
        )

        calculados = []
        for taller in talleres:
            tecnicos_activos = self._tecnicos_activos(taller)
            if not tecnicos_activos:
                continue

            distancia_metros = self._distancia_metros(incidente, taller)
            if distancia_metros is not None and distancia_metros > radio_max_km * 1000:
                continue

            score_especialidad = self._score_especialidad(
                taller,
                especialidades_requeridas,
            )
            # Se permite fallback

            score_distancia = self._score_distancia(distancia_metros, radio_max_km)
            score_disponibilidad = self._score_disponibilidad(taller, tecnicos_activos)
            score_total = (
                score_disponibilidad * 0.45
                + score_especialidad * 0.35
                + score_distancia * 0.20
            )

            calculados.append(
                {
                    "taller": taller,
                    "distancia_metros": distancia_metros,
                    "score_total": round(score_total, 4),
                    "score_distancia": round(score_distancia, 4),
                    "score_especialidad": round(score_especialidad, 4),
                    "score_disponibilidad": round(score_disponibilidad, 4),
                    "explicacion": self._explicacion(
                        taller,
                        categoria,
                        especialidades_requeridas,
                        distancia_metros,
                        score_especialidad,
                        score_disponibilidad,
                    ),
                }
            )

        def sort_key(item):
            tiene_especialidad = item["score_especialidad"] > 0
            if tiene_especialidad:
                return (1, item["score_total"], -(item["distancia_metros"] or 999999))
            else:
                return (0, -(item["distancia_metros"] or 999999), 0)

        calculados.sort(key=sort_key, reverse=True)

        self.db.query(IncidenteAsignacionCandidato).filter(
            IncidenteAsignacionCandidato.incidente_id == incidente.id
        ).delete(synchronize_session=False)

        ahora = _ahora()
        incidente.estado = (
            EstadoIncidente.BUSCANDO_TALLER
            if calculados
            else EstadoIncidente.PENDIENTE
        )
        self.db.add(incidente)
        for index, item in enumerate(calculados, start=1):
            es_primero = index == 1
            self.db.add(
                IncidenteAsignacionCandidato(
                    incidente_id=incidente.id,
                    taller_id=item["taller"].id,
                    orden=index,
                    score_total=item["score_total"],
                    score_distancia=item["score_distancia"],
                    score_especialidad=item["score_especialidad"],
                    score_disponibilidad=item["score_disponibilidad"],
                    estado="ofrecido" if es_primero else "pendiente",
                    explicacion=item["explicacion"],
                    fecha_oferta=ahora if es_primero else None,
                    expira_en=(
                        ahora + timedelta(minutes=timeout_minutos)
                        if es_primero
                        else None
                    ),
                )
            )

        self.db.commit()

        candidatos = self.obtener_candidatos(incidente.id)
        if candidatos:
            self._notificar_cliente_busqueda(incidente, len(candidatos))
            self._notificar_oferta_taller(incidente, candidatos[0])
        else:
            self._notificar_sin_talleres(incidente)

        return candidatos

    def generar_ofertas_multiples(
        self,
        incidente: Incidente,
        *,
        radio_max_km: float = 40,
    ) -> list[IncidenteAsignacionCandidato]:
        """Genera candidatos y los notifica a todos simultáneamente (Subasta/Múltiples Cotizaciones)."""
        from app.services.cotizacion_service import CotizacionService
        self.asegurar_catalogo_base()
        categoria = self._resolver_categoria(incidente.clasificacion_ia)
        especialidades_requeridas = self._obtener_especialidades_requeridas(categoria)

        talleres = (
            self.db.query(Taller)
            .options(
                joinedload(Taller.usuarios).joinedload(Usuario.especialidades),
                joinedload(Taller.horarios),
            )
            .filter(Taller.estado == True)
            .all()
        )

        calculados = []
        for taller in talleres:
            tecnicos_activos = self._tecnicos_activos(taller)
            if not tecnicos_activos:
                continue

            distancia_metros = self._distancia_metros(incidente, taller)
            if distancia_metros is not None and distancia_metros > radio_max_km * 1000:
                continue

            score_especialidad = self._score_especialidad(
                taller,
                especialidades_requeridas,
            )

            score_distancia = self._score_distancia(distancia_metros, radio_max_km)
            score_disponibilidad = self._score_disponibilidad(taller, tecnicos_activos)
            score_total = (
                score_disponibilidad * 0.45
                + score_especialidad * 0.35
                + score_distancia * 0.20
            )

            # Sugerencia IA calculada al vuelo
            sug_monto = CotizacionService.calcular_sugerencia_ia(
                self.db, taller.id, incidente.clasificacion_ia
            )

            calculados.append(
                {
                    "taller": taller,
                    "distancia_metros": distancia_metros,
                    "score_total": round(score_total, 4),
                    "score_distancia": round(score_distancia, 4),
                    "score_especialidad": round(score_especialidad, 4),
                    "score_disponibilidad": round(score_disponibilidad, 4),
                    "sugerencia_ia_monto": sug_monto,
                    "explicacion": self._explicacion(
                        taller,
                        categoria,
                        especialidades_requeridas,
                        distancia_metros,
                        score_especialidad,
                        score_disponibilidad,
                    ),
                }
            )

        def sort_key(item):
            tiene_especialidad = item["score_especialidad"] > 0
            if tiene_especialidad:
                return (1, item["score_total"], -(item["distancia_metros"] or 999999))
            else:
                return (0, -(item["distancia_metros"] or 999999), 0)

        calculados.sort(key=sort_key, reverse=True)

        self.db.query(IncidenteAsignacionCandidato).filter(
            IncidenteAsignacionCandidato.incidente_id == incidente.id
        ).delete(synchronize_session=False)

        # Estado del incidente será BUSCANDO_TALLER (subasta abierta)
        incidente.estado = EstadoIncidente.BUSCANDO_TALLER
        self.db.add(incidente)

        ahora = _ahora()
        for index, item in enumerate(calculados, start=1):
            candidato = IncidenteAsignacionCandidato(
                incidente_id=incidente.id,
                taller_id=item["taller"].id,
                orden=index,
                score_total=item["score_total"],
                score_distancia=item["score_distancia"],
                score_especialidad=item["score_especialidad"],
                score_disponibilidad=item["score_disponibilidad"],
                sugerencia_ia_monto=item["sugerencia_ia_monto"],
                estado="sugerido",  # Todos están sugeridos
                fecha_oferta=ahora,
                explicacion=item["explicacion"],
            )
            self.db.add(candidato)

        self.db.commit()

        candidatos = self.obtener_candidatos(incidente.id)
        if not candidatos:
            self._notificar_sin_talleres(incidente)
        else:
            self._notificar_cliente_busqueda(incidente, len(candidatos))
            # Notificar a TODOS los sugeridos
            for candidato in candidatos:
                self._notificar_oferta_taller(incidente, candidato)
            
        return candidatos

    def seleccionar_candidato(
        self,
        incidente: Incidente,
        taller_id: int,
        *,
        timeout_minutos: int = 5,
    ) -> IncidenteAsignacionCandidato | None:
        """El cliente elige manualmente el taller. Lo pasamos a ofrecido."""
        candidato = self.obtener_candidato_taller(incidente.id, taller_id)
        if not candidato:
            # Si el cliente lo seleccionó manualmente pero no era candidato, lo creamos
            candidato = IncidenteAsignacionCandidato(
                incidente_id=incidente.id,
                taller_id=taller_id,
                orden=1,
                score_total=1.0,
                score_distancia=1.0,
                score_especialidad=1.0,
                score_disponibilidad=1.0,
                estado="pendiente",
                explicacion="Seleccionado manualmente por el cliente."
            )
            self.db.add(candidato)
            self.db.flush()

        ahora = _ahora()
        candidato.estado = "ofrecido"
        candidato.fecha_oferta = ahora
        candidato.expira_en = ahora + timedelta(minutes=timeout_minutos)
        
        incidente.estado = EstadoIncidente.BUSCANDO_TALLER
        self.db.add(candidato)
        self.db.add(incidente)
        self.db.commit()
        
        self.db.refresh(candidato)
        self._notificar_oferta_taller(incidente, candidato)
        return candidato

    def obtener_candidatos(self, incidente_id: int) -> list[IncidenteAsignacionCandidato]:
        return (
            self.db.query(IncidenteAsignacionCandidato)
            .options(joinedload(IncidenteAsignacionCandidato.taller))
            .filter(IncidenteAsignacionCandidato.incidente_id == incidente_id)
            .order_by(IncidenteAsignacionCandidato.orden.asc())
            .all()
        )

    def tiene_candidatos(self, incidente_id: int) -> bool:
        return (
            self.db.query(IncidenteAsignacionCandidato.id)
            .filter(IncidenteAsignacionCandidato.incidente_id == incidente_id)
            .first()
            is not None
        )

    def obtener_candidato_taller(
        self,
        incidente_id: int,
        taller_id: int,
    ) -> IncidenteAsignacionCandidato | None:
        return (
            self.db.query(IncidenteAsignacionCandidato)
            .filter(
                IncidenteAsignacionCandidato.incidente_id == incidente_id,
                IncidenteAsignacionCandidato.taller_id == taller_id,
            )
            .first()
        )

    def marcar_aceptado(self, incidente_id: int, taller_id: int) -> None:
        ahora = _ahora()
        candidato = self.obtener_candidato_taller(incidente_id, taller_id)
        if candidato:
            candidato.estado = "aceptado"
            candidato.fecha_respuesta = ahora

        otros = (
            self.db.query(IncidenteAsignacionCandidato)
            .filter(
                IncidenteAsignacionCandidato.incidente_id == incidente_id,
                IncidenteAsignacionCandidato.taller_id != taller_id,
                IncidenteAsignacionCandidato.estado.in_(["pendiente", "ofrecido"]),
            )
            .all()
        )
        for otro in otros:
            otro.estado = "saltado"

        self.db.commit()

    def rechazar_y_ofrecer_siguiente(
        self,
        incidente: Incidente,
        taller_id: int,
        motivo: str | None,
    ) -> IncidenteAsignacionCandidato | None:
        candidato = self.obtener_candidato_taller(incidente.id, taller_id)
        if candidato:
            candidato.estado = "rechazado"
            candidato.motivo_rechazo = motivo
            candidato.fecha_respuesta = _ahora()
            self.db.commit()

        return self.ofrecer_siguiente(incidente)

    def ofrecer_siguiente(
        self,
        incidente: Incidente,
        *,
        timeout_minutos: int = 5,
    ) -> IncidenteAsignacionCandidato | None:
        ahora = _ahora()
        ofrecido = (
            self.db.query(IncidenteAsignacionCandidato)
            .filter(
                IncidenteAsignacionCandidato.incidente_id == incidente.id,
                IncidenteAsignacionCandidato.estado == "ofrecido",
            )
            .order_by(IncidenteAsignacionCandidato.orden.asc())
            .first()
        )
        if ofrecido and not self._esta_vencido(ofrecido, ahora):
            return ofrecido
        if ofrecido:
            ofrecido.estado = "expirado"
            ofrecido.fecha_respuesta = ahora

        siguiente = (
            self.db.query(IncidenteAsignacionCandidato)
            .filter(
                IncidenteAsignacionCandidato.incidente_id == incidente.id,
                IncidenteAsignacionCandidato.estado == "pendiente",
            )
            .order_by(IncidenteAsignacionCandidato.orden.asc())
            .first()
        )
        if not siguiente:
            incidente.estado = EstadoIncidente.PENDIENTE
            self.db.add(incidente)
            self.db.commit()
            self._notificar_sin_talleres(incidente)
            return None

        incidente.estado = EstadoIncidente.BUSCANDO_TALLER
        self.db.add(incidente)
        siguiente.estado = "ofrecido"
        siguiente.fecha_oferta = ahora
        siguiente.expira_en = ahora + timedelta(minutes=timeout_minutos)
        self.db.commit()
        self.db.refresh(siguiente)
        self._notificar_oferta_taller(incidente, siguiente)
        return siguiente

    def procesar_ofertas_vencidas(
        self,
        *,
        timeout_minutos: int = 5,
        limite: int = 50,
    ) -> int:
        ahora = _ahora()
        vencidos = (
            self.db.query(IncidenteAsignacionCandidato)
            .options(joinedload(IncidenteAsignacionCandidato.incidente))
            .filter(
                IncidenteAsignacionCandidato.estado == "ofrecido",
                IncidenteAsignacionCandidato.expira_en.isnot(None),
                IncidenteAsignacionCandidato.expira_en <= ahora,
            )
            .order_by(IncidenteAsignacionCandidato.expira_en.asc())
            .limit(limite)
            .all()
        )

        procesados = 0
        for candidato in vencidos:
            incidente = candidato.incidente
            if not incidente or incidente.taller_id:
                candidato.estado = "saltado"
                candidato.fecha_respuesta = ahora
                self.db.commit()
                continue

            candidato.estado = "expirado"
            candidato.fecha_respuesta = ahora
            self.db.commit()
            self._notificar_taller_no_responde(incidente, candidato)
            self.ofrecer_siguiente(
                incidente,
                timeout_minutos=timeout_minutos,
            )
            procesados += 1

        return procesados

    def recomendar_talleres_por_especialidad(
        self,
        *,
        especialidad_id: int,
        latitud: float | None = None,
        longitud: float | None = None,
    ) -> list[dict]:
        """Directorio de talleres (solo consulta).

        Devuelve talleres activos que ofrecen la especialidad indicada,
        ordenados con la logica de ranking existente pero priorizando la mejor
        `calificacion_promedio`. No modifica ningun incidente ni estado.
        """
        especialidad = (
            self.db.query(Especialidad)
            .filter(Especialidad.id == especialidad_id)
            .first()
        )
        if not especialidad:
            return []

        nombre_especialidad = _normalizar(especialidad.nombre)

        talleres = (
            self.db.query(Taller)
            .options(
                joinedload(Taller.usuarios).joinedload(Usuario.especialidades),
                joinedload(Taller.horarios),
            )
            .filter(Taller.estado == True)
            .all()
        )

        resultados = []
        for taller in talleres:
            tecnicos_activos = self._tecnicos_activos(taller)
            if not tecnicos_activos:
                continue
            if nombre_especialidad not in self._especialidades_taller(taller):
                continue

            distancia_metros = None
            if (
                latitud is not None
                and longitud is not None
                and taller.latitud is not None
                and taller.longitud is not None
            ):
                distancia_metros = incidente_crud.calcular_distancia_haversine(
                    float(taller.latitud),
                    float(taller.longitud),
                    float(latitud),
                    float(longitud),
                )

            resultados.append(
                {
                    "taller": taller,
                    "especialidad": especialidad.nombre,
                    "distancia_metros": distancia_metros,
                    "calificacion_promedio": taller.calificacion_promedio,
                    "score_disponibilidad": self._score_disponibilidad(taller, tecnicos_activos),
                }
            )

        # Prioridad: mejor calificacion_promedio; a igualdad, mayor disponibilidad
        # y por ultimo menor distancia.
        resultados.sort(
            key=lambda item: (
                item["calificacion_promedio"] if item["calificacion_promedio"] is not None else -1.0,
                item["score_disponibilidad"],
                -(item["distancia_metros"] if item["distancia_metros"] is not None else 1e12),
            ),
            reverse=True,
        )
        return resultados

    def _obtener_categoria_por_nombre(self, nombre: str) -> CategoriaIncidente | None:
        categoria = (
            self.db.query(CategoriaIncidente)
            .filter(CategoriaIncidente.nombre == nombre)
            .first()
        )
        if categoria:
            return categoria

        nombre_normalizado = _normalizar(nombre)
        categorias = self.db.query(CategoriaIncidente).all()
        for categoria in categorias:
            if _normalizar(categoria.nombre) == nombre_normalizado:
                return categoria
        return None

    def _resolver_categoria(self, nombre: str | None) -> CategoriaIncidente:
        nombre = nombre or "Otro / No clasificado"
        categoria = self._obtener_categoria_por_nombre(nombre)
        if categoria and categoria.activa:
            return categoria
        fallback = self._obtener_categoria_por_nombre("Otro / No clasificado")
        if fallback is None:
            raise RuntimeError("No existe la categoria fallback de incidentes.")
        return fallback

    def _obtener_especialidades_requeridas(
        self,
        categoria: CategoriaIncidente,
    ) -> list[CategoriaEspecialidad]:
        return (
            self.db.query(CategoriaEspecialidad)
            .options(joinedload(CategoriaEspecialidad.especialidad))
            .filter(CategoriaEspecialidad.categoria_id == categoria.id)
            .all()
        )

    def _tecnicos_activos(self, taller: Taller) -> list[Usuario]:
        return [
            usuario
            for usuario in taller.usuarios
            if usuario.rol_id == 3 and usuario.esta_activo
        ]

    def _especialidades_taller(self, taller: Taller) -> set[str]:
        especialidades = set()
        for tecnico in self._tecnicos_activos(taller):
            for especialidad in tecnico.especialidades:
                especialidades.add(_normalizar(especialidad.nombre))
        return especialidades

    def _score_especialidad(
        self,
        taller: Taller,
        requeridas: list[CategoriaEspecialidad],
    ) -> float:
        if not requeridas:
            return 0.2

        especialidades_taller = self._especialidades_taller(taller)
        peso_total = sum(item.peso for item in requeridas)
        if peso_total <= 0:
            return 0

        peso_match = 0.0
        falta_obligatoria = False
        for item in requeridas:
            nombre = _normalizar(item.especialidad.nombre)
            if nombre in especialidades_taller:
                peso_match += item.peso
            elif item.es_obligatoria:
                falta_obligatoria = True

        score = peso_match / peso_total
        if falta_obligatoria and score > 0:
            score *= 0.5
        return max(0, min(score, 1))

    def _score_disponibilidad(self, taller: Taller, tecnicos_activos: list[Usuario]) -> float:
        if not taller.estado or not tecnicos_activos:
            return 0
        if taller.esta_abierto_ahora:
            return 1
        return 0.55 if taller.horarios else 0.65

    def _distancia_metros(self, incidente: Incidente, taller: Taller) -> float | None:
        if (
            incidente.latitud is None
            or incidente.longitud is None
            or taller.latitud is None
            or taller.longitud is None
        ):
            return None

        return incidente_crud.calcular_distancia_haversine(
            float(taller.latitud),
            float(taller.longitud),
            float(incidente.latitud),
            float(incidente.longitud),
        )

    def _score_distancia(self, distancia_metros: float | None, radio_max_km: float) -> float:
        if distancia_metros is None:
            return 0.25
        distancia_km = distancia_metros / 1000
        return max(0, min(1 - distancia_km / radio_max_km, 1))

    def _explicacion(
        self,
        taller: Taller,
        categoria: CategoriaIncidente,
        requeridas: list[CategoriaEspecialidad],
        distancia_metros: float | None,
        score_especialidad: float,
        score_disponibilidad: float,
    ) -> str:
        especialidades = ", ".join(taller.especialidades_activas) or "sin especialidades activas"
        requeridas_texto = ", ".join(
            f"{item.especialidad.nombre} ({item.peso:g})"
            for item in requeridas
        ) or "sin especialidades definidas"
        distancia = (
            f"{distancia_metros / 1000:.1f} km"
            if distancia_metros is not None
            else "distancia no disponible"
        )
        disponibilidad = "abierto" if taller.esta_abierto_ahora else "fuera de horario"
        return (
            f"Categoria {categoria.nombre}. Requiere: {requeridas_texto}. "
            f"Taller con: {especialidades}. Distancia: {distancia}. "
            f"Disponibilidad: {disponibilidad}. "
            f"Compatibilidad {score_especialidad:.0%}, disponibilidad {score_disponibilidad:.0%}."
        )

    def _esta_vencido(
        self,
        candidato: IncidenteAsignacionCandidato,
        ahora: datetime,
    ) -> bool:
        if candidato.expira_en is None:
            return False
        expira_en = candidato.expira_en
        if expira_en.tzinfo is None:
            ahora = datetime.utcnow()
        return expira_en <= ahora

    def _notificar_cliente_busqueda(self, incidente: Incidente, cantidad: int) -> None:
        NotificacionService.crear_notificacion(
            db=self.db,
            usuario_id=incidente.usuario_id,
            titulo="Buscando taller",
            mensaje=f"Encontramos {cantidad} talleres candidatos para tu incidente #{incidente.id}.",
            tipo="buscando_taller",
            incidente_id=incidente.id,
            extra_data={
                "evento": "buscando_taller",
                "estado_nuevo": incidente.estado,
                "candidatos": cantidad,
            },
        )

    def _notificar_sin_talleres(self, incidente: Incidente) -> None:
        NotificacionService.crear_notificacion(
            db=self.db,
            usuario_id=incidente.usuario_id,
            titulo="Sin talleres disponibles",
            mensaje=(
                f"No encontramos talleres compatibles para el incidente #{incidente.id}. "
                "El caso queda pendiente para revision manual."
            ),
            tipo="sin_talleres_disponibles",
            incidente_id=incidente.id,
            extra_data={
                "evento": "sin_talleres_disponibles",
                "estado_nuevo": incidente.estado,
            },
        )

    def _notificar_oferta_taller(
        self,
        incidente: Incidente,
        candidato: IncidenteAsignacionCandidato,
    ) -> None:
        admins = (
            self.db.query(Usuario)
            .filter(
                Usuario.taller_id == candidato.taller_id,
                Usuario.rol_id == 1,
                Usuario.esta_activo == True,
            )
            .all()
        )
        for admin in admins:
            NotificacionService.crear_notificacion(
                db=self.db,
                usuario_id=admin.id,
                titulo="Nuevo incidente compatible",
                mensaje=(
                    f"Tu taller recibio el incidente #{incidente.id}. "
                    f"Categoria: {incidente.clasificacion_ia or 'No clasificada'}."
                ),
                tipo="incidente_ofrecido_taller",
                incidente_id=incidente.id,
                extra_data={
                    "evento": "incidente_ofrecido_taller",
                    "taller_id": candidato.taller_id,
                    "orden": candidato.orden,
                    "score_total": candidato.score_total,
                    "expira_en": (
                        candidato.expira_en.isoformat()
                        if candidato.expira_en
                        else None
                    ),
                },
            )

    def _notificar_taller_no_responde(
        self,
        incidente: Incidente,
        candidato: IncidenteAsignacionCandidato,
    ) -> None:
        NotificacionService.crear_notificacion(
            db=self.db,
            usuario_id=incidente.usuario_id,
            titulo="Buscando otro taller",
            mensaje=(
                f"El taller candidato no respondio el incidente #{incidente.id}. "
                "Estamos buscando el siguiente taller disponible."
            ),
            tipo="taller_no_responde",
            incidente_id=incidente.id,
            extra_data={
                "evento": "taller_no_responde",
                "estado_nuevo": incidente.estado,
                "taller_id": candidato.taller_id,
            },
        )
