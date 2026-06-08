import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AnalisisService, RankingTaller } from '../../core/services/analisis';

@Component({
  selector: 'app-ranking-talleres',
  imports: [CommonModule, FormsModule],
  templateUrl: './ranking-talleres.html',
  styleUrl: './ranking-talleres.css'
})
export class RankingTalleres implements OnInit {
  private analisisService = inject(AnalisisService);
  
  ranking: RankingTaller[] = [];
  cargando: boolean = true;
  periodoSeleccionado: number = 30;

  ngOnInit() {
    this.cargarRanking();
  }

  cargarRanking() {
    this.cargando = true;
    this.analisisService.getRankingTalleres(this.periodoSeleccionado).subscribe({
      next: (data) => {
        this.ranking = data;
        this.cargando = false;
      },
      error: (err) => {
        console.error('Error cargando ranking', err);
        this.cargando = false;
      }
    });
  }

  onPeriodoChange() {
    this.cargarRanking();
  }

  getMedal(index: number): string {
    if (index === 0) return '🥇';
    if (index === 1) return '🥈';
    if (index === 2) return '🥉';
    return `${index + 1}º`;
  }
}
