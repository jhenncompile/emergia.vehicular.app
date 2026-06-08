import { Component, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router'; // 🆕 Importar ActivatedRoute
import { AuthService, LoginRequest } from '../../../core/services/auth';

@Component({
  selector: 'app-login',
  standalone: true,
  // 🆕 Agregamos RouterLink al arreglo de imports
  imports: [CommonModule, ReactiveFormsModule, RouterLink], 
  templateUrl: './login.html', 
  styleUrls: ['./login.css'] 
})
export class LoginComponent implements OnInit {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  loginForm = this.fb.group({
    username: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(3)]]
  });

  errorMessage = '';
  isLoading = false;
  isCheckout = false;

  ngOnInit() {
    this.isCheckout = this.route.snapshot.queryParams['checkout'] === 'true';
  }

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
          if (this.isCheckout) {
            this.router.navigate(['/perfil-taller'], { queryParams: { checkout: 'true' } });
          } else {
            this.router.navigate(['/dashboard']);
          }
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