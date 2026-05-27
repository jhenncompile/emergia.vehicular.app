import { Component, OnInit, inject, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { TecnicoService } from '../../core/services/tecnico';
import { AuthService } from '../../core/services/auth';

@Component({
  selector: 'app-tecnico-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './tecnico-dashboard.html',
  styleUrls: ['./tecnico-dashboard.css']
})
export class TecnicoDashboardComponent implements OnInit {
  private tecnicoService = inject(TecnicoService);
  private authService = inject(AuthService);
  private router = inject(Router);
  private cdr = inject(ChangeDetectorRef);

  incidentes: any[] = [];
  incidentesFiltrados: any[] = [];
  cargando = false;
  nombre = '';
  mensaje = '';
  
  // Filtros
  filtroEstado = '';
  filtroFecha = '';
  filtroDistancia = '';
  
  // Estados disponibles (según backend)
  estados = ['pendiente', 'en_proceso', 'rechazado', 'atendido', 'cancelado'];
  
  // Coordenadas del técnico (simulado - en producción vendrían del GPS)
  coordenadasTecnico = { lat: -17.8, lng: -63.2 };

  ngOnInit() {
    this.nombre = this.authService.getNombre();
    this.cargarIncidentes();
  }

  cargarIncidentes() {
    this.cargando = true;
    this.tecnicoService.getMisIncidentes().subscribe({
      next: (data) => {
        this.incidentes = data;
        this.aplicarFiltrosYOrdenamiento();
        this.cargando = false;
        this.cdr.detectChanges();
      },
      error: (err) => {
        console.error('Error al cargar incidentes:', err);
        this.mensaje = 'Error al cargar los incidentes ❌';
        this.cargando = false;
        this.cdr.detectChanges();
      }
    });
  }

  aplicarFiltrosYOrdenamiento() {
    let resultado = [...this.incidentes];
    
    console.log('=== FILTROS ===');
    console.log('Incidentes totales:', resultado.length);
    console.log('Estados únicos:', [...new Set(resultado.map(i => i.estado))]);
    console.log('Filtro estado seleccionado:', this.filtroEstado);
    console.log('Filtro fecha:', this.filtroFecha);
    console.log('Filtro distancia:', this.filtroDistancia);
    
    // Filtro por estado
    if (this.filtroEstado) {
      resultado = resultado.filter(inc => {
        const incidentes_estado = inc.estado?.toLowerCase().trim();
        const filtro_estado = this.filtroEstado.toLowerCase().trim();
        return incidentes_estado === filtro_estado;
      });
      console.log('Después de filtro estado:', resultado.length);
    }
    
    // Filtro por fecha
    if (this.filtroFecha) {
      // Extraer solo la fecha sin considerar hora ni zona horaria
      const fechaFiltro = this.filtroFecha; // Formato: YYYY-MM-DD del input
      
      resultado = resultado.filter(inc => {
        // Obtener la fecha del incidente en formato local
        const fechaIncDate = new Date(inc.fecha_creacion);
        // Usar toLocaleDateString para obtener fecha en formato local sin problemas de timezone
        const year = fechaIncDate.getFullYear();
        const month = String(fechaIncDate.getMonth() + 1).padStart(2, '0');
        const day = String(fechaIncDate.getDate()).padStart(2, '0');
        const fechaIncStr = `${year}-${month}-${day}`; // YYYY-MM-DD
        
        const coincide = fechaIncStr === fechaFiltro;
        console.log('Fecha filtro:', fechaFiltro, '| Fecha incidente:', fechaIncStr, '| Coincide:', coincide);
        return coincide;
      });
      console.log('Después de filtro fecha:', resultado.length);
    }
    
    // Filtro por distancia
    if (this.filtroDistancia) {
      resultado = resultado.filter(inc => {
        const distancia = this.calcularDistancia(inc);
        if (this.filtroDistancia === 'cerca') return distancia < 5;
        if (this.filtroDistancia === 'medio') return distancia >= 5 && distancia < 15;
        if (this.filtroDistancia === 'lejos') return distancia >= 15;
        return true;
      });
      console.log('Después de filtro distancia:', resultado.length);
    }
    
    // Ordenamiento: primero por estado (en_proceso > atendido > pendiente > rechazado > cancelado)
    const ordenEstado: { [key: string]: number } = {
      'en_proceso': 1,
      'atendido': 2,
      'pendiente': 3,
      'rechazado': 4,
      'cancelado': 5
    };
    
    // Ordenamiento por prioridad
    const ordenPrioridad: { [key: string]: number } = {
      'alta': 1,
      'media': 2,
      'baja': 3
    };
    
    resultado.sort((a, b) => {
      // Primero por estado
      const difEstado = (ordenEstado[a.estado] || 0) - (ordenEstado[b.estado] || 0);
      if (difEstado !== 0) return difEstado;
      
      // Luego por prioridad
      return (ordenPrioridad[a.prioridad?.toLowerCase()] || 0) - 
             (ordenPrioridad[b.prioridad?.toLowerCase()] || 0);
    });
    
    console.log('Resultado final después de filtros y ordenamiento:', resultado.length);
    this.incidentesFiltrados = resultado;
  }

  calcularDistancia(incidente: any): number {
    if (!incidente.taller || !incidente.taller.latitud || !incidente.taller.longitud) {
      return 0;
    }
    
    const lat1 = this.coordenadasTecnico.lat;
    const lon1 = this.coordenadasTecnico.lng;
    const lat2 = incidente.taller.latitud;
    const lon2 = incidente.taller.longitud;
    
    // Fórmula de Haversine simplificada
    const R = 6371; // Radio de la Tierra en km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distancia = R * c;
    
    return Math.round(distancia * 10) / 10; // Redondear a 1 decimal
  }

  getDistanciaClass(incidente: any): string {
    const distancia = this.calcularDistancia(incidente);
    if (distancia < 5) return 'distancia-cerca';
    if (distancia < 15) return 'distancia-medio';
    return 'distancia-lejos';
  }

  abrirGoogleMaps(incidente: any) {
    if (!incidente.taller || !incidente.taller.latitud || !incidente.taller.longitud) {
      alert('Coordenadas no disponibles');
      return;
    }
    const url = `https://www.google.com/maps?q=${incidente.taller.latitud},${incidente.taller.longitud}`;
    window.open(url, '_blank');
  }

  onFiltroChange() {
    this.aplicarFiltrosYOrdenamiento();
    this.cdr.detectChanges();
  }

  verDetalle(incidenteId: number) {
    this.router.navigate(['/tecnico/incidente', incidenteId]);
  }

  salir() {
    this.authService.logout();
    this.router.navigate(['/login']);
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
}
