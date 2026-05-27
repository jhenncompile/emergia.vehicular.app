import { Component, OnInit, inject, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { TecnicoService } from '../../core/services/tecnico';
import { AuthService } from '../../core/services/auth';
import * as L from 'leaflet';
import 'leaflet/dist/leaflet.css';

@Component({
  selector: 'app-tecnico-incidente-detalle',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './tecnico-incidente-detalle.html',
  styleUrls: ['./tecnico-incidente-detalle.css']
})
export class TecnicoIncidenteDetalleComponent implements OnInit {
  private tecnicoService = inject(TecnicoService);
  private authService = inject(AuthService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  private cdr = inject(ChangeDetectorRef);

  incidente: any = null;
  cargando = true;
  mensaje = '';
  nombre = '';
  mapa: L.Map | null = null;

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
  }

  cargarIncidente() {
    const id = this.route.snapshot.paramMap.get('id');
    if (!id) {
      this.mensaje = 'ID de incidente no válido ❌';
      return;
    }

    this.tecnicoService.getIncidente(parseInt(id)).subscribe({
      next: (data) => {
        console.log('=== DATOS RECIBIDOS DEL API ===');
        console.log('Incidente completo:', data);
        console.log('Usuario:', data?.usuario);
        console.log('Taller:', data?.taller);
        console.log('Vehículo:', data?.vehiculo);
        console.log('Técnico:', data?.tecnico);
        this.incidente = data;
        this.cargando = false;
        this.cdr.detectChanges();
        // Inicializar mapa después de cargar datos y que se renderice el DOM
        setTimeout(() => this.inicializarMapa(), 500);
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

    console.log('Inicializando Leaflet');
    console.log('Elemento mapa encontrado:', elementoMapa);
    console.log('Dimensiones del elemento:', elementoMapa.offsetWidth, 'x', elementoMapa.offsetHeight);

    // Evitar inicializar múltiples veces
    if (this.mapa) {
      this.mapa.remove();
    }

    const lat = parseFloat(this.incidente.taller.latitud as any);
    const lng = parseFloat(this.incidente.taller.longitud as any);

    console.log('Coordenadas:', lat, lng);

    try {
      this.mapa = L.map('mapa', { 
        center: [lat, lng],
        zoom: 15
      });

      console.log('L.map inicializado:', this.mapa);

      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors',
        maxZoom: 19
      }).addTo(this.mapa);

      console.log('Tile layer agregado');

      // Agregar marcador
      const marker = L.marker([lat, lng]).addTo(this.mapa);
      marker.bindPopup(`<b>${this.incidente.taller.nombre || 'Taller'}</b>`);

      console.log('Marcador agregado');
      console.log('Mapa inicializado correctamente');
    } catch (error) {
      console.error('Error al inicializar mapa:', error);
    }
  }

  getEstadoClass(estado: string): string {
    const estadoMap: { [key: string]: string } = {
      'pendiente': 'estado-pendiente',
      'en_proceso': 'estado-en-proceso',
      'en-proceso': 'estado-en-proceso',
      'rechazado': 'estado-rechazado',
      'atendido': 'estado-atendido',
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
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}
