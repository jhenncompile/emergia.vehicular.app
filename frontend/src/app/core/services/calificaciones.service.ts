import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface CalificacionDetalle {
  id: number;
  incidente_id: number;
  taller_id: number;
  usuario_id: number;
  puntuacion: number;
  comentario: string;
  fecha_creacion: string;
  cliente_nombre: string;
  cliente_apellido: string;
  vehiculo_marca?: string;
  vehiculo_modelo?: string;
}

export interface PromedioTaller {
  taller_id: number;
  promedio: number;
  total_calificaciones: number;
}

@Injectable({
  providedIn: 'root'
})
export class CalificacionesService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/calificaciones`;

  private get headers() {
    const token = localStorage.getItem('token');
    return new HttpHeaders().set('Authorization', `Bearer ${token}`);
  }

  getMisCalificaciones(): Observable<CalificacionDetalle[]> {
    return this.http.get<CalificacionDetalle[]>(`${this.apiUrl}/taller/mis-calificaciones`, { headers: this.headers });
  }

  getPromedioTaller(tallerId: number): Observable<PromedioTaller> {
    return this.http.get<PromedioTaller>(`${this.apiUrl}/taller/${tallerId}/promedio`, { headers: this.headers });
  }
}
