"""
Arbol de decisiones estatico del Assistant.

Contiene UNICAMENTE los datos del arbol (nodos y opciones) y la funcion pura
para navegarlo. No conoce FastAPI ni la base de datos. En el futuro este modulo
puede reemplazarse por un motor basado en IA sin tocar el endpoint ni el cliente
movil, siempre que se respete el contrato de `resolver_nodo`.

Estructura de un nodo:
    {
        "mensaje": str,                # texto que muestra el Assistant
        "es_final": bool,              # True cuando el flujo llego a su fin
        "opciones": [                  # opciones que puede elegir el usuario
            {"id": str, "texto": str, "siguiente": str},  # 'siguiente' = id de nodo
        ],
    }
"""

NODO_INICIAL = "inicio"

_CIERRE = "Mantente en un lugar seguro y espera la asistencia del taller."

DECISION_TREE = {
    "inicio": {
        "mensaje": (
            "Hola, soy tu asistente. Mientras llega la ayuda, cuentame: "
            "¿que problema tienes?"
        ),
        "es_final": False,
        "opciones": [
            {"id": "llanta_pinchada", "texto": "Llanta pinchada", "siguiente": "llanta_pinchada"},
            {"id": "bateria_descargada", "texto": "Bateria descargada", "siguiente": "bateria_descargada"},
            {"id": "accidente", "texto": "Accidente", "siguiente": "accidente"},
            {"id": "sobrecalentamiento", "texto": "Sobrecalentamiento del motor", "siguiente": "sobrecalentamiento"},
            {"id": "otro", "texto": "Otro problema", "siguiente": "otro"},
        ],
    },
    "llanta_pinchada": {
        "mensaje": (
            "Llanta pinchada. Recomendaciones de seguridad:\n"
            "1. Reduce la velocidad y orillate en un lugar plano y seguro.\n"
            "2. Enciende las luces intermitentes de emergencia.\n"
            "3. Coloca el triangulo de seguridad a varios metros del vehiculo.\n"
            "4. No cambies la llanta si estas en una via de alto trafico.\n"
            f"{_CIERRE}"
        ),
        "es_final": True,
        "opciones": [
            {"id": "volver", "texto": "Volver al inicio", "siguiente": "inicio"},
        ],
    },
    "bateria_descargada": {
        "mensaje": (
            "Bateria descargada. Recomendaciones de seguridad:\n"
            "1. Apaga luces, radio y aire acondicionado.\n"
            "2. Verifica que el vehiculo este en un lugar seguro y frenado.\n"
            "3. Si intentas un puente de corriente, hazlo solo si conoces el procedimiento.\n"
            "4. No manipules los bornes con las manos humedas.\n"
            f"{_CIERRE}"
        ),
        "es_final": True,
        "opciones": [
            {"id": "volver", "texto": "Volver al inicio", "siguiente": "inicio"},
        ],
    },
    "accidente": {
        "mensaje": (
            "Accidente. Recomendaciones de seguridad:\n"
            "1. Conserva la calma y verifica si hay personas heridas.\n"
            "2. Si hay heridos graves, llama de inmediato a los servicios de emergencia.\n"
            "3. Enciende las intermitentes y senaliza la zona del accidente.\n"
            "4. Si es posible y seguro, muevete fuera de la via de circulacion.\n"
            f"{_CIERRE}"
        ),
        "es_final": True,
        "opciones": [
            {"id": "volver", "texto": "Volver al inicio", "siguiente": "inicio"},
        ],
    },
    "sobrecalentamiento": {
        "mensaje": (
            "Sobrecalentamiento del motor. Recomendaciones de seguridad:\n"
            "1. Orillate y apaga el motor lo antes posible.\n"
            "2. No abras el tapon del radiador con el motor caliente.\n"
            "3. Espera a que el motor se enfrie antes de revisar el refrigerante.\n"
            "4. No continues conduciendo para evitar danos mayores.\n"
            f"{_CIERRE}"
        ),
        "es_final": True,
        "opciones": [
            {"id": "volver", "texto": "Volver al inicio", "siguiente": "inicio"},
        ],
    },
    "otro": {
        "mensaje": (
            "Entendido. Recomendaciones generales de seguridad:\n"
            "1. Orillate en un lugar seguro y enciende las intermitentes.\n"
            "2. Senaliza el vehiculo con el triangulo de seguridad.\n"
            "3. Permanece dentro del vehiculo si estas en una via peligrosa.\n"
            "4. Ten a la mano los datos de tu ubicacion para la asistencia.\n"
            f"{_CIERRE}"
        ),
        "es_final": True,
        "opciones": [
            {"id": "volver", "texto": "Volver al inicio", "siguiente": "inicio"},
        ],
    },
}


def resolver_nodo(nodo_actual=None, opcion=None):
    """Navega el arbol de forma pura y devuelve el nodo resultante.

    - Sin `nodo_actual`: devuelve el nodo inicial.
    - Con `nodo_actual` y `opcion`: sigue la opcion elegida hacia el siguiente nodo.
    - Si la opcion no es valida, se mantiene en el nodo actual.

    Devuelve una tupla (id_nodo, nodo).
    """
    if not nodo_actual or nodo_actual not in DECISION_TREE:
        return NODO_INICIAL, DECISION_TREE[NODO_INICIAL]

    nodo = DECISION_TREE[nodo_actual]

    if opcion:
        for op in nodo["opciones"]:
            if op["id"] == opcion:
                siguiente = op["siguiente"]
                if siguiente in DECISION_TREE:
                    return siguiente, DECISION_TREE[siguiente]
                break

    return nodo_actual, nodo
