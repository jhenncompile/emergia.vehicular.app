import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, RouterLinkActive, Router } from '@angular/router';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Subscription } from 'rxjs';
import { environment } from '../../../../environments/environment';
import { AuthService } from '../../../core/services/auth';
import { NotificacionContadorService } from '../../../core/services/notificacion-contador.service';
import { WebSocketNotificacionService } from '../../../core/services/websocket-notificacion.service';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive],
  templateUrl: './sidebar.html',
  styleUrl: './sidebar.css'
})
export class SidebarComponent implements OnInit, OnDestroy {
  private http = inject(HttpClient);
  private router = inject(Router);
  private authService = inject(AuthService);
  private contadorNotificaciones = inject(NotificacionContadorService);
  public wsService = inject(WebSocketNotificacionService);
  private notificacionSub: Subscription | null = null;
  private contadorSub: Subscription | null = null;

  // 🚩 Variable que alimenta el HTML
  public usuario: string = 'Cargando...';
  public notificacionesNoLeidas: number = 0;

  ngOnInit() {
    this.cargarDatosUsuario();
    this.contadorSub = this.contadorNotificaciones.noLeidas$.subscribe((cantidad) => {
      this.notificacionesNoLeidas = cantidad;
    });
    this.contadorNotificaciones.cargarPendientes();
    this.notificacionSub = this.wsService.notificaciones$.subscribe(() => {
      this.contadorNotificaciones.cargarPendientes();
    });
  }

  ngOnDestroy() {
    this.notificacionSub?.unsubscribe();
    this.contadorSub?.unsubscribe();
  }

  cargarDatosUsuario() {
    const token = localStorage.getItem('token');
    
    // Si no hay token, no intentamos pedir el perfil
    if (!token) return;

    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);

    // Usamos el mismo endpoint que tu dashboard
    this.http.get<any>(`${environment.apiUrl}/usuarios/me`, { headers }).subscribe({
      next: (user) => {
        // Asignamos el nombre real (ej: "Angie")
        this.usuario = user.nombre;
      },
      error: () => {
        this.usuario = 'Administrador';
      }
    });
  }

  onLogout() {
    this.wsService.desconectar();
    this.contadorNotificaciones.limpiar();
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}
