import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterOutlet } from '@angular/router';
import { SidebarComponent } from '../../components/sidebar/sidebar';
import { WebSocketNotificacionService } from '../../../core/services/websocket-notificacion.service';

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [CommonModule, RouterOutlet, SidebarComponent],
  template: `
    <div class="layout-container">
      <app-sidebar></app-sidebar> 

      <main class="main-content">
        <div class="content-wrapper">
          <router-outlet></router-outlet>
        </div>
      </main>
    </div>
  `,
  styles: [`
    .layout-container {
      display: flex;
      min-height: 100vh;
      background-color: #f1f5f9; /* Color Slate 100 - Muy limpio */
    }

    .main-content {
      flex: 1;
      /* 🚩 EL TRUCO: Margen izquierdo igual al ancho del sidebar */
      margin-left: 260px; 
      height: 100vh;
      overflow-y: auto; /* Solo el contenido hace scroll, el sidebar queda fijo */
    }

    .content-wrapper {
      max-width: 1400px; /* Para que en pantallas gigantes no se estire infinito */
      margin: 0 auto;
      padding: 40px; /* Más aire para que se vea premium */
    }

    /* Ajuste para tablets/celulares */
    @media (max-width: 768px) {
      .main-content {
        margin-left: 0;
        padding: 20px;
      }
    }
  `]
})
export class MainLayoutComponent implements OnInit, OnDestroy {
  private wsService = inject(WebSocketNotificacionService);

  ngOnInit() {
    const usuarioId = Number(localStorage.getItem('usuario_id'));
    if (Number.isFinite(usuarioId) && usuarioId > 0) {
      this.wsService.conectar(usuarioId);
    }
  }

  ngOnDestroy() {
    this.wsService.desconectar();
  }
}
