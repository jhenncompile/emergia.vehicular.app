import os
import sys
import subprocess
import argparse
from sqlalchemy import create_engine, text

# CONFIGURAR ENCODING DE WINDOWS
os.environ['PYTHONIOENCODING'] = 'utf-8'
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# Asegurar que encuentre el módulo 'app'
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.base import Base  # Asegúrate de que este archivo importe todos tus modelos
from app.db.session import SessionLocal, engine
from app.db.seeder import seed_db 
from app.core.config import settings

# Manejo de errores encoding-safe
import logging
logging.basicConfig(level=logging.INFO, format='%(message)s')

def run_command(command):
    """Ejecuta comandos de terminal con mejor manejo de encoding"""
    print(f"[CMD] Executing: {command}")
    try:
        result = subprocess.run(
            command, 
            shell=True, 
            capture_output=True, 
            text=True,
            encoding='utf-8',
            errors='replace'
        )
        if result.returncode != 0:
            stderr = (result.stderr[:200] if result.stderr else "Sin detalles").encode('utf-8', errors='ignore').decode('utf-8', errors='ignore')
            print(f"[WARN] Error: {stderr}")
        else:
            stdout = (result.stdout[:200] if result.stdout else "Exito").encode('utf-8', errors='ignore').decode('utf-8', errors='ignore')
            print(f"[OK] {stdout}")
    except Exception as e:
        error_str = str(e)[:100]
        error_str = error_str.encode('utf-8', errors='ignore').decode('utf-8', errors='ignore')
        print(f"[ERROR] Ejecutando comando: {error_str}")

def positive_int(value):
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Debe ser un numero entero") from exc
    if number < 1:
        raise argparse.ArgumentTypeError("Debe ser mayor o igual a 1")
    return number


def non_negative_int(value):
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Debe ser un numero entero") from exc
    if number < 0:
        raise argparse.ArgumentTypeError("Debe ser mayor o igual a 0")
    return number


