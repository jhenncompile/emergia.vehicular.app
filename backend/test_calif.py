import sys
import os

# Add the parent directory to sys.path to import app modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.session import SessionLocal
from app.crud.crud_calificacion import calificacion_crud

def test_query():
    db = SessionLocal()
    try:
        taller_id = 1
        print("Testing without filters:")
        res1 = calificacion_crud.promedio_taller(db, taller_id=taller_id)
        print("Res1:", res1)
        
        print("Testing with filters:")
        res2 = calificacion_crud.promedio_taller(db, taller_id=taller_id, tecnico_id=1)
        print("Res2:", res2)
    except Exception as e:
        print("Error:", e)
    finally:
        db.close()

if __name__ == "__main__":
    test_query()
