import { Component, inject, OnInit, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TalleresService } from '../../core/services/talleres';
import * as L from 'leaflet';
import { ActivatedRoute } from '@angular/router';

@Component({
  selector: 'app-perfil-taller',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './perfil-taller.html',
  styleUrl: './perfil-taller.css'
})
export class PerfilTallerComponent implements OnInit {
  private talleresService = inject(TalleresService);
  private zone = inject(NgZone);
  private cdr = inject(ChangeDetectorRef);
  private route = inject(ActivatedRoute);
  private map: any;
  private marker: any;

  taller: any = {
    nombre: '',
    direccion: '',
    telefono: '',
    latitud: -17.7833,
    longitud: -63.1821,
    estado: true,
    especialidades_activas: [],
    horarios: [],
    esta_abierto_ahora: false
  };

  cargando: boolean = false;
  mensaje: string = '';
  
  // Edición de horarios
  editandoHorarios: boolean = false;
  horarioEnEdicion: any = null;
  horariosAnadidos: any[] = [];
  diasSemana = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'];
  
  // Método para obtener días disponibles para una fila específica
  getDiasDisponibles(indexActual: number): string[] {
    const normalizarDia = (dia: string) => dia.toLowerCase()
      .replace('á', 'a')
      .replace('é', 'e')
      .replace('í', 'i')
      .replace('ó', 'o')
      .replace('ú', 'u')
      .replace('ñ', 'n');
    
    const diasUsados = this.taller.horarios.map((h: any) => normalizarDia(h.dia));
    // Excluir días de OTRAS filas, pero NO la fila actual
    const diasDeOtrasFila = this.horariosAnadidos
      .map((h: any, i: number) => i !== indexActual ? normalizarDia(h.dia) : null)
      .filter(d => d !== null);
    
    return this.diasSemana.filter(d => !diasUsados.includes(d) && !diasDeOtrasFila.includes(d));
  }

  ngOnInit() {
    this.cargarDatos();
  }

  cargarDatos() {
    this.talleresService.getMiTaller().subscribe({
      next: (data) => {
        this.taller = data;
        // Normalizar días (remover tildes) y ordenar horarios
        if (this.taller.horarios) {
          const normalizarDia = (dia: string) => dia.toLowerCase()
            .replace('á', 'a')
            .replace('é', 'e')
            .replace('í', 'i')
            .replace('ó', 'o')
            .replace('ú', 'u')
            .replace('ñ', 'n');
          
          this.taller.horarios = this.taller.horarios.map((h: any) => ({
            ...h,
            dia: normalizarDia(h.dia)
          }));
          this.taller.horarios = this.ordenarHorarios(this.taller.horarios);
        }
        this.cdr.detectChanges();
        this.initMap();
        
        // Si viene con checkout=true y no es premium, gatillar suscripción de Stripe
        const checkoutParam = this.route.snapshot.queryParams['checkout'];
        if (checkoutParam === 'true' && this.taller.plan_suscripcion !== 'premium') {
          this.suscribirPremium();
        }
      },
      error: (err) => {
        console.error('Error al cargar taller', err);
        this.initMap();
      }
    });
  }

  // --- LÓGICA DEL MAPA (Se mantiene igual) ---
  private initMap() {
    if (this.map) { this.map.remove(); }
    this.map = L.map('map').setView([this.taller.latitud, this.taller.longitud], 15);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(this.map);
    
    const customIcon = L.icon({
      iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
      shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
      iconSize: [25, 41],
      iconAnchor: [12, 41]
    });

    this.marker = L.marker([this.taller.latitud, this.taller.longitud], { 
      icon: customIcon,
      draggable: true 
    }).addTo(this.map);

    this.map.on('click', (e: any) => this.actualizarCoordenadas(e.latlng.lat, e.latlng.lng));
    this.marker.on('dragend', () => {
      const position = this.marker.getLatLng();
      this.actualizarCoordenadas(position.lat, position.lng);
    });
  }

  private actualizarCoordenadas(lat: number, lng: number) {
    this.zone.run(() => {
      this.taller.latitud = lat;
      this.taller.longitud = lng;
    });
    this.marker.setLatLng([lat, lng]);
  }

  guardar() {
    this.cargando = true;
    this.mensaje = '';
    // Enviamos el objeto taller al backend (ignorará especialidades_activas al ser property)
    this.talleresService.updateMiTaller(this.taller).subscribe({
      next: () => {
        this.mensaje = '¡Perfil actualizado correctamente! ✅';
        this.cargando = false;
        setTimeout(() => this.mensaje = '', 3000);
      },
      error: (err) => {
        this.mensaje = 'Error al actualizar los datos ❌';
        this.cargando = false;
      }
    });
  }

  suscribirPremium() {
    this.cargando = true;
    this.talleresService.suscribirPremium().subscribe({
      next: (res: any) => {
        if (res.checkout_url) {
          window.location.href = res.checkout_url;
        }
        this.cargando = false;
      },
      error: (err) => {
        this.mensaje = 'Error al generar checkout ❌';
        this.cargando = false;
      }
    });
  }

