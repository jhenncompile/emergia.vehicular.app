import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { IncidentesService } from '../../core/services/incidentes';
import { environment } from '../../../environments/environment';
import jsPDF from 'jspdf';
import html2canvas from 'html2canvas';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.css'
})
export class DashboardComponent implements OnInit {
  private http = inject(HttpClient);
  private incidentesService = inject(IncidentesService);

  tallerNombre = 'Cargando...';
  usuarioNombre = 'Usuario';

  // Estado de carga
  cargando = true;
  cargandoMetricas = true;
  exportandoPDF = false;

  // Filtros de fecha
  fechaInicio: string = '';
  fechaFin: string = '';

  async exportarPDF() {
    this.exportandoPDF = true;
    try {
      const dashboardElement = document.querySelector('.dashboard-wrapper') as HTMLElement;
      if (!dashboardElement) {
        throw new Error('Elemento del dashboard no encontrado');
      }

      // Para evitar que los botones se impriman (opcional, pero mejora el look)
      const filterBar = document.querySelector('.filter-bar') as HTMLElement;
      if (filterBar) filterBar.style.display = 'none';

      const canvas = await html2canvas(dashboardElement, {
        scale: 2,
        useCORS: true,
        backgroundColor: '#f4f6fb',
      });

      if (filterBar) filterBar.style.display = 'flex';

      const imgData = canvas.toDataURL('image/png');
      const pdf = new jsPDF('p', 'mm', 'a4');
      
      const pdfWidth = pdf.internal.pageSize.getWidth();
      const pdfHeight = (canvas.height * pdfWidth) / canvas.width;

      pdf.addImage(imgData, 'PNG', 0, 0, pdfWidth, pdfHeight);
      pdf.save(`Reporte_KPIs_${this.fechaInicio}_al_${this.fechaFin}.pdf`);
    } catch (error) {
      console.error('Error al generar PDF', error);
      alert('Hubo un error al generar el PDF. Intente nuevamente.');
    } finally {
      this.exportandoPDF = false;
    }
  }

  // KPIs principales
  kpis = {
    totalIncidentes: 0,
    incidentesFinalizados: 0,
    incidentesCancelados: 0,
    porcentajeCancelados: 0,
    tasaExito: 0,
    tiempoPromedioMin: 0,
    tiempoPromedioLlegadaMin: 0,
    cumplimientoSLA: 0,
    promedioCalificacion: 0,
    recaudadoBruto: 0,
    recaudadoNeto: 0,
    comisionPlataforma: 0,
  };

  // Atenciones por técnico
  atencionPorTecnico: Array<{ tecnico: string; cantidad: number; porcentaje: number }> = [];

  // Datos para mini-chart de barras (por técnico)
  maxAtencionesTecnico = 1;

  // KPIs de incidentes por estado (calculados desde historial)
  distribucionEstados: Array<{ estado: string; cantidad: number; color: string }> = [];

  ngOnInit() {
    this.setFechasPorDefecto();
    this.obtenerDatosPerfil();
    this.cargarDashboard();
  }

  setFechasPorDefecto() {
    const hoy = new Date();
    const primerDiaMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    this.fechaFin = hoy.toISOString().split('T')[0];
    this.fechaInicio = primerDiaMes.toISOString().split('T')[0];
  }

  obtenerDatosPerfil() {
    const token = localStorage.getItem('token');
    if (!token) return;
    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    this.http.get<any>(`${environment.apiUrl}/usuarios/me`, { headers }).subscribe({
      next: (user) => {
        this.usuarioNombre = user.nombre;
        this.tallerNombre = user.taller?.nombre ?? 'Mi Taller';
      },
      error: () => { this.tallerNombre = 'Mi Taller'; }
    });
  }

