import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { IncidentesService } from '../../core/services/incidentes';
import { Incidente } from '../../interface/incidente.interface';
import { environment } from '../../../environments/environment';

@Component({
  selector: 'app-historial',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './historial.html',
  styleUrl: './historial.css'
})
export class HistorialComponent implements OnInit {
  private incidentesService = inject(IncidentesService);
  private http = inject(HttpClient);

  historial: Incidente[] = [];
  metricas: any = null;
  cargando = false;
  tecnicos: any[] = [];

  descargas: { [id: number]: boolean } = {};

  // Filtros
  fechaInicio: string = '';
  fechaFin: string = '';
  tecnicoSeleccionado: number | null = null;
  
  estadosDisponibles = [
    { value: 'finalizado', label: 'Finalizado' },
    { value: 'cancelado', label: 'Cancelado' },
    { value: 'en_atencion', label: 'En Atención' },
    { value: 'en_camino', label: 'En Camino' },
    { value: 'asignado_taller', label: 'Taller Asignado' }
  ];
  estadosSeleccionados: string[] = ['finalizado', 'cancelado'];

  etiquetaEstado(estado: string): string {
    const labels: Record<string, string> = {
      buscando_taller: 'Buscando taller',
      asignado_taller: 'Taller asignado',
      en_camino: 'En camino',
      en_atencion: 'En atención',
      finalizado: 'Finalizado',
      cancelado: 'Cancelado'
    };
    return labels[estado] || estado;
  }

  ngOnInit() {
    this.cargarTecnicos();
    this.cargarDatos();
  }

  cargarTecnicos() {
    const token = localStorage.getItem('token');
    if (!token) return;
    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    
    this.http.get<any[]>(`${environment.apiUrl}/usuarios/mis-tecnicos`, { headers }).subscribe({
      next: (data) => this.tecnicos = data,
      error: (err) => console.error('Error cargando técnicos:', err)
    });
  }

  toggleEstado(estado: string) {
    const index = this.estadosSeleccionados.indexOf(estado);
    if (index > -1) {
      this.estadosSeleccionados.splice(index, 1);
    } else {
      this.estadosSeleccionados.push(estado);
    }
  }

  cargarDatos() {
    this.cargando = true;
    
    const fi = this.fechaInicio ? `${this.fechaInicio}T00:00:00Z` : undefined;
    const ff = this.fechaFin ? `${this.fechaFin}T23:59:59Z` : undefined;

    this.incidentesService.obtenerMetricas(
      fi,
      ff,
      this.estadosSeleccionados,
      this.tecnicoSeleccionado || undefined
    ).subscribe({
      next: (data: any) => this.metricas = data,
      error: (err: any) => console.error('Error cargando métricas:', err)
    });

    this.incidentesService.obtenerHistorial(
      fi, 
      ff,
      this.estadosSeleccionados,
      this.tecnicoSeleccionado || undefined
    ).subscribe({
      next: (data: Incidente[]) => {
        this.historial = data;
        this.cargando = false;
      },
      error: (err: any) => {
        console.error('Error cargando historial:', err);
        this.cargando = false;
      }
    });
  }

  aplicarFiltros() {
    this.cargarDatos();
  }
  
  descargarPDF(id: number) {
    this.descargas[id] = true;

    this.incidentesService.descargarReporte(id).subscribe({
      next: (blob) => {
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `Reporte_Tecnico_${id}.pdf`;
        link.click();
        this.descargas[id] = false;
      },
      error: () => {
        alert('Error al generar el reporte');
        this.descargas[id] = false;
      }
    });
  }
}
