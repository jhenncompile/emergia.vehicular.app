import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CalificacionesService, CalificacionDetalle, PromedioTaller } from '../../core/services/calificaciones.service';

@Component({
  selector: 'app-calificaciones',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './calificaciones.html',
  styleUrl: './calificaciones.css'
})
export class CalificacionesComponent implements OnInit {
  private calificacionesService = inject(CalificacionesService);

  public calificaciones: CalificacionDetalle[] = [];
  public calificacionesFiltradas: CalificacionDetalle[] = [];
  public promedioInfo: PromedioTaller | null = null;
  public isLoading: boolean = true;
  public errorMessage: string = '';

  // Filtros
  public estrellasFiltro: number | 'TODAS' = 'TODAS';
  public fechaOrden: 'NUEVAS' | 'ANTIGUAS' = 'NUEVAS';

  ngOnInit() {
    this.cargarDatos();
  }

  cargarDatos() {
    this.isLoading = true;
    const tallerId = Number(localStorage.getItem('taller_id'));

    if (Number.isFinite(tallerId) && tallerId > 0) {
      this.calificacionesService.getPromedioTaller(tallerId).subscribe({
        next: (info) => this.promedioInfo = info,
        error: () => {}
      });
    }

    this.calificacionesService.getMisCalificaciones().subscribe({
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
  }

  onFiltroChange() {
    this.aplicarFiltros();
  }

  getStarsArray(puntuacion: number): number[] {
    return Array(5).fill(0).map((_, i) => i < puntuacion ? 1 : 0);
  }
}
