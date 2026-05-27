import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class TecnicoService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/incidentes`;

  private getHeaders() {
    const token = localStorage.getItem('token');
    return {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    };
  }

  // Obtener incidentes asignados al técnico
  getMisIncidentes(): Observable<any[]> {
    return this.http.get<any[]>(`${this.apiUrl}/tecnico/mis-incidentes`, {
      headers: this.getHeaders()
    });
  }

  // Obtener detalle de un incidente específico
  getIncidente(id: number): Observable<any> {
    return this.http.get<any>(`${this.apiUrl}/${id}`, {
      headers: this.getHeaders()
    });
  }
}
