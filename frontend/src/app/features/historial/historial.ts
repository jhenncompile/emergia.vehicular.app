import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpHeaders } from '@angular/common/http'; // 👈 Importamos esto
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
  private http = inject(HttpClient); // 👈 Inyectamos HttpClient

  historial: Incidente[] = [];
  metricas: any = null;
  cargando = false;
  tecnicos: any[] = []; // 👈 Lista de técnicos

  // 🚩 Diccionario para el estado de carga del PDF (Soluciona el error TS2339)
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
    this.cargarTecnicos(); // 👈 Cargamos los técnicos reales
    this.cargarDatos();
  }

  cargarTecnicos() {
    const token = localStorage.getItem('token');
    if (!token) return;
    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    
    // 🚩 Usamos tu ruta real del backend: /usuarios/mis-tecnicos
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
    
    this.incidentesService.obtenerMetricas(
      this.fechaInicio,
      this.fechaFin,
      this.estadosSeleccionados,
      this.tecnicoSeleccionado || undefined
    ).subscribe({
      next: (data: any) => this.metricas = data,
      error: (err: any) => console.error('Error cargando métricas:', err)
    });

    // 🚩 Enviamos todos los filtros al servicio
    this.incidentesService.obtenerHistorial(
      this.fechaInicio, 
      this.fechaFin,
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
    this.descargas[id] = true; // 🚩 Marcamos carga en el diccionario

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