  cargarDashboard() {
    this.cargandoMetricas = true;
    const fi = this.fechaInicio ? `${this.fechaInicio}T00:00:00Z` : undefined;
    const ff = this.fechaFin ? `${this.fechaFin}T23:59:59Z` : undefined;

    // Cargar métricas del backend (única llamada)
    this.incidentesService.obtenerMetricas(fi, ff).subscribe({
      next: (metricas) => {
        const fin = metricas.finanzas ?? {};
        this.kpis.recaudadoBruto = parseFloat(fin.recaudado_bruto ?? 0);
        this.kpis.recaudadoNeto = parseFloat(fin.recaudado_neto ?? 0);
        this.kpis.comisionPlataforma = this.kpis.recaudadoBruto - this.kpis.recaudadoNeto;
        this.kpis.tiempoPromedioMin = metricas.tiempo_promedio_asignacion_segundos
          ? Math.round(metricas.tiempo_promedio_asignacion_segundos / 60)
          : 0;
        this.kpis.tiempoPromedioLlegadaMin = metricas.tiempo_promedio_llegada_segundos
          ? Math.round(metricas.tiempo_promedio_llegada_segundos / 60)
          : 0;
        this.kpis.cumplimientoSLA = metricas.cumplimiento_sla_porcentaje ?? 0;
        this.kpis.promedioCalificacion = metricas.promedio_calificacion ?? 0;

        // Atenciones por técnico
        const porTec = (metricas.atenciones_por_tecnico ?? []) as Array<{ tecnico: string; cantidad: number }>;
        const totalAtenciones = porTec.reduce((s, t) => s + t.cantidad, 0) || 1;
        this.atencionPorTecnico = porTec.map(t => ({
          ...t,
          porcentaje: Math.round((t.cantidad / totalAtenciones) * 100)
        }));
        this.maxAtencionesTecnico = Math.max(...porTec.map(t => t.cantidad), 1);

        // KPIs de incidentes desde conteo_por_estado del backend
        this.kpis.totalIncidentes = metricas.total_incidentes ?? 0;
        const conteoEstados = (metricas.conteo_por_estado ?? []) as Array<{ estado: string; cantidad: number }>;
        const finalizados = conteoEstados.find(e => e.estado === 'finalizado')?.cantidad ?? 0;
        const cancelados = conteoEstados.find(e => e.estado === 'cancelado')?.cantidad ?? 0;
        
        this.kpis.incidentesFinalizados = finalizados;
        this.kpis.incidentesCancelados = cancelados;
        this.kpis.tasaExito = this.kpis.totalIncidentes > 0 
          ? Math.round((finalizados / this.kpis.totalIncidentes) * 100) 
          : 0;
        this.kpis.porcentajeCancelados = this.kpis.totalIncidentes > 0
          ? Math.round((cancelados / this.kpis.totalIncidentes) * 100)
          : 0;

        // Distribución por estado para el gráfico
        const colores: Record<string, string> = {
          finalizado: '#51cf66',
          cancelado: '#ff6b6b',
          en_atencion: '#339af0',
          en_camino: '#f59f00',
          buscando_taller: '#cc5de8',
          pendiente: '#adb5bd',
          asignado_taller: '#74c0fc',
        };
        this.distribucionEstados = conteoEstados.map(e => ({
          estado: this.formatearEstado(e.estado),
          cantidad: e.cantidad,
          color: colores[e.estado] ?? '#adb5bd'
        })).sort((a, b) => b.cantidad - a.cantidad);

        this.cargandoMetricas = false;
        this.cargando = false;
      },
      error: () => {
        this.cargandoMetricas = false;
        this.cargando = false;
      }
    });
  }

  aplicarFiltros() {
    this.cargarDashboard();
  }

  limpiarFiltros() {
    this.setFechasPorDefecto();
    this.cargarDashboard();
  }

  formatearEstado(estado: string): string {
    const mapa: Record<string, string> = {
      finalizado: 'Finalizado',
      cancelado: 'Cancelado',
      en_atencion: 'En Atención',
      en_camino: 'En Camino',
      buscando_taller: 'Buscando Taller',
      pendiente: 'Pendiente',
    };
    return mapa[estado] ?? estado;
  }

  barWidth(cantidad: number): number {
    return Math.round((cantidad / this.maxAtencionesTecnico) * 100);
  }

  formatMoney(n: number): string {
    return n.toLocaleString('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }
}