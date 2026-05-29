import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Router } from '@angular/router';
import { Subscription } from 'rxjs';
import { environment } from '../../../environments/environment';
import { NotificacionContadorService } from '../../core/services/notificacion-contador.service';
import { WebSocketNotificacionService } from '../../core/services/websocket-notificacion.service';

export interface Notificacion {
  id: number;
  titulo: string;
  mensaje: string;
  tipo: string;
  leido: boolean;
  fecha_envio: string;
  incidente_id?: number;
}

@Component({
  selector: 'app-notificaciones',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './notificaciones.html',
  styleUrl: './notificaciones.css'
})
export class NotificacionesComponent implements OnInit, OnDestroy {
  private http = inject(HttpClient);
  private router = inject(Router);
  private contadorNotificaciones = inject(NotificacionContadorService);
  private wsService = inject(WebSocketNotificacionService);
  private notificacionSub: Subscription | null = null;
  
  public notificaciones: Notificacion[] = [];
  public cargando = true;
  public esTecnico = localStorage.getItem('rol_id') === '3';

  private getHeaders() {
    const token = localStorage.getItem('token');
    return new HttpHeaders().set('Authorization', `Bearer ${token}`);
  }

  ngOnInit() {
    this.conectarWebSocket();
    this.cargarHistorial();
    this.notificacionSub = this.wsService.notificaciones$.subscribe((notif) => {
      if (notif) {
        this.agregarNotificacionReciente(notif);
      }
    });
  }

  ngOnDestroy() {
    this.notificacionSub?.unsubscribe();
  }

  cargarHistorial() {
    const userId = localStorage.getItem('usuario_id');
    if (!userId) {
      console.error('usuario_id no encontrado en localStorage');
      this.cargando = false;
      return;
    }

    // Llamamos al nuevo endpoint que trae TODAS (leídas y no leídas)
    this.http.get<Notificacion[]>(`${environment.apiUrl}/notificaciones/usuario/${userId}/historial`, { headers: this.getHeaders() })
      .subscribe({
        next: (data) => {
          this.notificaciones = data;
          this.contadorNotificaciones.cargarPendientes();
          this.cargando = false;
        },
        error: (err) => {
          console.error("Error cargando notificaciones", err);
          this.cargando = false;
        }
      });
  }

  marcarComoLeida(id: number) {
    const estabaNoLeida = this.notificaciones.some(noti => noti.id === id && !noti.leido);

    // 🚩 OPTIMISTIC UI: Actualizamos visualmente primero
    this.notificaciones = this.notificaciones.map(noti => 
      noti.id === id ? { ...noti, leido: true } : noti
    );
    if (estabaNoLeida) {
      this.contadorNotificaciones.descontarUna();
    }

    // Confirmamos con el Backend
    this.http.patch(`${environment.apiUrl}/notificaciones/${id}/leer`, {}, { headers: this.getHeaders() })
      .subscribe({
        next: () => this.contadorNotificaciones.cargarPendientes(),
        error: () => {
          this.cargarHistorial();
          this.contadorNotificaciones.cargarPendientes();
        }
      });
  }

  volver() {
    this.router.navigate([this.esTecnico ? '/tecnico/dashboard' : '/dashboard']);
  }

  private conectarWebSocket() {
    const usuarioId = Number(localStorage.getItem('usuario_id'));
    if (Number.isFinite(usuarioId) && usuarioId > 0) {
      this.wsService.conectar(usuarioId);
    }
  }

  private agregarNotificacionReciente(notif: Partial<Notificacion>) {
    if (!notif.id || this.notificaciones.some((n) => n.id === notif.id)) {
      return;
    }

    this.notificaciones = [{
      id: notif.id,
      titulo: notif.titulo || 'Nueva notificación',
      mensaje: notif.mensaje || '',
      tipo: notif.tipo || 'sistema',
      leido: false,
      fecha_envio: notif.fecha_envio || new Date().toISOString(),
      incidente_id: notif.incidente_id
    }, ...this.notificaciones];
    this.contadorNotificaciones.cargarPendientes();
  }
}
