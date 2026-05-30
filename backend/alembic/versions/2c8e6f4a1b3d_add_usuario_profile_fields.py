"""Add user profile fields.

Revision ID: 2c8e6f4a1b3d
Revises: 9b7c1d4e2a10
Create Date: 2026-05-30
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "2c8e6f4a1b3d"
down_revision: Union[str, None] = "9b7c1d4e2a10"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("usuario", sa.Column("apellido", sa.String(length=100), nullable=True))
    op.add_column("usuario", sa.Column("ciudad", sa.String(length=100), nullable=True))
    op.add_column("usuario", sa.Column("direccion", sa.String(length=200), nullable=True))


def downgrade() -> None:
    op.drop_column("usuario", "direccion")
    op.drop_column("usuario", "ciudad")
    op.drop_column("usuario", "apellido")
