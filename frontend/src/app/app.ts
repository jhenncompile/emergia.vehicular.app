import { Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from './core/services/auth';
import { ToastComponent } from './shared/components/toast/toast';
import { ToastService } from './core/services/toast.service';
import { WebSocketNotificacionService } from './core/services/websocket-notificacion.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, CommonModule, ToastComponent],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App {
  // Inyectamos el servicio para que el HTML sepa si mostrar el menú o no
  public authService = inject(AuthService);
  private toastService = inject(ToastService);
  private wsNotificacionService = inject(WebSocketNotificacionService);

  constructor() {
    this.wsNotificacionService.notificaciones$.subscribe(noti => {
      // Mostrar toast en cada notificación
      this.toastService.show(noti.titulo || 'Notificación', noti.mensaje || 'Tienes una nueva notificación', 'info');
    });
  }
}