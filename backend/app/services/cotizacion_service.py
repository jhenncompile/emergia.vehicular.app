from sqlalchemy.orm import Session
from sqlalchemy import func
from app.models.incidente import Incidente
from app.models.pago import Pago

class CotizacionService:
    @staticmethod
    def calcular_sugerencia_ia(db: Session, taller_id: int, clasificacion_ia: str) -> float:
        """
        Calcula un promedio histórico de cobros para sugerir un precio base al taller.
        Prioriza el historial del propio taller, luego el global, y finalmente un fallback estático.
        """
        if not clasificacion_ia:
            clasificacion_ia = "Otro / No clasificado"

        # 1. Promedio histórico del propio taller
        promedio_taller = db.query(func.avg(Pago.monto))\
            .join(Incidente, Pago.incidente_id == Incidente.id)\
            .filter(
                Incidente.taller_id == taller_id, 
                Incidente.clasificacion_ia == clasificacion_ia, 
                Pago.estado == 'completado'
            ).scalar()
        
        if promedio_taller is not None:
            return round(float(promedio_taller), 2)
            
        # 2. Promedio global de todos los talleres para esa categoría
        promedio_global = db.query(func.avg(Pago.monto))\
            .join(Incidente, Pago.incidente_id == Incidente.id)\
            .filter(
                Incidente.clasificacion_ia == clasificacion_ia, 
                Pago.estado == 'completado'
            ).scalar()
            
        if promedio_global is not None:
            return round(float(promedio_global), 2)
            
        # 3. Fallback estático
        BASE_PRICES = {
            "Pinchazo": 50.0,
            "Daño en Rueda o Rin": 120.0,
            "Falla Eléctrica": 150.0,
            "Revisión de Batería": 80.0,
            "Alternador": 300.0,
            "Fuga de refrigerante": 200.0,
            "Fuga de Aceite": 250.0,
            "Fuga de Combustible": 300.0,
            "Sobrecalentamiento": 250.0,
            "Sistema de Frenos": 250.0,
            "Falla de Motor": 500.0,
            "Motor no arranca": 200.0,
            "Bomba de Gasolina": 350.0,
            "Transmisiones": 800.0,
            "Falla de Embrague": 600.0,
            "Dirección": 400.0,
            "Ruido en Suspensión": 300.0,
            "Alineación y Balanceo": 120.0,
            "Aire Acondicionado": 250.0,
            "Llave o Inmovilizador": 350.0,
            "Cerrajería Vehicular": 150.0,
            "Escape / Catalizador": 400.0,
            "Cristales / Parabrisas": 600.0,
            "Carrocería": 800.0,
            "Mantenimiento Preventivo": 200.0,
            "Cambio de Aceite": 180.0,
            "Filtro de Aire": 80.0,
            "Correa de Distribución": 700.0,
            "Bujías": 150.0,
            "Accidente / Colisión": 1500.0,
        }
        
        for key, val in BASE_PRICES.items():
            if key.lower() in clasificacion_ia.lower():
                return val
                
        return 100.0 # Universal fallback
