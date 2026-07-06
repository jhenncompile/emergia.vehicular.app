"""
Servicio del Assistant.

Aisla al endpoint del motor concreto que resuelve la conversacion. Hoy usa el
arbol de decisiones estatico (`decision_tree`); en el futuro se puede cambiar la
implementacion interna por un motor de IA sin modificar el endpoint ni el cliente
movil, siempre que `responder` conserve el mismo contrato de entrada/salida.
"""

from typing import Optional, Dict, Any

from app.services.assistant import decision_tree


class AssistantService:
    def responder(self, nodo: Optional[str] = None, opcion: Optional[str] = None) -> Dict[str, Any]:
        """Devuelve el siguiente paso de la conversacion en un formato plano."""
        nodo_id, nodo_data = decision_tree.resolver_nodo(nodo_actual=nodo, opcion=opcion)

        return {
            "nodo": nodo_id,
            "mensaje": nodo_data["mensaje"],
            "es_final": nodo_data["es_final"],
            "opciones": [
                {"id": op["id"], "texto": op["texto"]}
                for op in nodo_data["opciones"]
            ],
        }


assistant_service = AssistantService()
