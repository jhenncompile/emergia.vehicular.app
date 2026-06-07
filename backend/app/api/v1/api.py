from fastapi import APIRouter
from app.api.v1.endpoints import (
    auth, usuario, incidentes, talleres, vehiculos, 
    bitacora, notificaciones, pagos, roles, taller_detalles, evidencias, 
    emergencia, seguimiento, calificaciones, analisis
)

api_router = APIRouter()

api_router.include_router(emergencia.router, prefix="/emergencia", tags=["Emergencia"])
api_router.include_router(seguimiento.router, tags=["Seguimiento"])

api_router.include_router(auth.router, prefix="/auth", tags=["Autenticación"])
api_router.include_router(usuario.router, prefix="/usuarios", tags=["Usuarios"])
api_router.include_router(incidentes.router, prefix="/incidentes", tags=["Incidentes"])
api_router.include_router(talleres.router, prefix="/talleres", tags=["Talleres"])
api_router.include_router(taller_detalles.router, prefix="/taller-config", tags=["Configuración Taller"])
api_router.include_router(vehiculos.router, prefix="/vehiculos", tags=["Vehículos"])
api_router.include_router(evidencias.router, prefix="/evidencias", tags=["Evidencias"])
api_router.include_router(notificaciones.router, prefix="/notificaciones", tags=["Notificaciones"])
api_router.include_router(pagos.router, prefix="/pagos", tags=["Pagos"])
api_router.include_router(roles.router, prefix="/roles", tags=["Roles"])
api_router.include_router(bitacora.router, prefix="/bitacora", tags=["Auditoría"])
api_router.include_router(calificaciones.router, prefix="/calificaciones", tags=["Calificaciones"])
api_router.include_router(analisis.router, prefix="/analisis", tags=["Análisis"])