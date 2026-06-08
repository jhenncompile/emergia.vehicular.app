import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';

@Component({
  selector: 'app-landing',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './landing.html',
  styleUrls: ['./landing.css']
})
export class LandingComponent {
  private router = inject(Router);

  irALogin() {
    this.router.navigate(['/login']);
  }

  irARegistro() {
    this.router.navigate(['/registro-taller']);
  }

  irAPlanPremium() {
    const token = localStorage.getItem('token');
    if (token) {
      this.router.navigate(['/perfil-taller'], { queryParams: { checkout: 'true' } });
    } else {
      this.router.navigate(['/registro-taller'], { queryParams: { checkout: 'true' } });
    }
  }
}