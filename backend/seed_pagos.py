from app.db.base import Base
from app.db.session import SessionLocal
from app.models.incidente import Incidente
from app.models.pago import Pago
import random
from datetime import datetime, timedelta

db = SessionLocal()
incidentes = db.query(Incidente).filter(Incidente.estado == 'finalizado', Incidente.taller_id != None).all()
count = 0
for inc in incidentes:
    monto = random.randint(100, 1500)
    pago = Pago(
        incidente_id=inc.id,
        usuario_id=inc.usuario_id,
        taller_id=inc.taller_id,
        monto=monto,
        comision_plataforma=monto * 0.1,
        metodo_pago=random.choice(['efectivo', 'qr', 'transferencia']),
        estado=random.choice(['pendiente', 'completado', 'cancelado']),
        fecha=datetime.now() - timedelta(days=random.randint(1,30))
    )
    db.add(pago)
    count += 1
db.commit()
print(f'Created {count} pagos.')
