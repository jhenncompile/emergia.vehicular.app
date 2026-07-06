from fastapi import APIRouter

from app.schemas.assistant import ChatRequest, ChatResponse
from app.services.assistant.assistant_service import assistant_service

router = APIRouter()


@router.post("/chat", response_model=ChatResponse)
def chat(payload: ChatRequest):
    """Assistant de recomendaciones de seguridad basado en un arbol de decisiones.

    Es completamente stateless: no consulta ni almacena datos en la base de datos.
    El cliente envia el nodo actual y la opcion elegida, y recibe el siguiente paso.
    """
    return assistant_service.responder(nodo=payload.nodo, opcion=payload.opcion)
