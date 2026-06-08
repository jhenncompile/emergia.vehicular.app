import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../core/services/auth';

@Component({
  selector: 'app-registro-taller',
  standalone: true,
  // 🚩 IMPORTANTE: Aquí agregamos ReactiveFormsModule para que no dé el error de JIT y RouterLink para navegación SPA
  imports: [CommonModule, ReactiveFormsModule, RouterLink],
  templateUrl: './registro-taller.html',
  styleUrls: ['./registro-taller.css']
})
export class RegistroTallerComponent {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);

  hidePassword = true;

  togglePasswordVisibility() {
    this.hidePassword = !this.hidePassword;
  }

  registerForm: FormGroup = this.fb.group({
    nombre: ['', [Validators.required]],
    correo: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(6)]],
    taller: this.fb.group({
      nombre: ['', [Validators.required]],
      direccion: ['', [Validators.required]],
      latitud: [-17.7833],
      longitud: [-63.1821],
      comision_porcentaje: [10]
    })
  });

  onSubmit() {
    if (this.registerForm.valid) {
      this.authService.registerTaller(this.registerForm.value as any).subscribe({
        next: () => {
          alert('¡Taller registrado con éxito!');
          this.router.navigate(['/dashboard']);
        },
        error: (err) => {
          console.error(err);
          alert(err.error?.detail || 'Error al registrar el taller');
        }
      });
    }
  }
}