import os
import sys
import argparse
sys.path.insert(0, os.path.abspath("."))
from sqlalchemy.orm import Session
from app.db.session import SessionLocal
from app.api.v1.endpoints.incidentes import rechazar_pedido_auxilio
from app.models.usuario import Usuario

def main():
    db = SessionLocal()
    # Find admin taller for testing
    admin = db.query(Usuario).filter(Usuario.rol_id == 2).first()
    if not admin:
        print("No admin taller found")
        return
    try:
        rechazar_pedido_auxilio(db=db, id=34, motivo="Test", current_user=admin)
        print("Success")
    except Exception as e:
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
