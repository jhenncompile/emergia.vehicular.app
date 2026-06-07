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

  // Datos temporales para las acciones
  incidenteAccion: any = null; 
  montoCobro: number = 0;
  idTecnicoSeleccionado: number = 0;
  motivoRechazo: string = '';
  accionMotivo: 'rechazar' | 'cancelar' = 'rechazar';

  ngOnInit() { 
    this.cargarDatos();
    this.cargarTecnicos();
  }

  cargarDatos() {
    this.cargando = true;
    this.incidentesService.getPendientes().subscribe(data => this.incidentesPendientes = data.sort((a, b) => b.id - a.id));
    this.incidentesService.getMisAtenciones().subscribe(data => {
      this.misAtenciones = data.sort((a, b) => b.id - a.id);
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
    return ['asignado_taller', 'en_camino'].includes(inc?.estado);
  }

  puedeMarcarLlegada(inc: any): boolean {
    return inc?.estado === 'en_camino';
  }

  puedeCobrar(inc: any): boolean {
    return inc?.estado === 'en_atencion' && inc?.pago_estado === 'pendiente';
  }

  puedeCancelar(inc: any): boolean {
    return ['asignado_taller', 'en_camino'].includes(inc?.estado);
  }

  // --- LÓGICA DE ASIGNACIÓN Y REASIGNACIÓN ---

  // Se usa cuando aceptas un incidente nuevo
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
      return alert('Solo puedes asignar técnico cuando el incidente está asignado al taller o en camino.');
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
    this.montoCobro = 0;
    this.mostrarModalCobro = true;
  }

  cerrarModalCobro() {
    this.mostrarModalCobro = false;
    this.incidenteAccion = null;
  }
  generarCobro() {
    if (this.montoCobro <= 0) return alert('Monto inválido.');
  
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
      error: (e) => alert('Error al generar cobro: ' + e.error?.detail)
    });
  }
}
