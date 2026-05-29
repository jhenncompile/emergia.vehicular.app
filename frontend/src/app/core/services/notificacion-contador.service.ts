import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { BehaviorSubject } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class NotificacionContadorService {
  private http = inject(HttpClient);
  private noLeidasSubject = new BehaviorSubject<number>(0);

  public noLeidas$ = this.noLeidasSubject.asObservable();

  cargarPendientes() {
    const usuarioId = localStorage.getItem('usuario_id');
    const token = localStorage.getItem('token');

    if (!usuarioId || !token) {
      this.noLeidasSubject.next(0);
      return;
    }

    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);

    this.http.get<any[]>(`${environment.apiUrl}/notificaciones/usuario/${usuarioId}/pendientes`, { headers })
      .subscribe({
        next: (notificaciones) => {
          this.noLeidasSubject.next(notificaciones.length);
        },
        error: (err) => {
          console.error('Error cargando contador de notificaciones:', err);
        }
      });
  }

  descontarUna() {
    this.noLeidasSubject.next(Math.max(0, this.noLeidasSubject.value - 1));
  }

  limpiar() {
    this.noLeidasSubject.next(0);
  }
}
