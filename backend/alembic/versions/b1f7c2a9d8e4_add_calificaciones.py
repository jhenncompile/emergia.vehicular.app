"""Add workshop ratings.

Revision ID: b1f7c2a9d8e4
Revises: 8e3f2a5d1c4b
Create Date: 2026-06-07 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "b1f7c2a9d8e4"
down_revision: Union[str, None] = "8e3f2a5d1c4b"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _table_exists(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return table_name in inspector.get_table_names()


def _column_exists(table_name: str, column_name: str) -> bool:
    if not _table_exists(table_name):
        return False
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return any(column["name"] == column_name for column in inspector.get_columns(table_name))


def _index_exists(table_name: str, index_name: str) -> bool:
    if not _table_exists(table_name):
        return False
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return any(index["name"] == index_name for index in inspector.get_indexes(table_name))


def upgrade() -> None:
    if not _column_exists("taller", "calificacion_promedio"):
        op.add_column(
            "taller",
            sa.Column("calificacion_promedio", sa.Float(), nullable=True),
        )

    if not _table_exists("calificacion"):
        op.create_table(
            "calificacion",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("incidente_id", sa.Integer(), nullable=False),
            sa.Column("taller_id", sa.Integer(), nullable=False),
            sa.Column("usuario_id", sa.Integer(), nullable=False),
            sa.Column("puntuacion", sa.Integer(), nullable=False),
            sa.Column("comentario", sa.Text(), nullable=True),
            sa.Column("fecha_creacion", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
            sa.ForeignKeyConstraint(["incidente_id"], ["incidente.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["taller_id"], ["taller.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["usuario_id"], ["usuario.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("incidente_id"),
        )

    if not _index_exists("calificacion", "ix_calificacion_id"):
        op.create_index(op.f("ix_calificacion_id"), "calificacion", ["id"], unique=False)


def downgrade() -> None:
    if _index_exists("calificacion", "ix_calificacion_id"):
        op.drop_index(op.f("ix_calificacion_id"), table_name="calificacion")

    if _table_exists("calificacion"):
        op.drop_table("calificacion")

    if _column_exists("taller", "calificacion_promedio"):
        op.drop_column("taller", "calificacion_promedio")
