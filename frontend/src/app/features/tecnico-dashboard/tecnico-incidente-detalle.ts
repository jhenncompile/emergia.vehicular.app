import { Component, OnInit, OnDestroy, inject, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TecnicoService } from '../../core/services/tecnico';
import { AuthService } from '../../core/services/auth';
import { NotificacionContadorService } from '../../core/services/notificacion-contador.service';
import { WebSocketNotificacionService } from '../../core/services/websocket-notificacion.service';
import { Subscription } from 'rxjs';
import * as L from 'leaflet';


@Component({
  selector: 'app-tecnico-incidente-detalle',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './tecnico-incidente-detalle.html',
  styleUrls: ['./tecnico-incidente-detalle.css']
})
export class TecnicoIncidenteDetalleComponent implements OnInit, OnDestroy {
  private tecnicoService = inject(TecnicoService);
  private authService = inject(AuthService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  private cdr = inject(ChangeDetectorRef);
  private contadorNotificaciones = inject(NotificacionContadorService);
  public wsService = inject(WebSocketNotificacionService);
  private notificacionSub: Subscription | null = null;
  private contadorSub: Subscription | null = null;

  incidente: any = null;
  cargando = true;
  mensaje = '';
  nombre = '';
  notificacionesNoLeidas = 0;
  mapa: L.Map | null = null;
  private mapaTimeoutId: ReturnType<typeof setTimeout> | null = null;

  ngOnInit() {
    // Configurar iconos de Leaflet usando URLs públicas
    const baseUrl = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4';
    const defaultIcon = L.icon({
      iconRetinaUrl: baseUrl + '/images/marker-icon-2x.png',
      iconUrl: baseUrl + '/images/marker-icon.png',
      shadowUrl: baseUrl + '/images/marker-shadow.png',
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      shadowSize: [41, 41]
    });
    L.Marker.prototype.setIcon(defaultIcon);

    this.nombre = this.authService.getNombre();
    this.cargarIncidente();
    this.contadorSub = this.contadorNotificaciones.noLeidas$.subscribe((cantidad) => {
      this.notificacionesNoLeidas = cantidad;
      this.cdr.detectChanges();
    });
    this.contadorNotificaciones.cargarPendientes();
    
    // Conectar WebSocket para recibir actualizaciones en tiempo real
    const usuarioId = localStorage.getItem('usuario_id');
    if (usuarioId) {
      this.wsService.conectar(parseInt(usuarioId));
      
      // Escuchar notificaciones y recargar datos si cambian
      this.notificacionSub = this.wsService.notificaciones$.subscribe(notif => {
        if (notif) {
          // Recargar datos del incidente
          this.cargarIncidente();
          this.contadorNotificaciones.cargarPendientes();
        }
      });
    }
  }

  ngOnDestroy() {
    // Desconectar WebSocket al salir
    if (this.notificacionSub) {
      this.notificacionSub.unsubscribe();
    }
    this.contadorSub?.unsubscribe();
    this.wsService.desconectar();
    if (this.mapaTimeoutId) {
      clearTimeout(this.mapaTimeoutId);
      this.mapaTimeoutId = null;
    }
    // Remover mapa
    if (this.mapa) {
      this.mapa.remove();
    }
  }

  cargarIncidente() {
    const id = this.route.snapshot.paramMap.get('id');
    if (!id) {
      this.mensaje = 'ID de incidente no válido ❌';
      return;
    }

    this.tecnicoService.getIncidente(parseInt(id)).subscribe({
      next: (data) => {
        this.incidente = data;
        this.cargando = false;
        this.cdr.detectChanges();
        // Inicializar mapa después de cargar datos y que se renderice el DOM
        if (this.mapaTimeoutId) {
          clearTimeout(this.mapaTimeoutId);
        }
        this.mapaTimeoutId = setTimeout(() => this.inicializarMapa(), 500);
      },
      error: (err) => {
        console.error('Error al cargar incidente:', err);
        this.mensaje = 'Error al cargar el incidente ❌';
        this.cargando = false;
        this.cdr.detectChanges();
      }
    });
  }

  inicializarMapa() {
    if (!this.incidente?.taller?.latitud || !this.incidente?.taller?.longitud) {
      console.warn('No hay coordenadas del taller');
      return;
    }

    const elementoMapa = document.getElementById('mapa');
    if (!elementoMapa) {
      console.warn('Elemento mapa no encontrado en el DOM');
      return;
    }

    // Evitar inicializar múltiples veces
    if (this.mapa) {
      this.mapa.remove();
    }

    const lat = parseFloat(this.incidente.taller.latitud as any);
    const lng = parseFloat(this.incidente.taller.longitud as any);

    try {
      this.mapa = L.map('mapa', { 
        center: [lat, lng],
        zoom: 15
      });

      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors',
        maxZoom: 19
      }).addTo(this.mapa);

      // Agregar marcador
      const marker = L.marker([lat, lng]).addTo(this.mapa);
      marker.bindPopup(`<b>${this.incidente.taller.nombre || 'Taller'}</b>`);
    } catch (error) {
      console.error('Error al inicializar mapa:', error);
    }
  }

  getEstadoClass(estado: string): string {
    const estadoMap: { [key: string]: string } = {
      'pendiente': 'estado-pendiente',
      'buscando_taller': 'estado-pendiente',
      'asignado_taller': 'estado-en-proceso',
      'en_camino': 'estado-en-proceso',
      'en_atencion': 'estado-atendido',
      'finalizado': 'estado-atendido',
      'completado': 'estado-completado',
      'cancelado': 'estado-cancelado'
    };
    return estadoMap[estado?.toLowerCase()] || 'estado-pendiente';
  }

  getPrioridadClass(prioridad: string): string {
    const prioridadMap: { [key: string]: string } = {
      'baja': 'prioridad-baja',
      'media': 'prioridad-media',
      'alta': 'prioridad-alta'
    };
    return prioridadMap[prioridad?.toLowerCase()] || 'prioridad-media';
  }

  volver() {
    this.router.navigate(['/tecnico/dashboard']);
  }

  salir() {
    this.contadorNotificaciones.limpiar();
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}
