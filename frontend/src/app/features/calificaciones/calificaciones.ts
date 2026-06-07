import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CalificacionesService, CalificacionDetalle, PromedioTaller } from '../../core/services/calificaciones.service';

import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

@Component({
  selector: 'app-calificaciones',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './calificaciones.html',
  styleUrl: './calificaciones.css'
})
export class CalificacionesComponent implements OnInit {
  private calificacionesService = inject(CalificacionesService);
  private http = inject(HttpClient);

  public calificaciones: CalificacionDetalle[] = [];
  public calificacionesFiltradas: CalificacionDetalle[] = [];
  public promedioInfo: PromedioTaller | null = null;
  public isLoading: boolean = true;
  public errorMessage: string = '';

  // Filtros Backend
  public fechaInicio: string = '';
  public fechaFin: string = '';
  public tecnicos: Array<{id: number, nombre: string, apellido: string}> = [];
  public tecnicoSeleccionado: number | null = null;

  // Filtros Frontend
  public estrellasFiltro: number | 'TODAS' = 'TODAS';
  public fechaOrden: 'NUEVAS' | 'ANTIGUAS' = 'NUEVAS';

  ngOnInit() {
    this.setFechasPorDefecto();
    this.cargarTecnicos();
    this.cargarDatos();
  }

  setFechasPorDefecto() {
    const hoy = new Date();
    const primerDiaMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    this.fechaFin = hoy.toISOString().split('T')[0];
    this.fechaInicio = primerDiaMes.toISOString().split('T')[0];
  }

  cargarTecnicos() {
    const token = localStorage.getItem('token');
    if (token) {
      this.http.get<any[]>(`${environment.apiUrl}/usuarios/mis-tecnicos`, {
        headers: { Authorization: `Bearer ${token}` }
      }).subscribe({
        next: (res) => this.tecnicos = res,
        error: () => {}
      });
    }
  }

  aplicarFiltrosBackend() {
    this.cargarDatos();
  }

  limpiarFiltrosBackend() {
    this.setFechasPorDefecto();
    this.tecnicoSeleccionado = null;
    this.cargarDatos();
  }

  cargarDatos() {
    this.isLoading = true;
    const fi = this.fechaInicio ? `${this.fechaInicio}T00:00:00Z` : undefined;
    const ff = this.fechaFin ? `${this.fechaFin}T23:59:59Z` : undefined;
    const tecId = this.tecnicoSeleccionado ? Number(this.tecnicoSeleccionado) : undefined;

    this.calificacionesService.getMisCalificaciones(fi, ff, tecId).subscribe({
      next: (data) => {
        this.calificaciones = data;
        this.aplicarFiltros();
        this.isLoading = false;
      },
      error: (err) => {
        this.errorMessage = 'Error al cargar calificaciones';
        this.isLoading = false;
      }
    });
  }

  aplicarFiltros() {
    let filtradas = [...this.calificaciones];

    // Filtro por estrellas
    if (this.estrellasFiltro !== 'TODAS') {
      filtradas = filtradas.filter(c => c.puntuacion === this.estrellasFiltro);
    }

    // Orden por fecha
    filtradas.sort((a, b) => {
      const dateA = new Date(a.fecha_creacion).getTime();
      const dateB = new Date(b.fecha_creacion).getTime();
      return this.fechaOrden === 'NUEVAS' ? dateB - dateA : dateA - dateB;
    });

    this.calificacionesFiltradas = filtradas;

    // Recalcular promedio basado en lo que realmente se ve
    if (filtradas.length > 0) {
      const sum = filtradas.reduce((acc, curr) => acc + curr.puntuacion, 0);
      this.promedioInfo = {
        taller_id: 0,
        promedio: sum / filtradas.length,
        total_calificaciones: filtradas.length
      };
    } else {
      this.promedioInfo = {
        taller_id: 0,
        promedio: 0,
        total_calificaciones: 0
      };
    }
  }

  onFiltroChange() {
    this.aplicarFiltros();
  }

  getStarsArray(puntuacion: number): number[] {
    return Array(5).fill(0).map((_, i) => i < puntuacion ? 1 : 0);
  }
}
