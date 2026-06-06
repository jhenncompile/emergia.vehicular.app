

export interface TecnicoInfo {
  id: number;
  nombre: string;
}

export interface VehiculoInfo {
  id: number;
  placa: string;
  marca: string;
  modelo: string;
}

export interface Incidente {
  id: number;
  vehiculo_id: number;
  usuario_id: number;
  taller_id?: number;
  tecnico_id?: number;
  latitud: number;
  longitud: number;
  prioridad: string;
  estado: string;
  pago_estado: string;
  telefono_cliente?: string;
  motivo_cancelacion?: string;
  cancelado_por?: string;
  tiempo_asignacion_segundos?: number;
  transcripcion_audio?: string;
  clasificacion_ia?: string;
  resumen_ia?: string;
  fecha_creacion?: string;       // Campo vital para el historial
  tecnico?: TecnicoInfo;          // Relación para mostrar quién atendió
  vehiculo?: VehiculoInfo;        // 🚗 Información del vehículo
  pagos?: any;                    // Relación con pagos (monto cobrado)
  distancia_metros?: number;      // 📏 Distancia al taller en metros
  descargando?: boolean;
}
