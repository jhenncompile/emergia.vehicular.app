"""Expand bitacora accion length

Revision ID: c7e4a9b2f610
Revises: af91898a4109
Create Date: 2026-06-08 03:38:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "c7e4a9b2f610"
down_revision: Union[str, Sequence[str], None] = "af91898a4109"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table("bitacora") as batch_op:
        batch_op.alter_column(
            "accion",
            existing_type=sa.String(length=20),
            type_=sa.String(length=50),
            existing_nullable=True,
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table("bitacora") as batch_op:
        batch_op.alter_column(
            "accion",
            existing_type=sa.String(length=50),
            type_=sa.String(length=20),
            existing_nullable=True,
        )
