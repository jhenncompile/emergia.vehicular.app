class EstadoIncidente:
    PENDIENTE = "pendiente"
    BUSCANDO_TALLER = "buscando_taller"
    ASIGNADO_TALLER = "asignado_taller"
    EN_CAMINO = "en_camino"
    EN_ATENCION = "en_atencion"
    FINALIZADO = "finalizado"
    CANCELADO = "cancelado"


ESTADOS_INCIDENTE_ACTIVOS = {
    EstadoIncidente.BUSCANDO_TALLER,
    EstadoIncidente.ASIGNADO_TALLER,
    EstadoIncidente.EN_CAMINO,
    EstadoIncidente.EN_ATENCION,
}

ESTADOS_INCIDENTE_HISTORICOS = {
    EstadoIncidente.FINALIZADO,
    EstadoIncidente.CANCELADO,
}

ESTADOS_CANCELABLES_CLIENTE = {
    EstadoIncidente.PENDIENTE,
    EstadoIncidente.BUSCANDO_TALLER,
    EstadoIncidente.ASIGNADO_TALLER,
    EstadoIncidente.EN_CAMINO,
}

ESTADOS_CANCELABLES_TALLER = {
    EstadoIncidente.ASIGNADO_TALLER,
    EstadoIncidente.EN_CAMINO,
}


class CanceladoPor:
    CLIENTE = "cliente"
    TALLER = "taller"
    SISTEMA = "sistema"
    ADMIN = "admin"

