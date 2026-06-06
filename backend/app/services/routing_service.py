"""
Servicio de rutas usando OpenStreetMap OSRM (Open Source Routing Machine)
"""
from typing import Dict, Any, Optional, List
import httpx
import asyncio
from app.core.config import settings


class RoutingService:
    """Servicio de rutas y cálculos de distancia/duración"""
    
    # API pública de OSRM
    OSRM_BASE = "https://router.project-osrm.org/route/v1"
    TIMEOUT = 10.0
    
    @staticmethod
    async def obtener_ruta(
        lon_origen: float,
        lat_origen: float,
        lon_destino: float,
        lat_destino: float
    ) -> Dict[str, Any]:
        """
        Obtener ruta entre dos puntos usando OSRM
        
        Args:
            lon_origen, lat_origen: Punto de inicio (técnico)
            lon_destino, lat_destino: Punto final (incidente)
            
        Returns:
            {
                "distancia_km": float,
                "duracion_minutos": float,
                "geometry": dict (GeoJSON),
                "pasos": list,
                "error": str | None
            }
        """
        try:
            # Construir URL
            url = (
                f"{RoutingService.OSRM_BASE}/driving/"
                f"{lon_origen},{lat_origen};"
                f"{lon_destino},{lat_destino}"
                f"?geometries=geojson&steps=true&overview=full"
            )
            
            async with httpx.AsyncClient() as client:
                response = await client.get(url, timeout=RoutingService.TIMEOUT)
                
                if response.status_code != 200:
                    return {
                        "error": f"OSRM error: {response.status_code}",
                        "distancia_km": None,
                        "duracion_minutos": None,
                        "geometry": None,
                        "pasos": []
                    }
                
                data = response.json()
                
                if data.get("code") != "Ok":
                    return {
                        "error": f"OSRM returned code: {data.get('code')}",
                        "distancia_km": None,
                        "duracion_minutos": None,
                        "geometry": None,
                        "pasos": []
                    }
                
                if not data.get("routes"):
                    return {
                        "error": "No routes found",
                        "distancia_km": None,
                        "duracion_minutos": None,
                        "geometry": None,
                        "pasos": []
                    }
                
                route = data["routes"][0]
                
                return {
                    "error": None,
                    "distancia_km": round(route["distance"] / 1000, 2),
                    "duracion_minutos": round(route["duration"] / 60, 1),
                    "geometry": route.get("geometry"),  # GeoJSON
                    "pasos": RoutingService._extraer_pasos(route),
                }
        
        except asyncio.TimeoutError:
            return {
                "error": "Timeout connecting to OSRM",
                "distancia_km": None,
                "duracion_minutos": None,
                "geometry": None,
                "pasos": []
            }
        except Exception as e:
            return {
                "error": f"Error obteniendo ruta: {str(e)}",
                "distancia_km": None,
                "duracion_minutos": None,
                "geometry": None,
                "pasos": []
            }
    
    @staticmethod
    def _extraer_pasos(route: Dict) -> List[Dict]:
        """
        Extraer instrucciones paso a paso de la ruta
        
        Returns:
            [
                {
                    "instruccion": "Gira derecha en Calle Principal",
                    "distancia_m": 150,
                    "duracion_seg": 12
                }
            ]
        """
        pasos = []
        
        for leg in route.get("legs", []):
            for step in leg.get("steps", []):
                instruction = step.get("maneuver", {}).get("instruction", "Continúa")
                
                pasos.append({
                    "instruccion": instruction,
                    "distancia_m": round(step.get("distance", 0)),
                    "duracion_seg": round(step.get("duration", 0)),
                })
        
        return pasos
    
    @staticmethod
    def calcular_eta_minutos(distancia_km: float, velocidad_promedio_kmh: float = 40) -> float:
        """
        Calcular ETA basado en distancia y velocidad promedio
        
        Args:
            distancia_km: Distancia en kilómetros
            velocidad_promedio_kmh: Velocidad promedio en km/h (default 40 km/h para ciudad)
            
        Returns:
            ETA en minutos
        """
        if distancia_km <= 0:
            return 0
        
        return round((distancia_km / velocidad_promedio_kmh) * 60)
