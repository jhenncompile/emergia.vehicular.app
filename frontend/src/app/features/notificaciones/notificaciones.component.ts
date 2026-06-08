import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FirebaseService } from '../../core/services/firebase.service';
import { Subject } from 'rxjs';
import { takeUntil } from 'rxjs/operators';
import { NotificacionContadorService } from '../../core/services/notificacion-contador.service';

interface Notificacion {
  id: number;
  tipo: string;
  timestamp: string;
  incidente: {
    id: number;
    placa_vehiculo: string;
    latitud: number;
    longitud: number;
    distancia_km: number;
    clasificacion: string;
    estado: string;
    taller_nombre: string;
  };
}

@Component({
  selector: 'app-notificaciones',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="notificaciones-container">
      <div *ngIf="notificacionActiva" class="notificacion-toast" [ngClass]="notificacionActiva.tipo">
        <div class="notificacion-header">
          <span class="icono">🚨</span>
          <span class="titulo">Incidente Cercano</span>
          <button class="btn-cerrar" (click)="cerrarNotificacion()">✕</button>
        </div>
        <div class="notificacion-content">
          <p><strong>Vehículo:</strong> {{ notificacionActiva.incidente.placa_vehiculo }}</p>
          <p><strong>Problema:</strong> {{ notificacionActiva.incidente.clasificacion }}</p>
          <p><strong>Distancia:</strong> <span class="distancia">{{ notificacionActiva.incidente.distancia_km }} km</span></p>
          <p><strong>Ubicación:</strong> ({{ notificacionActiva.incidente.latitud | number:'1.4-4' }}, {{ notificacionActiva.incidente.longitud | number:'1.4-4' }})</p>
        </div>
        <div class="notificacion-acciones">
          <button class="btn-ver" (click)="verEnMapa()">Ver en Mapa 🗺️</button>
          <button class="btn-aceptar" (click)="aceptarIncidente()">Aceptar 📍</button>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .notificaciones-container {
      position: fixed;
      top: 20px;
      right: 20px;
      z-index: 1000;
      max-width: 400px;
    }

    .notificacion-toast {
      background: white;
      border-radius: 8px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
      padding: 1rem;
      margin-bottom: 1rem;
      border-left: 4px solid #ef4444;
      animation: slideIn 0.3s ease-in-out;
    }

    @keyframes slideIn {
      from {
        transform: translateX(420px);
        opacity: 0;
      }
      to {
        transform: translateX(0);
        opacity: 1;
      }
    }

    .notificacion-header {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      margin-bottom: 0.75rem;
      border-bottom: 1px solid #e5e7eb;
      padding-bottom: 0.5rem;
    }

    .icono {
      font-size: 1.5rem;
    }

    .titulo {
      flex: 1;
      font-weight: 600;
      color: #0f172a;
    }

    .btn-cerrar {
      background: none;
      border: none;
      cursor: pointer;
      font-size: 1.2rem;
      color: #6b7280;
      padding: 0;
    }

    .btn-cerrar:hover {
      color: #1f2937;
    }

    .notificacion-content {
      margin: 0.75rem 0;
      font-size: 0.9rem;
      color: #475569;
    }

    .notificacion-content p {
      margin: 0.4rem 0;
    }

    .distancia {
      background: #fef3c7;
      padding: 0.2rem 0.4rem;
      border-radius: 4px;
      font-weight: 600;
      color: #92400e;
    }

    .notificacion-acciones {
      display: flex;
      gap: 0.5rem;
      margin-top: 0.75rem;
    }

    .btn-ver, .btn-aceptar {
      flex: 1;
      padding: 0.6rem;
      border: none;
      border-radius: 6px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
      font-size: 0.85rem;
    }

    .btn-ver {
      background: #3b82f6;
      color: white;
    }

    .btn-ver:hover {
      background: #2563eb;
    }

    .btn-aceptar {
      background: #10b981;
      color: white;
    }

    .btn-aceptar:hover {
      background: #059669;
    }
  `]
})
export class NotificacionesComponent implements OnInit, OnDestroy {
  private firebaseService = inject(FirebaseService);
  private destroy$ = new Subject<void>();
  
  notificacionActiva: Notificacion | null = null;
  private autoDismissTimer: any;

  ngOnInit() {
    // Escuchar notificaciones de Firebase
    this.firebaseService.notificaciones$
      .pipe(takeUntil(this.destroy$))
      .subscribe((notificacion: any) => {
        if (notificacion && notificacion.tipo === 'notificacion') {
          this.mostrarNotificacion(notificacion);
        }
      });
  }

  private mostrarNotificacion(notificacion: Notificacion) {
    this.notificacionActiva = notificacion;
    
    // Auto-descartar después de 10 segundos
    if (this.autoDismissTimer) {
      clearTimeout(this.autoDismissTimer);
    }
    this.autoDismissTimer = setTimeout(() => {
      this.cerrarNotificacion();
    }, 10000);
  }

  private contadorNotificaciones = inject(NotificacionContadorService);
  
  cerrarNotificacion() {
    if (this.notificacionActiva) {
      this.contadorNotificaciones.marcarLeida(this.notificacionActiva.id).subscribe(() => {
        this.contadorNotificaciones.refrescar();
      });
    }
    this.notificacionActiva = null;
    if (this.autoDismissTimer) {
      clearTimeout(this.autoDismissTimer);
    }
  }

  verEnMapa() {
    if (this.notificacionActiva) {
      const { latitud, longitud } = this.notificacionActiva.incidente;
      // Abrir Google Maps
      window.open(
        `https://www.google.com/maps/@${latitud},${longitud},15z`,
        '_blank'
      );
    }
  }

  aceptarIncidente() {
    if (this.notificacionActiva) {
      console.log('Aceptar incidente:', this.notificacionActiva.incidente.id);
      // Aquí irá la lógica para aceptar el incidente
      this.cerrarNotificacion();
    }
  }

  ngOnDestroy() {
    this.destroy$.next();
    this.destroy$.complete();
  }
}
