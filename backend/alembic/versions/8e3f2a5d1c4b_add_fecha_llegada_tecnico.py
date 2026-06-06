"""Add fecha_llegada_tecnico column to incidente table.

Revision ID: 8e3f2a5d1c4b
Revises: 7d2f9a1c6b30
Create Date: 2026-06-05 10:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "8e3f2a5d1c4b"
down_revision: Union[str, None] = "7d2f9a1c6b30"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _column_exists(table_name: str, column_name: str) -> bool:
    """Verificar si una columna ya existe."""
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return any(column["name"] == column_name for column in inspector.get_columns(table_name))


def upgrade() -> None:
    """Agregar columna fecha_llegada_tecnico."""
    if not _column_exists("incidente", "fecha_llegada_tecnico"):
        op.add_column(
            "incidente",
            sa.Column("fecha_llegada_tecnico", sa.DateTime(timezone=True), nullable=True)
        )


def downgrade() -> None:
    """Remover columna fecha_llegada_tecnico."""
    if _column_exists("incidente", "fecha_llegada_tecnico"):
        op.drop_column("incidente", "fecha_llegada_tecnico")
