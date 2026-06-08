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
import { NotificacionesComponent } from './features/notificaciones/notificaciones';


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
  { path: 'tecnico/notificaciones', component: NotificacionesComponent },
  
  {
    path: '',
    component: MainLayoutComponent,
    children: [
      { path: 'dashboard', component: DashboardComponent },
      { path: 'bitacora', component: BitacoraComponent },
      { path: 'finanzas', component: FinanzasComponent },
      { path: 'incidentes', component: AuxiliosComponent },
      { path: 'perfil-taller', component: PerfilTallerComponent }, // 👈 Revisa que el nombre sea IDÉNTICO al routerLink
      { path: 'calificaciones', loadComponent: () => import('./features/calificaciones/calificaciones').then(m => m.CalificacionesComponent) },
      { path: 'analisis', loadComponent: () => import('./features/analisis/analisis').then(m => m.Analisis) },
      { path: 'ranking', loadComponent: () => import('./features/ranking-talleres/ranking-talleres').then(m => m.RankingTalleres) },
      { path: 'administradores', component: GestionAdminsComponent },
      { path: 'notificaciones', component: NotificacionesComponent },
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      { path: 'historial', component: HistorialComponent },
      { path: 'mi-perfil', loadComponent: () => import('./features/mi-perfil/mi-perfil').then(m => m.MiPerfilComponent) }
    ]
  },
  // Este es el que te está mandando al login si algo falla arriba
  { path: '**', redirectTo: '/login' }
];