def build_parser():
    parser = argparse.ArgumentParser(
        description=(
            "Reinicia la base de datos y la puebla con datos variables. "
            "Los incidentes generados quedan en estado finalizado."
        ),
        epilog=(
            "Ejemplos:\n"
            "  python reset_db.py\n"
            "  python reset_db.py --yes --talleres 8 --clientes 40 --incidentes 300\n"
            "  python reset_db.py -y --clientes 20 --incidentes-min 50 --incidentes-max 80 --seed 123\n"
            "  python reset_db.py -y --incidentes 0 --bitacoras 0 --evidencias 0 --notificaciones 0"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="Confirma el borrado sin preguntar.",
    )
    parser.add_argument(
        "--talleres",
        dest="talleres_count",
        type=positive_int,
        default=6,
        help="Cantidad de talleres a crear.",
    )
    parser.add_argument(
        "--usuarios",
        "--clientes",
        "--usuarios-clientes",
        dest="clientes_count",
        type=positive_int,
        default=12,
        help=(
            "Cantidad de usuarios cliente a crear. "
            "Los admins y tecnicos se crean aparte segun los talleres."
        ),
    )
    parser.add_argument(
        "--incidentes",
        dest="incidentes_count",
        type=non_negative_int,
        default=None,
        help="Cantidad exacta de incidentes finalizados a crear.",
    )
    parser.add_argument(
        "--incidentes-min",
        type=non_negative_int,
        default=250,
        help="Minimo de incidentes si no se usa --incidentes.",
    )
    parser.add_argument(
        "--incidentes-max",
        type=non_negative_int,
        default=350,
        help="Maximo de incidentes si no se usa --incidentes.",
    )
    parser.add_argument(
        "--tecnicos-por-taller",
        dest="tecnicos_por_taller_count",
        type=positive_int,
        default=None,
        help="Cantidad exacta de tecnicos por taller.",
    )
    parser.add_argument(
        "--tecnicos-min",
        dest="tecnicos_por_taller_min",
        type=positive_int,
        default=2,
        help="Minimo de tecnicos por taller.",
    )
    parser.add_argument(
        "--tecnicos-max",
        dest="tecnicos_por_taller_max",
        type=positive_int,
        default=3,
        help="Maximo de tecnicos por taller.",
    )
    parser.add_argument(
        "--vehiculos-por-cliente",
        dest="vehiculos_por_cliente_count",
        type=positive_int,
        default=None,
        help="Cantidad exacta de vehiculos por cliente.",
    )
    parser.add_argument(
        "--vehiculos-min",
        dest="vehiculos_por_cliente_min",
        type=positive_int,
        default=1,
        help="Minimo de vehiculos por cliente.",
    )
    parser.add_argument(
        "--vehiculos-max",
        dest="vehiculos_por_cliente_max",
        type=positive_int,
        default=2,
        help="Maximo de vehiculos por cliente.",
    )
    parser.add_argument(
        "--bitacoras",
        dest="bitacoras_count",
        type=non_negative_int,
        default=100,
        help="Cantidad de registros de bitacora a crear.",
    )
    parser.add_argument(
        "--evidencias",
        dest="evidencias_count",
        type=non_negative_int,
        default=80,
        help="Cantidad de evidencias a crear.",
    )
    parser.add_argument(
        "--notificaciones",
        dest="notificaciones_count",
        type=non_negative_int,
        default=60,
        help="Cantidad de notificaciones a crear.",
    )
    parser.add_argument(
        "--dias-historial",
        dest="dias_historial",
        type=positive_int,
        default=365,
        help="Rango maximo de dias hacia atras para fechas historicas.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Semilla opcional para repetir exactamente los mismos datos.",
    )
    return parser


def build_seed_options(args):
    if args.tecnicos_por_taller_count is not None:
        args.tecnicos_por_taller_min = args.tecnicos_por_taller_count
        args.tecnicos_por_taller_max = args.tecnicos_por_taller_count
    if args.vehiculos_por_cliente_count is not None:
        args.vehiculos_por_cliente_min = args.vehiculos_por_cliente_count
        args.vehiculos_por_cliente_max = args.vehiculos_por_cliente_count

    if args.incidentes_count is None and args.incidentes_min > args.incidentes_max:
        raise SystemExit("--incidentes-min no puede ser mayor que --incidentes-max")
    if args.tecnicos_por_taller_min > args.tecnicos_por_taller_max:
        raise SystemExit("--tecnicos-min no puede ser mayor que --tecnicos-max")
    if args.vehiculos_por_cliente_min > args.vehiculos_por_cliente_max:
        raise SystemExit("--vehiculos-min no puede ser mayor que --vehiculos-max")

    return {
        "talleres_count": args.talleres_count,
        "clientes_count": args.clientes_count,
        "incidentes_count": args.incidentes_count,
        "incidentes_min": args.incidentes_min,
        "incidentes_max": args.incidentes_max,
        "tecnicos_por_taller_min": args.tecnicos_por_taller_min,
        "tecnicos_por_taller_max": args.tecnicos_por_taller_max,
        "vehiculos_por_cliente_min": args.vehiculos_por_cliente_min,
        "vehiculos_por_cliente_max": args.vehiculos_por_cliente_max,
        "bitacoras_count": args.bitacoras_count,
        "evidencias_count": args.evidencias_count,
        "notificaciones_count": args.notificaciones_count,
        "dias_historial": args.dias_historial,
        "seed": args.seed,
    }


def ask_int(question, *, default=None, minimum=0):
    while True:
        suffix = f" [{default}]" if default is not None else ""
        value = input(f"{question}{suffix}: ").strip()
        if not value and default is not None:
            return default
        try:
            number = int(value)
        except ValueError:
            print("[WARN] Escribe un numero entero.")
            continue
        if number < minimum:
            print(f"[WARN] El numero debe ser mayor o igual a {minimum}.")
            continue
        return number


def ask_optional_int(question, *, default=None):
    while True:
        suffix = f" [{default}]" if default is not None else " [aleatoria]"
        value = input(f"{question}{suffix}: ").strip()
        if not value:
            return default
        try:
            return int(value)
        except ValueError:
            print("[WARN] Escribe un numero entero o deja vacio.")


def collect_seed_options_interactive(args):
    print("\n[SEED] Configuracion interactiva de datos")
    print("[INFO] Presiona Enter para usar el valor entre corchetes.\n")

    talleres_count = ask_int(
        "Cuantos talleres quiere",
        default=args.talleres_count,
        minimum=1,
    )
    tecnicos_por_taller = ask_int(
        "Cuantos tecnicos por taller quiere",
        default=args.tecnicos_por_taller_count or args.tecnicos_por_taller_min,
        minimum=1,
    )
    clientes_count = ask_int(
        "Cuantos clientes quiere",
        default=args.clientes_count,
        minimum=1,
    )
    vehiculos_por_cliente = ask_int(
        "Cuantos vehiculos por cliente quiere",
        default=args.vehiculos_por_cliente_count or args.vehiculos_por_cliente_min,
        minimum=1,
    )
    incidentes_count = ask_int(
        "Cuantos incidentes finalizados quiere",
        default=args.incidentes_count if args.incidentes_count is not None else args.incidentes_min,
        minimum=0,
    )
    bitacoras_count = ask_int(
        "Cuantos registros de bitacora quiere",
        default=args.bitacoras_count,
        minimum=0,
    )
    evidencias_count = ask_int(
        "Cuantas evidencias quiere",
        default=args.evidencias_count,
        minimum=0,
    )
    notificaciones_count = ask_int(
        "Cuantas notificaciones quiere",
        default=args.notificaciones_count,
        minimum=0,
    )
    dias_historial = ask_int(
        "Cuantos dias hacia atras quiere para el historial",
        default=args.dias_historial,
        minimum=1,
    )
    seed = ask_optional_int(
        "Semilla para repetir datos exactos, deje vacio para aleatoria",
        default=args.seed,
    )

    return {
        "talleres_count": talleres_count,
        "clientes_count": clientes_count,
        "incidentes_count": incidentes_count,
        "incidentes_min": incidentes_count,
        "incidentes_max": incidentes_count,
        "tecnicos_por_taller_min": tecnicos_por_taller,
        "tecnicos_por_taller_max": tecnicos_por_taller,
        "vehiculos_por_cliente_min": vehiculos_por_cliente,
        "vehiculos_por_cliente_max": vehiculos_por_cliente,
        "bitacoras_count": bitacoras_count,
        "evidencias_count": evidencias_count,
        "notificaciones_count": notificaciones_count,
        "dias_historial": dias_historial,
        "seed": seed,
    }


def reset_database(seed_options=None):
    seed_options = seed_options or {}
    DATABASE_URL = settings.DATABASE_URL
    is_sqlite = DATABASE_URL.startswith('sqlite')
    is_postgres = DATABASE_URL.startswith('postgresql')
    
    # Sanitizar la URL para evitar problemas de encoding
    db_info = DATABASE_URL.split('@')[-1] if '@' in DATABASE_URL else DATABASE_URL
    db_info = db_info.encode('utf-8', errors='ignore').decode('utf-8', errors='ignore')
    print(f"[INIT] --- INICIANDO RESET TOTAL EN: {db_info} ---")
    print(f"[INFO] Tipo de DB: {'SQLite' if is_sqlite else 'PostgreSQL'}")

    # 1. Limpieza de Esquema 
    try:
        if is_postgres:
            print("[CLEAN] Borrando y recreando esquema publico (PostgreSQL)...")
            with engine.connect() as conn:
                conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE;"))
                conn.execute(text("CREATE SCHEMA public;"))
                conn.execute(text("GRANT ALL ON SCHEMA public TO public;"))
                conn.commit()
        elif is_sqlite:
            print("[CLEAN] Limpiando base de datos SQLite...")
            db_path = DATABASE_URL.replace('sqlite:///', '').replace('sqlite:', '')
            if os.path.exists(db_path):
                os.remove(db_path)
                print(f"[OK] Archivo SQLite eliminado: {db_path}")
        print("[OK] Esquema limpio.")
    except Exception as e:
        # Evitar problemas de encoding en el mensaje de error
        try:
            error_msg = str(e).encode('utf-8', errors='replace').decode('utf-8')
        except:
            error_msg = "[Error con encoding desconocido]"
        
        if "password" in error_msg.lower() or "auth" in error_msg.lower():
            print(f"[ERROR] ERROR DE AUTENTICACION con PostgreSQL")
            print(f"[ERROR] DATABASE_URL: {DATABASE_URL}")
        else:
            print(f"[WARN] Continuando a pesar del error en limpieza")
        # Continuamos de todas formas - talvez las tablas ya existen

    # 2. Reconstruir Tablas mediante SQLAlchemy
    print("[BUILD] Creando tablas desde modelos de SQLAlchemy...")
    try:
        Base.metadata.create_all(bind=engine)
        print("[OK] Tablas creadas exitosamente.")
    except Exception as e:
        print(f"[ERROR] Error al crear tablas: {e}")
        return

    # 3. Sincronizar Alembic (Stamp)
    # Esto le dice a Alembic que la DB ya está en la última versión y no intente crear tablas de nuevo
    print("[STAMP] Marcando versión en Alembic (Stamp)...")
    run_command("alembic stamp head")

    # 4. Ejecutar Seeder
    print("[SEED] Poblando base de datos...")
    db = SessionLocal()
    try:
        seed_config = ", ".join(
            f"{key}={value}"
            for key, value in seed_options.items()
            if value is not None
        )
        print(f"[SEED] Opciones: {seed_config or 'valores por defecto'}")
        seed_db(db, **seed_options)
        print("[OK] Datos de prueba insertados.")

        # 5. Sincronizar Secuencias de IDs (solo PostgreSQL)
        if is_postgres:
            print("[SYNC] Sincronizando secuencias (PostgreSQL)...")
            try:
                with engine.connect() as conn:
                    # Lista de tablas a sincronizar
                    tablas = ['rol', 'usuario', 'taller', 'incidente', 'pago', 'especialidad', 'evidencia', 'bitacora', 'calificacion']
                    for tabla in tablas:
                        try:
                            # Intenta sincronizar la secuencia de la tabla
                            conn.execute(text(f"SELECT setval(pg_get_serial_sequence('{tabla}', 'id'), coalesce(max(id), 1), max(id) IS NOT null) FROM {tabla};"))
                        except Exception:
                            continue
                    conn.commit()
                print("[OK] Secuencias alineadas.")
            except Exception as e:
                print(f"[WARN] Error al sincronizar secuencias: {str(e)[:100]}")
        else:
            print("[OK] SQLite no requiere sincronizacion de secuencias.")
    except Exception as e:
        error_msg = str(e).encode('utf-8', errors='ignore').decode('utf-8', errors='ignore')
        print(f"[ERROR] Error en el Seeder: {error_msg[:150]}")
    finally:
        db.close()

    print("\n[SUCCESS] SISTEMA LISTO Y DESPLEGADO!")

def main():
    args = build_parser().parse_args()

    # En Render no hay consola interactiva. En local, usar --yes o confirmar.
    is_render = os.environ.get("RENDER")

    if is_render or args.yes:
        seed_options = build_seed_options(args)
        reset_database(seed_options)
        return

    confirm = input("⚠️ ¿Borrar TODA la base de datos local? (s/n): ")
    if confirm.lower() == 's':
        seed_options = collect_seed_options_interactive(args)
        reset_database(seed_options)
    else:
        print("❌ Abortado.")


if __name__ == "__main__":
    main()
