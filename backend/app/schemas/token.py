from typing import Optional
from pydantic import BaseModel

class Token(BaseModel):
    access_token: str
    token_type: str
    rol_id: int  # 1=Admin, 2=Cliente, 3=Técnico
    usuario_id: int
    nombre: str

class TokenPayload(BaseModel):
    sub: Optional[int] = None