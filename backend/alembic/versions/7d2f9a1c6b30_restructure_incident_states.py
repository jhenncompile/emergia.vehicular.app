"""Restructure incident states.

Revision ID: 7d2f9a1c6b30
Revises: 4f6a8b2c9d01
Create Date: 2026-06-05 00:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "7d2f9a1c6b30"
down_revision: Union[str, None] = "4f6a8b2c9d01"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _column_exists(table_name: str, column_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return any(column["name"] == column_name for column in inspector.get_columns(table_name))


def upgrade() -> None:
    if not _column_exists("incidente", "cancelado_por"):
        op.add_column("incidente", sa.Column("cancelado_por", sa.String(length=20), nullable=True))
    if not _column_exists("incidente", "tiempo_asignacion_segundos"):
        op.add_column(
            "incidente",
            sa.Column("tiempo_asignacion_segundos", sa.Integer(), nullable=True),
        )

    op.execute(
        """
        UPDATE incidente
        SET estado = CASE
            WHEN estado = 'en_proceso' AND tecnico_id IS NULL THEN 'asignado_taller'
            WHEN estado = 'en_proceso' AND tecnico_id IS NOT NULL THEN 'en_camino'
            WHEN estado = 'atendido' AND pago_estado = 'pagado' THEN 'finalizado'
            WHEN estado = 'atendido' THEN 'en_atencion'
            WHEN estado = 'rechazado' THEN 'cancelado'
            ELSE estado
        END
        WHERE estado IN ('en_proceso', 'atendido', 'rechazado')
        """
    )
    op.execute(
        """
        UPDATE incidente
        SET cancelado_por = CASE
            WHEN cancelado_por IS NOT NULL THEN cancelado_por
            WHEN taller_id IS NOT NULL THEN 'taller'
            ELSE 'sistema'
        END
        WHERE estado = 'cancelado' AND cancelado_por IS NULL
        """
    )
    op.execute(
        """
        UPDATE incidente
        SET estado = 'buscando_taller'
        WHERE estado = 'pendiente'
          AND EXISTS (
              SELECT 1
              FROM incidente_asignacion_candidato c
              WHERE c.incidente_id = incidente.id
                AND c.estado = 'ofrecido'
          )
        """
    )


def downgrade() -> None:
    op.execute(
        """
        UPDATE incidente
        SET estado = CASE
            WHEN estado = 'buscando_taller' THEN 'pendiente'
            WHEN estado = 'asignado_taller' THEN 'en_proceso'
            WHEN estado = 'en_camino' THEN 'en_proceso'
            WHEN estado = 'en_atencion' THEN 'atendido'
            WHEN estado = 'finalizado' THEN 'atendido'
            ELSE estado
        END
        WHERE estado IN (
            'buscando_taller',
            'asignado_taller',
            'en_camino',
            'en_atencion',
            'finalizado'
        )
        """
    )
    if _column_exists("incidente", "tiempo_asignacion_segundos"):
        op.drop_column("incidente", "tiempo_asignacion_segundos")
    if _column_exists("incidente", "cancelado_por"):
        op.drop_column("incidente", "cancelado_por")

