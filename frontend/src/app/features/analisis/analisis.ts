import { Component, OnInit, inject, ViewChild, ElementRef, AfterViewInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { BaseChartDirective } from 'ng2-charts';
import { ChartConfiguration, ChartData, ChartType } from 'chart.js';
import * as L from 'leaflet';

import { AnalisisService, TipoCount, HeatPoint } from '../../core/services/analisis';

@Component({
  selector: 'app-analisis',
  imports: [CommonModule, FormsModule, BaseChartDirective],
  templateUrl: './analisis.html',
  styleUrl: './analisis.css',
})
export class Analisis implements OnInit, AfterViewInit {
  private analisisService = inject(AnalisisService);

  periodoSeleccionado: number = 30; // 1: Hoy, 7: Semana, 30: Mes

  // --- Chart.js Data ---
  public barChartOptions: ChartConfiguration['options'] = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: 'rgba(15, 23, 42, 0.9)',
        titleFont: { size: 14, family: 'Inter' },
        bodyFont: { size: 14, family: 'Inter' },
        padding: 10,
        displayColors: false,
      }
    },
    scales: {
      y: { beginAtZero: true, grid: { color: 'rgba(0, 0, 0, 0.05)' }, ticks: { color: '#64748b' } },
      x: { grid: { display: false }, ticks: { color: '#64748b' } }
    }
  };
  public barChartType: ChartType = 'bar';
  public barChartData: ChartData<'bar'> = {
    labels: [],
    datasets: [{ data: [], backgroundColor: '#3b82f6', borderRadius: 6 }]
  };

  // --- Leaflet Map ---
  @ViewChild('mapElement') mapElement!: ElementRef;
  private map!: L.Map;
  private heatLayer: any;

  ngOnInit() {
    this.cargarDatos();
  }

  ngAfterViewInit() {
    this.initMap();
  }

  onPeriodoChange() {
    this.cargarDatos();
  }

  private cargarDatos() {
    // 1. Cargar Gráfico de Barras
    this.analisisService.getIncidentesPorTipo(this.periodoSeleccionado).subscribe(data => {
      this.barChartData.labels = data.map(d => d.tipo);
      this.barChartData.datasets[0].data = data.map(d => d.total);
      
      // Forzar actualización del gráfico clonando el objeto
      this.barChartData = { ...this.barChartData };
    });

    // 2. Cargar Mapa de Calor
    this.analisisService.getHeatmapData(this.periodoSeleccionado).subscribe(data => {
      this.actualizarHeatmap(data);
    });
  }

  private initMap() {
    // Coordenadas base (ejemplo: Santa Cruz de la Sierra)
    this.map = L.map(this.mapElement.nativeElement).setView([-17.7833, -63.1821], 12);
    
    L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
      attribution: '© OpenStreetMap contributors © CARTO',
      maxZoom: 19
    }).addTo(this.map);
  }

  private async actualizarHeatmap(data: HeatPoint[]) {
    if (this.heatLayer) {
      this.map.removeLayer(this.heatLayer);
    }
    
    // Transformar datos para leaflet.heat: [lat, lng, intensidad]
    const heatData = data.map(p => [p.lat, p.lng, p.peso] as L.HeatLatLngTuple);
    
    // Asegurar que L está global antes de cargar el plugin (necesario en prod)
    (window as any).L = L;
    await import('leaflet.heat');

    // @ts-ignore - plugin estático
    this.heatLayer = L.heatLayer(heatData, {
      radius: 25,
      blur: 15,
      maxZoom: 12,
      gradient: { 0.4: 'blue', 0.6: 'cyan', 0.7: 'lime', 0.8: 'yellow', 1.0: 'red' }
    }).addTo(this.map);
  }
}
