"""Add incident description and location text fields.

Revision ID: 9b7c1d4e2a10
Revises: 44a9fa582453
Create Date: 2026-05-29 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "9b7c1d4e2a10"
down_revision: Union[str, Sequence[str], None] = "44a9fa582453"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("incidente", sa.Column("descripcion", sa.Text(), nullable=True))
    op.add_column("incidente", sa.Column("ubicacion", sa.String(length=255), nullable=True))
    op.add_column(
        "incidente",
        sa.Column("telefono_cliente", sa.String(length=20), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("incidente", "telefono_cliente")
    op.drop_column("incidente", "ubicacion")
    op.drop_column("incidente", "descripcion")
