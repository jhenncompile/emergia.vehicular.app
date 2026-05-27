import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
// 👇 Importamos el environment global
import { environment } from '../../../environments/environment'; 

@Injectable({ providedIn: 'root' })
export class TalleresService {
  private http = inject(HttpClient);
  // 👇 Usamos la variable dinámica en lugar del localhost quemado
  private apiUrl = `${environment.apiUrl}/talleres`;

  private getHeaders() {
    return new HttpHeaders().set('Authorization', `Bearer ${localStorage.getItem('token')}`);
  }

  // Obtiene los datos del taller del admin logueado
  getMiTaller(): Observable<any> {
    return this.http.get(`${this.apiUrl}/me`, { headers: this.getHeaders() });
  }

  // Actualiza los datos
  updateMiTaller(data: any): Observable<any> {
    return this.http.put(`${this.apiUrl}/me`, data, { headers: this.getHeaders() });
  }

  // Horarios
  agregarHorario(horario: any): Observable<any> {
    return this.http.post(`${this.apiUrl.replace('/talleres', '')}/taller-config/horarios`, horario, { headers: this.getHeaders() });
  }

  actualizarHorario(horarioId: number, horario: any): Observable<any> {
    return this.http.put(`${this.apiUrl.replace('/talleres', '')}/taller-config/horarios/${horarioId}`, horario, { headers: this.getHeaders() });
  }

  eliminarHorario(horarioId: number): Observable<any> {
    return this.http.delete(`${this.apiUrl.replace('/talleres', '')}/taller-config/horarios/${horarioId}`, { headers: this.getHeaders() });
  }
}