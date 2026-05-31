"""Add intelligent workshop assignment tables.

Revision ID: 4f6a8b2c9d01
Revises: 2c8e6f4a1b3d
Create Date: 2026-05-30 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "4f6a8b2c9d01"
down_revision: Union[str, None] = "2c8e6f4a1b3d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "categoria_incidente",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("nombre", sa.String(length=100), nullable=False),
        sa.Column("descripcion", sa.Text(), nullable=True),
        sa.Column("prioridad_default", sa.String(length=20), nullable=False),
        sa.Column("activa", sa.Boolean(), nullable=False),
        sa.Column(
            "fecha_creacion",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("nombre"),
    )
    op.create_index(
        op.f("ix_categoria_incidente_id"),
        "categoria_incidente",
        ["id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_categoria_incidente_nombre"),
        "categoria_incidente",
        ["nombre"],
        unique=False,
    )

    op.create_table(
        "categoria_especialidad",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("categoria_id", sa.Integer(), nullable=False),
        sa.Column("especialidad_id", sa.Integer(), nullable=False),
        sa.Column("peso", sa.Float(), nullable=False),
        sa.Column("es_obligatoria", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(
            ["categoria_id"],
            ["categoria_incidente.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["especialidad_id"],
            ["especialidad.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "categoria_id",
            "especialidad_id",
            name="uq_categoria_especialidad",
        ),
    )
    op.create_index(
        op.f("ix_categoria_especialidad_id"),
        "categoria_especialidad",
        ["id"],
        unique=False,
    )

    op.create_table(
        "incidente_asignacion_candidato",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("incidente_id", sa.Integer(), nullable=False),
        sa.Column("taller_id", sa.Integer(), nullable=False),
        sa.Column("orden", sa.Integer(), nullable=False),
        sa.Column("score_total", sa.Float(), nullable=False),
        sa.Column("score_distancia", sa.Float(), nullable=False),
        sa.Column("score_especialidad", sa.Float(), nullable=False),
        sa.Column("score_disponibilidad", sa.Float(), nullable=False),
        sa.Column("estado", sa.String(length=20), nullable=False),
        sa.Column("explicacion", sa.Text(), nullable=True),
        sa.Column(
            "fecha_creacion",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.Column("fecha_oferta", sa.DateTime(timezone=True), nullable=True),
        sa.Column("fecha_respuesta", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expira_en", sa.DateTime(timezone=True), nullable=True),
        sa.Column("motivo_rechazo", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["incidente_id"], ["incidente.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["taller_id"], ["taller.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "incidente_id",
            "taller_id",
            name="uq_incidente_taller_candidato",
        ),
    )
    op.create_index(
        op.f("ix_incidente_asignacion_candidato_estado"),
        "incidente_asignacion_candidato",
        ["estado"],
        unique=False,
    )
    op.create_index(
        op.f("ix_incidente_asignacion_candidato_id"),
        "incidente_asignacion_candidato",
        ["id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_incidente_asignacion_candidato_incidente_id"),
        "incidente_asignacion_candidato",
        ["incidente_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_incidente_asignacion_candidato_taller_id"),
        "incidente_asignacion_candidato",
        ["taller_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_incidente_asignacion_candidato_taller_id"),
        table_name="incidente_asignacion_candidato",
    )
    op.drop_index(
        op.f("ix_incidente_asignacion_candidato_incidente_id"),
        table_name="incidente_asignacion_candidato",
    )
    op.drop_index(
        op.f("ix_incidente_asignacion_candidato_id"),
        table_name="incidente_asignacion_candidato",
    )
    op.drop_index(
        op.f("ix_incidente_asignacion_candidato_estado"),
        table_name="incidente_asignacion_candidato",
    )
    op.drop_table("incidente_asignacion_candidato")
    op.drop_index(op.f("ix_categoria_especialidad_id"), table_name="categoria_especialidad")
    op.drop_table("categoria_especialidad")
    op.drop_index(op.f("ix_categoria_incidente_nombre"), table_name="categoria_incidente")
    op.drop_index(op.f("ix_categoria_incidente_id"), table_name="categoria_incidente")
    op.drop_table("categoria_incidente")
