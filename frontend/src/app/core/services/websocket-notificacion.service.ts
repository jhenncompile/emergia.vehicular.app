import { Injectable, OnDestroy, inject, NgZone } from '@angular/core';
import { Subject } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class WebSocketNotificacionService implements OnDestroy {
  private ngZone = inject(NgZone);
  
  private websocket: WebSocket | null = null;
  private notificacionesSubject = new Subject<any>();
  private heartbeatIntervalId: ReturnType<typeof setInterval> | null = null;
  private reconnectTimeoutId: ReturnType<typeof setTimeout> | null = null;
  private usuarioIdActual: number | null = null;
  private cierreManual = false;
  
  public notificaciones$ = this.notificacionesSubject.asObservable();
  public conectado = false;

  /**
   * Conecta al servidor WebSocket de notificaciones.
   * 
   * Debe llamarse desde el dashboard/layout principal para escuchar
   * notificaciones en tiempo real.
   * 
   * @param usuarioId ID del usuario autenticado
   */
  conectar(usuarioId: number) {
    if (!Number.isFinite(usuarioId)) {
      console.error('ID de usuario inválido para WebSocket:', usuarioId);
      return;
    }

    if (
      this.usuarioIdActual === usuarioId &&
      this.websocket &&
      (this.websocket.readyState === WebSocket.OPEN || this.websocket.readyState === WebSocket.CONNECTING)
    ) {
      return;
    }

    this.cierreManual = false;
    this.usuarioIdActual = usuarioId;
    this.limpiarReconexion();
    this.cerrarSocketActual();

    const conexionUrl = `${environment.wsUrl}/${usuarioId}`;

    this.ngZone.runOutsideAngular(() => {
      try {
        const socket = new WebSocket(conexionUrl);
        this.websocket = socket;
        
        socket.onopen = () => {
          this.ngZone.run(() => {
            this.conectado = true;
            this.iniciarHeartbeat();
          });
        };
        
        socket.onmessage = (event) => {
          this.ngZone.run(() => {
            try {
              // Ignorar heartbeat pong
              if (event.data === 'pong') {
                return;
              }
              
              const data = JSON.parse(event.data);
              this.notificacionesSubject.next(data);
            } catch (e) {
              console.error('Error parseando notificación WebSocket:', e);
            }
          });
        };
        
        socket.onerror = (event) => {
          this.ngZone.run(() => {
            console.error('❌ Error WebSocket:', event);
            this.conectado = false;
          });
        };
        
        socket.onclose = () => {
          this.ngZone.run(() => {
            if (this.websocket === socket) {
              this.websocket = null;
            }

            this.detenerHeartbeat();
            this.conectado = false;

            if (!this.cierreManual && this.usuarioIdActual === usuarioId) {
              this.reconnectTimeoutId = setTimeout(() => this.conectar(usuarioId), 5000);
            }
          });
        };
      } catch (error) {
        console.error('Error creando WebSocket:', error);
      }
    });
  }

  /**
   * Envía ping para mantener viva la conexión.
   */
  private iniciarHeartbeat() {
    this.detenerHeartbeat();

    this.ngZone.runOutsideAngular(() => {
      this.heartbeatIntervalId = setInterval(() => {
        if (this.websocket?.readyState === WebSocket.OPEN) {
          this.websocket.send('ping');
        }
      }, 30000);
    });
  }

  /**
   * Desconecta el WebSocket.
   */
  desconectar() {
    this.cierreManual = true;
    this.usuarioIdActual = null;
    this.limpiarReconexion();
    this.detenerHeartbeat();
    this.cerrarSocketActual();
    this.conectado = false;
  }

  /**
   * Retorna si el WebSocket está conectado.
   */
  isConectado(): boolean {
    return this.conectado;
  }

  /**
   * Envía un cambio de estado de incidente a otros clientes.
   */
  enviarCambioEstado(incidenteId: number, estado: string) {
    if (this.websocket?.readyState === WebSocket.OPEN) {
      this.websocket.send(JSON.stringify({
        tipo: 'cambio_estado',
        incidente_id: incidenteId,
        estado: estado
      }));
    }
  }

  ngOnDestroy() {
    this.desconectar();
  }

  private cerrarSocketActual() {
    if (!this.websocket) {
      return;
    }

    const socket = this.websocket;
    this.websocket = null;

    socket.onopen = null;
    socket.onmessage = null;
    socket.onerror = null;
    socket.onclose = null;

    if (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING) {
      socket.close();
    }
  }

  private detenerHeartbeat() {
    if (this.heartbeatIntervalId) {
      clearInterval(this.heartbeatIntervalId);
      this.heartbeatIntervalId = null;
    }
  }

  private limpiarReconexion() {
    if (this.reconnectTimeoutId) {
      clearTimeout(this.reconnectTimeoutId);
      this.reconnectTimeoutId = null;
    }
  }
}
