import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router'; // 🆕 Importar RouterLink
import { AuthService, LoginRequest } from '../../../core/services/auth';

@Component({
  selector: 'app-login',
  standalone: true,
  // 🆕 Agregamos RouterLink al arreglo de imports
  imports: [CommonModule, ReactiveFormsModule, RouterLink], 
  templateUrl: './login.html', 
  styleUrls: ['./login.css'] 
})
export class LoginComponent {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);

  loginForm = this.fb.group({
    username: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(3)]]
  });

  errorMessage = '';
  isLoading = false;

  onSubmit() {
    if (this.loginForm.invalid) return;

    this.isLoading = true;
    this.errorMessage = '';

    const credentials: LoginRequest = {
      username: this.loginForm.value.username!,
      password: this.loginForm.value.password!
    };

    this.authService.login(credentials).subscribe({
      next: (res: any) => { 
        this.isLoading = false;
        console.log('Login exitoso, guardando token y redirigiendo...');
        localStorage.setItem('token', res.access_token);
        
        // Redireccionar según rol
        const rolId = this.authService.getRolId();
        console.log('Rol:', rolId);
        
        if (rolId === 3) {
          // Técnico
          this.router.navigate(['/tecnico/dashboard']);
        } else if (rolId === 1) {
          // Admin
          this.router.navigate(['/dashboard']);
        } else {
          // Cliente u otro rol
          this.router.navigate(['/']);
        }
      },
      error: (err) => {
        this.isLoading = false;
        this.errorMessage = 'Credenciales incorrectas o error de servidor.';
        console.error(err);
      }
    });
  }
}