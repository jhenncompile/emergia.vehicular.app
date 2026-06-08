import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface TipoCount {
  tipo: string;
  total: number;
}

export interface HeatPoint {
  lat: number;
  lng: number;
  tipo: string;
  peso: number;
}

export interface RankingTaller {
  taller_id: number;
  nombre: string;
  total_atenciones: number;
  tasa_exito: number;
  tiempo_promedio: number;
  puntaje: number;
}

@Injectable({
  providedIn: 'root'
})
export class AnalisisService {
  private http = inject(HttpClient);
  private baseUrl = `${environment.apiUrl}/analisis`;

  private getHeaders() {
    const token = localStorage.getItem('token');
    return new HttpHeaders().set('Authorization', `Bearer ${token}`);
  }

  getIncidentesPorTipo(dias: number = 30): Observable<TipoCount[]> {
    return this.http.get<TipoCount[]>(`${this.baseUrl}/por-tipo?dias=${dias}`, { headers: this.getHeaders() });
  }

  getHeatmapData(dias: number = 30): Observable<HeatPoint[]> {
    return this.http.get<HeatPoint[]>(`${this.baseUrl}/heatmap?dias=${dias}`, { headers: this.getHeaders() });
  }
  
  getRankingTalleres(dias: number = 30): Observable<RankingTaller[]> {
    return this.http.get<RankingTaller[]>(`${this.baseUrl}/ranking-talleres?dias=${dias}`, { headers: this.getHeaders() });
  }
}
