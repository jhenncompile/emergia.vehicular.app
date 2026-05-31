from app.db.base_class import Base  # noqa
from app.models.usuario import Usuario
from app.models.rol import Rol
from app.models.taller import Taller
from app.models.vehiculo import Vehiculo
from app.models.incidente import Incidente
from app.models.notificacion import Notificacion, TokenDispositivo
from app.models.pago import Pago
from app.models.taller_detalle import HorarioTaller
from app.models.usuario import Usuario, Especialidad
from app.models.bitacora import Bitacora
from app.models.evidencia import Evidencia
from app.models.asignacion_inteligente import (
    CategoriaEspecialidad,
    CategoriaIncidente,
    IncidenteAsignacionCandidato,
)
