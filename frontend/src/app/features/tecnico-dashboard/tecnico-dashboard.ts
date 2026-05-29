import { Component, OnInit, OnDestroy, inject, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { TecnicoService } from '../../core/services/tecnico';
import { AuthService } from '../../core/services/auth';
import { NotificacionContadorService } from '../../core/services/notificacion-contador.service';
import { WebSocketNotificacionService } from '../../core/services/websocket-notificacion.service';
import { Subscription } from 'rxjs';

@Component({
  selector: 'app-tecnico-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './tecnico-dashboard.html',
  styleUrls: ['./tecnico-dashboard.css']
})
export class TecnicoDashboardComponent implements OnInit, OnDestroy {
  private tecnicoService = inject(TecnicoService);
  private authService = inject(AuthService);
  private router = inject(Router);
  private cdr = inject(ChangeDetectorRef);
  private contadorNotificaciones = inject(NotificacionContadorService);
  public wsService = inject(WebSocketNotificacionService);
  private notificacionSub: Subscription | null = null;
  private contadorSub: Subscription | null = null;

  incidentes: any[] = [];
  incidentesFiltrados: any[] = [];
  cargando = false;
  nombre = '';
  mensaje = '';
  notificacionesNoLeidas = 0;
  toastNotificacion: any = null;
  private toastTimeoutId: ReturnType<typeof setTimeout> | null = null;
  
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
    this.contadorSub = this.contadorNotificaciones.noLeidas$.subscribe((cantidad) => {
      this.notificacionesNoLeidas = cantidad;
      this.cdr.detectChanges();
    });
    this.contadorNotificaciones.cargarPendientes();
    
    // Conectar WebSocket para recibir notificaciones en tiempo real
    const usuarioId = localStorage.getItem('usuario_id');
    if (usuarioId) {
      this.wsService.conectar(parseInt(usuarioId));
      
      // Escuchar notificaciones
      this.notificacionSub = this.wsService.notificaciones$.subscribe(notif => {
        if (notif) {
          // Mostrar notificación visual
          this.mostrarNotificacion(notif);
          this.contadorNotificaciones.cargarPendientes();
          
          // Recargar incidentes automáticamente
          this.cargarIncidentes();
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
    if (this.toastTimeoutId) {
      clearTimeout(this.toastTimeoutId);
      this.toastTimeoutId = null;
    }
    this.wsService.desconectar();
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

    // Filtro por estado
    if (this.filtroEstado) {
      resultado = resultado.filter(inc => {
        const incidentes_estado = inc.estado?.toLowerCase().trim();
        const filtro_estado = this.filtroEstado.toLowerCase().trim();
        return incidentes_estado === filtro_estado;
      });
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
        
        return fechaIncStr === fechaFiltro;
      });
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
    this.contadorNotificaciones.limpiar();
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

  mostrarNotificacion(notif: any) {
    this.toastNotificacion = {
      titulo: notif.titulo || 'Nueva notificación',
      mensaje: notif.mensaje || 'Tienes una nueva notificación',
      tipo: notif.tipo || 'sistema',
      incidente_id: notif.incidente_id
    };

    if (this.toastTimeoutId) {
      clearTimeout(this.toastTimeoutId);
    }

    this.toastTimeoutId = setTimeout(() => {
      this.cerrarToastNotificacion();
    }, 8000);
    
    // Reproducir sonido (opcional)
    this.playNotificationSound();
  }

  cerrarToastNotificacion() {
    this.toastNotificacion = null;
    if (this.toastTimeoutId) {
      clearTimeout(this.toastTimeoutId);
      this.toastTimeoutId = null;
    }
    this.cdr.detectChanges();
  }

  abrirNotificaciones() {
    this.cerrarToastNotificacion();
    this.router.navigate(['/tecnico/notificaciones']);
  }

  playNotificationSound() {
    // Crear un beep simple sin necesidad de archivo de audio
    try {
      const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
      const oscillator = audioContext.createOscillator();
      const gainNode = audioContext.createGain();
      
      oscillator.connect(gainNode);
      gainNode.connect(audioContext.destination);
      
      oscillator.frequency.value = 800; // Frecuencia en Hz
      oscillator.type = 'sine';
      
      gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.5);
      
      oscillator.start(audioContext.currentTime);
      oscillator.stop(audioContext.currentTime + 0.5);
    } catch (e) {
      // Si falla, silenciosamente continuar
    }
  }
}
