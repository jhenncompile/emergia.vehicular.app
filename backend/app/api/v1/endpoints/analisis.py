from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, Integer, case
from typing import List, Optional
from datetime import datetime, timedelta

from app.api import deps
from app.models.incidente import Incidente

router = APIRouter()

@router.get("/por-tipo")
def analisis_por_tipo(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller),
    dias: int = Query(30, description="Días a analizar")
):
    """
    Devuelve la cantidad de incidentes agrupados por clasificación IA (tipo)
    """
    fecha_limite = datetime.utcnow() - timedelta(days=dias)
    
    resultados = db.query(
        Incidente.clasificacion_ia,
        func.count(Incidente.id).label("total")
    ).filter(
        Incidente.fecha_creacion >= fecha_limite
    ).group_by(
        Incidente.clasificacion_ia
    ).all()

    # Mapear los resultados directamente desde la BD
    response = []
    
    # Si la BD está vacía o todo es null, inyectar algunos datos de ejemplo si no hay absolutamente nada 
    # (solo para que no se vea vacío en desarrollo)
    if not resultados:
        return [
            {"tipo": "Batería", "total": 0},
            {"tipo": "Llanta", "total": 0},
            {"tipo": "Motor", "total": 0},
            {"tipo": "Choque", "total": 0}
        ]
        
    for row in resultados:
        tipo = row.clasificacion_ia if row.clasificacion_ia else "Sin Clasificar"
        # Limpiar posibles variaciones de "Sin Clasificar" o nulls
        response.append({
            "tipo": tipo.capitalize() if tipo != "Sin Clasificar" else tipo,
            "total": row.total
        })

    # Ordenar de mayor a menor
    response.sort(key=lambda x: x["total"], reverse=True)
            
    return response

@router.get("/heatmap")
def analisis_heatmap(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller),
    dias: int = Query(30, description="Días a analizar")
):
    """
    Devuelve los puntos geográficos para el mapa de calor
    """
    fecha_limite = datetime.utcnow() - timedelta(days=dias)
    
    incidentes = db.query(
        Incidente.latitud,
        Incidente.longitud,
        Incidente.clasificacion_ia
    ).filter(
        Incidente.fecha_creacion >= fecha_limite,
        Incidente.latitud.isnot(None),
        Incidente.longitud.isnot(None)
    ).all()

    response = []
    for inc in incidentes:
        response.append({
            "lat": float(inc.latitud),
            "lng": float(inc.longitud),
            "tipo": inc.clasificacion_ia or "Otros",
            "peso": 1.0 # Peso base para cada punto en Leaflet Heat
        })

    return response

@router.get("/ranking-talleres")
def ranking_talleres(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_admin_taller),
    dias: int = Query(30, description="Días a analizar")
):
    """
    Devuelve un ranking de talleres basado en eficiencia (tiempo de respuesta, tasa de éxito y calificación de clientes).
    """
    from app.models.taller import Taller
    
    fecha_limite = datetime.utcnow() - timedelta(days=dias)
    
    # Obtener incidentes agrupados por taller, incluyendo la calificación promedio del Taller
    resultados = db.query(
        Taller.id,
        Taller.nombre,
        Taller.calificacion_promedio,
        func.count(Incidente.id).label("total_incidentes"),
        func.sum(case((Incidente.estado == 'finalizado', 1), else_=0)).label("exitosos"),
        func.avg(Incidente.tiempo_asignacion_segundos).label("tiempo_promedio")
    ).outerjoin(
        Incidente, (Incidente.taller_id == Taller.id) & (Incidente.fecha_creacion >= fecha_limite)
    ).group_by(
        Taller.id, Taller.nombre, Taller.calificacion_promedio
    ).all()
    
    ranking = []
    for row in resultados:
        total = row.total_incidentes
        # Include all talleres, even if total == 0, so the leaderboard isn't empty!
            
        exitosos = row.exitosos or 0
        tasa_exito = (exitosos / total * 100) if total > 0 else 0
        
        tiempo_avg = row.tiempo_promedio or 0
        tiempo_avg_segundos = float(tiempo_avg)
        
        calificacion_estrellas = float(row.calificacion_promedio or 0.0)
        
        # Nueva Fórmula: 40% éxito, 30% tiempo, 30% estrellas
        # Puntaje éxito (max 40):
        score_exito = (tasa_exito / 100) * 40
        
        # Puntaje tiempo (max 30): óptimo 0s, límite 600s (10 min)
        if tiempo_avg_segundos >= 600 or total == 0:
            score_tiempo = 0
        else:
            score_tiempo = (1 - (tiempo_avg_segundos / 600)) * 30
            
        # Puntaje estrellas (max 30): 5 estrellas = 30 puntos
        score_estrellas = (calificacion_estrellas / 5.0) * 30
            
        puntaje_final = score_exito + score_tiempo + score_estrellas
        
        ranking.append({
            "taller_id": row.id,
            "nombre": row.nombre,
            "total_atenciones": total,
            "tasa_exito": round(tasa_exito, 1),
            "tiempo_promedio": round(tiempo_avg_segundos, 1),
            "calificacion_promedio": round(calificacion_estrellas, 1),
            "puntaje": round(puntaje_final, 1)
        })
        
    # Ordenar de mayor a menor puntaje
    ranking.sort(key=lambda x: x["puntaje"], reverse=True)
    
    return ranking
