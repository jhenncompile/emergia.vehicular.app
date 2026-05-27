import { Routes } from '@angular/router';
import { LoginComponent } from './features/auth/login/login';
import { DashboardComponent } from './features/dashboard/dashboard';
import { MainLayoutComponent } from './shared/layouts/main-layout/main-layout';
import { BitacoraComponent } from './features/bitacora/bitacora';
import { RegistroTallerComponent } from './components/registro-taller/registro-taller';
import { LandingComponent } from './components/landing/landing';
import { GestionAdminsComponent } from './features/gestion-admins/gestion-admins';
import { ForgotPasswordComponent } from './features/auth/forgot-password/forgot-password';
import { ResetPasswordComponent } from './features/auth/reset-password/reset-password';
import { PerfilTallerComponent } from './features/perfil-taller/perfil-taller';
import { AuxiliosComponent } from './features/auxilios/auxilios';
import { FinanzasComponent } from './features/finanzas/finanzas';
import { HistorialComponent } from './features/historial/historial';
import { TecnicoDashboardComponent } from './features/tecnico-dashboard/tecnico-dashboard';
import { TecnicoIncidenteDetalleComponent } from './features/tecnico-dashboard/tecnico-incidente-detalle';


export const routes: Routes = [
  // 1. AGREGA ESTO: pathMatch: 'full' es obligatorio para la ruta raíz
  { path: '', component: LandingComponent, pathMatch: 'full' }, 

  { path: 'login', component: LoginComponent },
  { path: 'forgot-password', component: ForgotPasswordComponent },
  { path: 'reset-password', component: ResetPasswordComponent },
  { path: 'registro-taller', component: RegistroTallerComponent },
  
  // Dashboard del Técnico (sin MainLayout)
  { path: 'tecnico/dashboard', component: TecnicoDashboardComponent },
  { path: 'tecnico/incidente/:id', component: TecnicoIncidenteDetalleComponent },
  
  {
    path: '',
    component: MainLayoutComponent,
    children: [
      { path: 'dashboard', component: DashboardComponent },
      { path: 'bitacora', component: BitacoraComponent },
      { path: 'finanzas', component: FinanzasComponent },
      { path: 'incidentes', component: AuxiliosComponent },
      { path: 'perfil-taller', component: PerfilTallerComponent }, // 👈 Revisa que el nombre sea IDÉNTICO al routerLink
      { path: 'administradores', component: GestionAdminsComponent },
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      { path: 'historial', component: HistorialComponent },
    ]
  },
  // Este es el que te está mandando al login si algo falla arriba
  { path: '**', redirectTo: '/login' }
];