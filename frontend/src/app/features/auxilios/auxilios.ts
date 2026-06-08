import { Component, inject, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms'; 
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { IncidentesService } from '../../core/services/incidentes';
import { UsuariosService } from '../../core/services/usuarios'; 
import { WebSocketNotificacionService } from '../../core/services/websocket-notificacion.service';
import { environment } from '../../../environments/environment';
import { MapaTecnicoComponent } from './mapa-tecnico/mapa-tecnico.component';

@Component({
  selector: 'app-auxilios',
  standalone: true,
  imports: [CommonModule, FormsModule, MapaTecnicoComponent],
  templateUrl: './auxilios.html',
  styleUrl: './auxilios.css'
})
export class AuxiliosComponent implements OnInit {
  private incidentesService = inject(IncidentesService);
  private usuariosService = inject(UsuariosService);
  private http = inject(HttpClient);

  tabActiva: 'pendientes' | 'mis-atenciones' = 'pendientes';
  incidentesPendientes: any[] = [];
  misAtenciones: any[] = [];
  tecnicosDisponibles: any[] = []; 
  cargando: boolean = false;
  incidenteSeleccionado: any = null;

  // Estados de Modales
  mostrarModalCobro: boolean = false;
  mostrarModalAsignar: boolean = false; 
  mostrarModalRechazo: boolean = false; 
  mostrarModalCotizar: boolean = false;
  mostrarModalReparacion: boolean = false;

  // Datos temporales para las acciones
  incidenteAccion: any = null; 
  montoCobro: number = 0;
  cotizacionTiempo: string = '';
  tiempoReparacionInput: string = '';
  procesandoCobro: boolean = false;
  sugerenciaMonto: number = 0;
  idTecnicoSeleccionado: number = 0;
  motivoRechazo: string = '';
  accionMotivo: 'rechazar' | 'cancelar' = 'rechazar';

  ngOnInit() { 
    this.cargarDatos();
    this.cargarTecnicos();
    
    // Suscribirse a websocket para auto-actualizar estados
    this.wsNotificacionService.notificaciones$.subscribe(notif => {
      if (notif && notif.incidente_id) {
        this.cargarDatos(); // Recargar datos si hay cualquier novedad del incidente
      }
    });
  }

  cargarDatos() {
    this.cargando = true;
    this.incidentesService.getPendientes().subscribe(data => {
      this.incidentesPendientes = data.sort((a, b) => b.id - a.id);
      if (this.incidenteSeleccionado && this.tabActiva === 'pendientes') {
        const updated = this.incidentesPendientes.find(i => i.id === this.incidenteSeleccionado.id);
        if (updated) this.incidenteSeleccionado = updated;
      }
    });
    this.incidentesService.getMisAtenciones().subscribe(data => {
      this.misAtenciones = data.sort((a, b) => b.id - a.id);
      if (this.incidenteSeleccionado && this.tabActiva === 'mis-atenciones') {
        const updated = this.misAtenciones.find(i => i.id === this.incidenteSeleccionado.id);
        if (updated) this.incidenteSeleccionado = updated;
      }
      this.cargando = false;
    });
  }

  cargarTecnicos() {
    this.usuariosService.getMisTecnicos().subscribe(data => {
      // Filtramos solo los que el taller marcó como activos
      this.tecnicosDisponibles = data.filter((t: any) => t.esta_activo);
    });
  }

  cambiarTab(tab: 'pendientes' | 'mis-atenciones') { 
    this.tabActiva = tab; 
    this.cerrarPanel();
  }

  cerrarPanel() {
    this.incidenteSeleccionado = null;
  }

  seleccionarIncidente(inc: any) { 
    this.incidenteSeleccionado = inc;
  }

  etiquetaEstado(estado: string): string {
    const labels: Record<string, string> = {
      pendiente: 'Pendiente',
      buscando_taller: 'Buscando taller',
      asignado_taller: 'Taller asignado',
      en_camino: 'En camino',
      en_atencion: 'En atención',
      finalizado: 'Finalizado',
      cancelado: 'Cancelado'
    };
    return labels[estado] || estado;
  }

  puedeAsignarTecnico(inc: any): boolean {
  return inc?.estado === 'asignado_taller';
}

  puedeReasignarTecnico(inc: any): boolean {
    return ['asignado_taller', 'en_camino', 'en_atencion'].includes(inc?.estado);
  }

  puedeMarcarLlegada(inc: any): boolean {
    return inc?.estado === 'en_camino';
  }

  puedeCobrar(inc: any): boolean {
    return (inc?.estado === 'en_atencion' || inc?.estado === 'finalizado') && inc?.pago_estado === 'pendiente';
  }

  puedeCancelar(inc: any): boolean {
    return ['asignado_taller', 'en_camino', 'en_atencion'].includes(inc?.estado);
  }

  // --- HELPERS PARA CARDS ---
  tieneFotos(inc: any): boolean {
    if (!inc?.evidencias) return false;
    return inc.evidencias.some((e: any) => e.tipo_archivo === 'imagen');
  }

  tieneAudio(inc: any): boolean {
    if (!inc?.evidencias) return false;
    return inc.evidencias.some((e: any) => e.tipo_archivo === 'audio');
  }

  evidenciaUrl(urlArchivo: string | null | undefined): string {
    if (!urlArchivo) return '';
    if (/^https?:\/\//i.test(urlArchivo)) return urlArchivo;

    const backendOrigin = environment.apiUrl.replace(/\/api\/v1\/?$/, '');
    const normalizedPath = urlArchivo.startsWith('/')
      ? urlArchivo
      : `/${urlArchivo}`;

    return `${backendOrigin}${normalizedPath}`;
  }

  calcularTiempo(fecha: string | undefined): string {
    if (!fecha) return '';
    const date = new Date(fecha);
    const diffMs = new Date().getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    if (diffMins < 60) return `${diffMins} min ago`;
    const diffHrs = Math.floor(diffMins / 60);
    if (diffHrs < 24) return `${diffHrs} hr ago`;
    const diffDays = Math.floor(diffHrs / 24);
    return `${diffDays} d ago`;
  }

  // --- LÓGICA DE ASIGNACIÓN Y REASIGNACIÓN ---

  // --- FLUJO DE COTIZACION (REEMPLAZA ACEPTAR DIRECTO) ---
  
  abrirModalCotizar(inc: any) {
    this.incidenteAccion = inc;
    // Buscar la sugerencia de IA en el arreglo de candidatos (si viene incluido en los datos)
    // O si el backend lo devuelve, por ahora pondremos 0 y el backend generará si no existe
    this.sugerenciaMonto = inc.sugerencia_ia_monto || 0; // Se asume que backend mandará esto
    this.montoCobro = this.sugerenciaMonto > 0 ? this.sugerenciaMonto : 100;
    this.cotizacionTiempo = '30 minutos';
    this.mostrarModalCotizar = true;
  }

  confirmarCotizacion() {
    if (this.montoCobro <= 0 || !this.cotizacionTiempo.trim()) {
      return alert('Debe ingresar un monto válido y un tiempo estimado.');
    }
    
    this.incidentesService.enviarCotizacion(this.incidenteAccion.id, this.montoCobro, this.cotizacionTiempo).subscribe({
      next: (res) => {
        alert('Cotización enviada exitosamente. El cliente será notificado.');
        this.mostrarModalCotizar = false;
        this.cargarDatos();
      },
      error: (e) => alert('Error al enviar cotización: ' + e.error?.detail)
    });
  }

  cerrarModalCotizar() {
    this.mostrarModalCotizar = false;
    this.incidenteAccion = null;
  }

  // Se usa cuando aceptas un incidente nuevo (DEPRECADO POR COTIZAR)
  aceptarIncidente(id: number) {
    this.incidentesService.aceptarIncidente(id).subscribe({
      next: (res) => {
        this.cargarDatos();
        this.incidenteAccion = res;
        this.idTecnicoSeleccionado = 0;
        this.mostrarModalAsignar = true;
      },
      error: (e) => alert('Error al aceptar: ' + e.error?.detail)
    });
  }

  // Se usa desde el panel lateral para cambiar al técnico
  abrirReasignacion() {
    if (!this.incidenteSeleccionado) return;
    if (!this.puedeReasignarTecnico(this.incidenteSeleccionado)) {
      return alert('Solo puedes asignar técnico cuando el incidente está asignado, en camino o en atención.');
    }
    this.incidenteAccion = this.incidenteSeleccionado;
    // Pre-seleccionamos el ID actual si ya tiene uno
    this.idTecnicoSeleccionado = this.incidenteSeleccionado.tecnico_id || 0;
    this.mostrarModalAsignar = true;
  }

  confirmarAsignacion() {
    if (!this.idTecnicoSeleccionado) return alert('Debes seleccionar un técnico.');
    
    this.incidentesService.asignarTecnico(this.incidenteAccion.id, this.idTecnicoSeleccionado).subscribe({
      next: () => {
        alert('Técnico asignado correctamente 🔧');
        
        // Actualización reactiva del panel lateral si está abierto
        const tecnicoNuevo = this.tecnicosDisponibles.find(t => t.id == this.idTecnicoSeleccionado);
        if (this.incidenteSeleccionado && this.incidenteSeleccionado.id === this.incidenteAccion.id) {
          this.incidenteSeleccionado.tecnico = tecnicoNuevo;
          this.incidenteSeleccionado.tecnico_id = this.idTecnicoSeleccionado;
        }

        this.cerrarModalAsignar();
        this.cargarDatos();
      },
      error: (e) => alert('Error en asignación: ' + e.error?.detail)
    });
  }

  cerrarModalAsignar() {
    this.mostrarModalAsignar = false;
    this.incidenteAccion = null;
    this.idTecnicoSeleccionado = 0;
  }

  // --- FLUJO DE RECHAZO ---

  abrirModalRechazo(inc: any, accion: 'rechazar' | 'cancelar' = 'rechazar') {
    this.incidenteAccion = inc;
    this.motivoRechazo = '';
    this.accionMotivo = accion;
    this.mostrarModalRechazo = true;
  }

  confirmarRechazo() {
    if (!this.motivoRechazo.trim()) return alert('Por favor escribe un motivo.');

    const request$ = this.accionMotivo === 'cancelar'
      ? this.incidentesService.cancelarIncidente(this.incidenteAccion.id, this.motivoRechazo)
      : this.incidentesService.rechazarIncidente(this.incidenteAccion.id, this.motivoRechazo);

    request$.subscribe({
      next: () => {
        alert(this.accionMotivo === 'cancelar' ? 'Incidente cancelado con éxito.' : 'Oferta rechazada con éxito.');
        this.mostrarModalRechazo = false;
        if (this.incidenteSeleccionado?.id === this.incidenteAccion.id) {
          this.cerrarPanel();
        }
        this.cargarDatos();
      },
      error: (e) => alert('Error al rechazar: ' + e.error?.detail)
    });
  }

  private wsNotificacionService = inject(WebSocketNotificacionService);
  private cd = inject(ChangeDetectorRef);

  actualizarLista(lista: any[], actualizado: any): any[] {
    return lista.map(inc => inc.id === actualizado.id ? actualizado : inc);
  }

  marcarLlegada(id: number) {
    if (!confirm('¿Marcar que el técnico llegó al incidente?')) return;
    this.incidentesService.marcarLlegada(id).subscribe({
      next: (actualizado) => {
        // Actualizamos localmente para no recargar toda la tabla
        this.incidentesPendientes = this.actualizarLista(this.incidentesPendientes, actualizado);
        this.misAtenciones = this.actualizarLista(this.misAtenciones, actualizado);
        
        if (this.incidenteSeleccionado?.id === id) {
          this.incidenteSeleccionado = { ...this.incidenteSeleccionado, ...actualizado };
        }
        
        // Forzamos actualización visual y avisamos al servidor WS
        this.cd.detectChanges();
        this.wsNotificacionService.enviarCambioEstado(id, 'en_atencion');
      },
      error: (e) => alert('Error al marcar llegada: ' + e.error?.detail)
    });
  }

  // --- COBRO ---

  abrirModalCobro(incidente: any) {
    this.incidenteAccion = incidente;
    this.montoCobro = incidente.cotizacion_monto || 0;
    this.mostrarModalCobro = true;
  }

  cerrarModalCobro() {
    this.mostrarModalCobro = false;
    this.incidenteAccion = null;
    this.procesandoCobro = false;
  }
  generarCobro() {
    if (this.montoCobro <= 0) return alert('Monto inválido.');
    if (this.procesandoCobro) return;
  
    this.procesandoCobro = true;
    const token = localStorage.getItem('token');
    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    const url = `${environment.apiUrl}/pagos/generar-cobro/${this.incidenteAccion.id}?monto=${this.montoCobro}&metodo=por_definir`;

    this.http.post(url, {}, { headers }).subscribe({
      next: (res: any) => {
        // ✅ ELIMINADO: window.open (Ya no abre links externos)
        alert('Cobro registrado y emitido con éxito 💵');
      
        this.cerrarModalCobro();
        this.cargarDatos(); // 🔄 Recargamos para que el estado 'pago_estado' cambie en la tabla
      },
      error: (e) => {
        this.procesandoCobro = false;
        alert('Error al generar cobro: ' + e.error?.detail);
      }
    });
  }
  abrirModalReparacion(incidente: any) {
    this.incidenteAccion = incidente;
    this.tiempoReparacionInput = incidente.tiempo_reparacion_estimado || '';
    this.mostrarModalReparacion = true;
  }

  cerrarModalReparacion() {
    this.mostrarModalReparacion = false;
    this.incidenteAccion = null;
    this.tiempoReparacionInput = '';
  }

  guardarTiempoReparacion() {
    if (!this.incidenteAccion || !this.tiempoReparacionInput.trim()) return;

    this.incidentesService.actualizarTiempoReparacion(this.incidenteAccion.id, this.tiempoReparacionInput).subscribe({
      next: () => {
        alert('Tiempo de reparación actualizado con éxito ⏱️');
        this.cerrarModalReparacion();
        this.cargarDatos(); 
      },
      error: (e: any) => alert('Error al actualizar tiempo: ' + e.error?.detail)
    });
  }
}
