import { Component, Input, OnInit, OnDestroy, inject, NgZone, AfterViewInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import * as L from 'leaflet';
import { WebSocketNotificacionService } from '../../../core/services/websocket-notificacion.service';
import { Subscription } from 'rxjs';

@Component({
  selector: 'app-mapa-tecnico',
  standalone: true,
  imports: [CommonModule],
  template: `<div id="mapa-tecnico-container" class="map-container"></div>`,
  styles: [`
    .map-container {
      height: 300px;
      width: 100%;
      border-radius: 8px;
      margin-top: 10px;
      z-index: 1;
    }
  `]
})
export class MapaTecnicoComponent implements OnInit, AfterViewInit, OnDestroy {
  @Input() incidente: any;

  private wsService = inject(WebSocketNotificacionService);
  private ngZone = inject(NgZone);
  private sub: Subscription | null = null;

  private map: L.Map | null = null;
  private tecnicoMarker: L.Marker | null = null;
  private incidenteMarker: L.Marker | null = null;
  private routeLine: L.Polyline | null = null;

  ngOnInit() {
    this.sub = this.wsService.notificaciones$.subscribe((notificacion) => {
      if (notificacion.tipo === 'ubicacion_tecnico' && notificacion.incidente_id === this.incidente.id) {
        this.actualizarUbicacion(notificacion.latitud, notificacion.longitud);
      }
    });
  }

  ngAfterViewInit() {
    // Timeout to ensure the container is fully rendered and sized
    setTimeout(() => {
      this.initMap();
    }, 100);
  }

  private initMap() {
    const lat = Number(this.incidente.latitud);
    const lng = Number(this.incidente.longitud);
    
    this.map = L.map('mapa-tecnico-container').setView([lat, lng], 14);

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors'
    }).addTo(this.map);

    // Incidente Marker (Rojo)
    const redIcon = L.icon({
      iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-red.png',
      shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      shadowSize: [41, 41]
    });

    this.incidenteMarker = L.marker([lat, lng], { icon: redIcon })
      .addTo(this.map)
      .bindPopup('Ubicación del Incidente');
      
    // Fix default icon issue with Leaflet in Angular
    const iconDefault = L.icon({
      iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
      iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
      shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      tooltipAnchor: [16, -28],
      shadowSize: [41, 41]
    });
    L.Marker.prototype.options.icon = iconDefault;
  }

  private actualizarUbicacion(lat: number, lng: number) {
    if (!this.map) return;

    if (!this.tecnicoMarker) {
      // Create Technician Marker
      this.tecnicoMarker = L.marker([lat, lng])
        .addTo(this.map)
        .bindPopup('Técnico en camino');
        
      this.routeLine = L.polyline([
        [lat, lng],
        [Number(this.incidente.latitud), Number(this.incidente.longitud)]
      ], { color: 'blue' }).addTo(this.map);

      // Fit bounds
      this.map.fitBounds(this.routeLine.getBounds(), { padding: [50, 50] });
    } else {
      this.tecnicoMarker.setLatLng([lat, lng]);
      if (this.routeLine) {
        this.routeLine.setLatLngs([
          [lat, lng],
          [Number(this.incidente.latitud), Number(this.incidente.longitud)]
        ]);
      }
    }
  }

  ngOnDestroy() {
    if (this.sub) this.sub.unsubscribe();
    if (this.map) {
      this.map.remove();
    }
  }
}