  cancelarSuscripcion() {
    if(confirm('¿Estás seguro de cancelar tu plan Premium? Perderás los beneficios limitados al terminar el periodo.')) {
      this.cargando = true;
      this.talleresService.cancelarSuscripcion().subscribe({
        next: () => {
          this.mensaje = 'Suscripción cancelada ✅';
          this.cargando = false;
          this.cargarDatos();
        },
        error: (err) => {
          this.mensaje = 'Error al cancelar suscripción ❌';
          this.cargando = false;
        }
      });
    }
  }

  // Formato de hora (convierte "08:00:00" a "08:00")
  formatTime(time: string | any): string {
    if (!time) return '';
    if (typeof time === 'string') {
      return time.substring(0, 5); // "HH:MM"
    }
    return time;
  }

  // Ordenar horarios por día de la semana
  private ordenarHorarios(horarios: any[]): any[] {
    const diasOrden = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'];
    
    return horarios.sort((a, b) => {
      const indexA = diasOrden.indexOf(a.dia.toLowerCase());
      const indexB = diasOrden.indexOf(b.dia.toLowerCase());
      return indexA - indexB;
    });
  }

  // --- EDICIÓN DE HORARIOS ---
  iniciarEdicionHorarios() {
    this.editandoHorarios = true;
    this.horariosAnadidos = [];
    this.agregarHorarioTemp(); // Agregar una fila vacía automáticamente
    this.cdr.detectChanges();
  }

  agregarHorarioTemp() {
    const nuevoHorario = {
      dia: '',
      hora_apertura: '08:00',
      hora_cierre: '18:00'
    };
    this.horariosAnadidos.push(nuevoHorario);
    this.cdr.detectChanges();
  }

  guardarHorarios() {
    this.cargando = true;
    let completados = 0;
    const total = this.horariosAnadidos.length;

    if (total === 0) {
      this.editandoHorarios = false;
      this.cargando = false;
      return;
    }

    this.horariosAnadidos.forEach((horario) => {
      if (!horario.dia) {
        this.mensaje = 'Por favor selecciona un día para todos los horarios ❌';
        this.cargando = false;
        return;
      }

      const payload = {
        taller_id: this.taller.id || 0,
        dia: this.normalizarDiaAlGuardar(horario.dia),
        hora_apertura: horario.hora_apertura,
        hora_cierre: horario.hora_cierre
      };

      this.talleresService.agregarHorario(payload).subscribe({
        next: () => {
          completados++;
          if (completados === total) {
            this.mensaje = '¡Horarios agregados correctamente! ✅';
            this.cargando = false;
            this.editandoHorarios = false;
            this.horariosAnadidos = [];            this.cdr.detectChanges();            this.cargarDatos();
          }
        },
        error: (err) => {
          this.mensaje = 'Error al guardar horarios ❌';
          this.cargando = false;
        }
      });
    });
  }

  editarHorario(horario: any) {
    console.log('Editando horario:', horario);
    this.horarioEnEdicion = { ...horario };
    this.cdr.detectChanges();
  }

  guardarEdicionHorario() {
    if (!this.horarioEnEdicion) return;

    this.cargando = true;
    const payload = {
      taller_id: this.taller.id,
      dia: this.normalizarDiaAlGuardar(this.horarioEnEdicion.dia),
      hora_apertura: this.horarioEnEdicion.hora_apertura,
      hora_cierre: this.horarioEnEdicion.hora_cierre
    };

    this.talleresService.actualizarHorario(this.horarioEnEdicion.id, payload).subscribe({
      next: () => {
        this.mensaje = '¡Horario actualizado! ✅';
        this.horarioEnEdicion = null;
        this.cargando = false;        this.cdr.detectChanges();        this.cargarDatos();
      },
      error: (err) => {
        console.error('Error actualizar horario:', err);
        this.mensaje = 'Error al actualizar horario ❌';
        this.cargando = false;
      }
    });
  }

  cancelarEdicion() {
    this.horarioEnEdicion = null;
    this.editandoHorarios = false;
    this.horariosAnadidos = [];
    this.cdr.detectChanges();
  }

  eliminarHorario(horarioId: number) {
    if (confirm('¿Deseas eliminar este horario?')) {
      this.talleresService.eliminarHorario(horarioId).subscribe({
        next: () => {
          this.mensaje = '¡Horario eliminado! ✅';          this.cdr.detectChanges();          this.cargarDatos();
        },
        error: () => {
          this.mensaje = 'Error al eliminar horario ❌';
        }
      });
    }
  }

  // Convertir días sin tildes a días con tildes para guardar en backend
  private normalizarDiaAlGuardar(dia: string): string {
    const mapa: any = {
      'lunes': 'lunes',
      'martes': 'martes',
      'miercoles': 'miércoles',
      'jueves': 'jueves',
      'viernes': 'viernes',
      'sabado': 'sábado',
      'domingo': 'domingo'
    };
    return mapa[dia.toLowerCase()] || dia;
  }

  // Para ngFor trackBy
  trackByIndex(index: number): number {
    return index;
  }

  // Cuando cambia el día en el select, actualizar diasDisponibles
  onDiaChange() {
    this.cdr.detectChanges();
  }

  // Eliminar un día temporal del formulario
  eliminarDiaTemp(index: number) {
    this.horariosAnadidos.splice(index, 1);
    this.cdr.detectChanges();
  }
}