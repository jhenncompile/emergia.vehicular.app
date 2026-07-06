from pydantic import BaseModel
from typing import Optional, List


class ChatRequest(BaseModel):
    # Nodo actual de la conversacion (None => inicia una nueva).
    nodo: Optional[str] = None
    # Opcion elegida por el usuario dentro del nodo actual.
    opcion: Optional[str] = None


class ChatOpcion(BaseModel):
    id: str
    texto: str


class ChatResponse(BaseModel):
    nodo: str
    mensaje: str
    es_final: bool
    opciones: List[ChatOpcion]
