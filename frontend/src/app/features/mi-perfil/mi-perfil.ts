import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { environment } from '../../../environments/environment';

@Component({
  selector: 'app-mi-perfil',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './mi-perfil.html',
  styleUrl: './mi-perfil.css'
})
export class MiPerfilComponent implements OnInit {
  private http = inject(HttpClient);

  usuario: any = {
    nombre: '',
    apellido: '',
    correo: '',
    telefono: '',
    ciudad: '',
    direccion: '',
    rol_id: null
  };

  cargando: boolean = false;
  mensaje: string = '';

  ngOnInit() {
    this.cargarPerfil();
  }

  cargarPerfil() {
    this.cargando = true;
    const token = localStorage.getItem('token');
    if (!token) return;

    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    this.http.get<any>(`${environment.apiUrl}/usuarios/me`, { headers }).subscribe({
      next: (data) => {
        this.usuario = data;
        this.cargando = false;
      },
      error: (err) => {
        console.error('Error al cargar perfil', err);
        this.cargando = false;
      }
    });
  }

  guardar() {
    this.cargando = true;
    this.mensaje = '';
    const token = localStorage.getItem('token');
    if (!token) return;

    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    
    const payload = {
      nombre: this.usuario.nombre,
      apellido: this.usuario.apellido,
      telefono: this.usuario.telefono,
      ciudad: this.usuario.ciudad,
      direccion: this.usuario.direccion
    };

    this.http.put<any>(`${environment.apiUrl}/usuarios/me`, payload, { headers }).subscribe({
      next: (res) => {
        this.usuario = res;
        this.mensaje = '¡Perfil actualizado correctamente! ✅';
        this.cargando = false;
        
        if (res.nombre) {
          localStorage.setItem('nombre', res.nombre);
        }
        
        setTimeout(() => this.mensaje = '', 3000);
      },
      error: (err) => {
        console.error('Error al actualizar perfil', err);
        this.mensaje = 'Error al actualizar los datos ❌';
        this.cargando = false;
      }
    });
  }

  getRolLabel(rolId: number): string {
    const roles: Record<number, string> = {
      1: 'Administrador de Taller',
      2: 'Cliente / Propietario',
      3: 'Técnico / Mecánico'
    };
    return roles[rolId] || 'Usuario';
  }
}
