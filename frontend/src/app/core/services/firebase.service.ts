import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { BehaviorSubject, Observable } from 'rxjs';
import { environment } from '../../../environments/environment';
// Firebase modular SDK
import { initializeApp } from 'firebase/app';
import { getMessaging, onMessage, getToken, Messaging } from 'firebase/messaging';

@Injectable({ providedIn: 'root' })
export class FirebaseService {
  private http = inject(HttpClient);
  public notificaciones$ = new BehaviorSubject<any>(null);
  private messaging!: Messaging;

  get notificaciones(): Observable<any> {
    return this.notificaciones$.asObservable();
  }

  constructor() {
    this.inicializarFirebase();
  }

  private inicializarFirebase() {
    try {
      if (this.soportaNotificaciones()) {
        const app = initializeApp(environment.firebase);
        this.messaging = getMessaging(app);
        console.log('✅ Firebase inicializado correctamente');
        this.setupForegroundNotifications();
      }
    } catch (error) {
      console.error('❌ Error al inicializar Firebase:', error);
    }
  }

  /**
   * Configura la escucha de notificaciones en primer plano con fix para TS Strict
   */
  private setupForegroundNotifications() {
    if (!this.messaging) return;

    onMessage(this.messaging, (payload: any) => {
      console.log('📢 Notificación recibida:', payload);
      
      // FIX TS4111: Usamos acceso por llave [''] para evitar errores de índice
      const data = payload.data || {};
      
      const notificacion = {
        tipo: data['tipo'] || 'notificacion',
        timestamp: new Date().toISOString(),
        incidente: {
          id: data['id'] || '',
          placa_vehiculo: data['placa_vehiculo'] || 'N/A',
          latitud: parseFloat(data['latitud'] || '0'),
          longitud: parseFloat(data['longitud'] || '0'),
          distancia_km: parseFloat(data['distancia_km'] || '0'),
          clasificacion: data['clasificacion'] || 'N/A',
          estado: data['estado'] || 'pendiente',
        },
        notification: {
          title: payload.notification?.title,
          body: payload.notification?.body,
        }
      };

      this.notificaciones$.next(notificacion);
    });
  }

  /**
   * Proceso completo de permisos y obtención de token
   */
  async requestNotificationPermission(): Promise<string | null> {
    try {
      const permission = await Notification.requestPermission();
      
      if (permission !== 'granted') {
        console.warn('⚠️ Permiso denegado');
        return null;
      }

      console.log('✅ Permiso otorgado');
      const token = await getToken(this.messaging, {
        vapidKey: environment.vapidKey
      });

      if (token) {
        localStorage.setItem('fcmToken', token);
        await this.guardarTokenEnBackend(token);
        return token;
      }
      
      return null;
    } catch (error) {
      console.error('❌ Error en flujo de permisos:', error);
      return null;
    }
  }

  /**
   * Registro en Backend con reglas Multi-Tenant
   */
  public async guardarTokenEnBackend(token?: string): Promise<boolean> {
    try {
      // Si no pasan token, intentamos sacarlo del localStorage
      const fcmToken = token || localStorage.getItem('fcmToken');
      const userId = localStorage.getItem('usuario_id');
      const bearerToken = localStorage.getItem('token');

      if (!userId || !fcmToken || !bearerToken) {
        console.log('ℹ️ No hay datos para vincular token (usuario_id, fcmToken o token faltante)');
        return false;
      }

      const payload = {
        usuario_id: Number(userId),
        token_fcm: fcmToken,
        plataforma: 'web'
      };

      // Usamos el token Bearer para seguridad (REGLA CRÍTICA)
      const headers = new HttpHeaders().set('Authorization', `Bearer ${bearerToken}`);

      return new Promise((resolve) => {
        this.http.post(`${environment.apiUrl}/notificaciones/tokens`, payload, { headers })
          .subscribe({
            next: () => {
              console.log('✅ Token FCM vinculado exitosamente al backend');
              resolve(true);
            },
            error: (err) => {
              console.error('❌ Error vinculando token al backend:', err);
              resolve(false);
            }
          });
      });
    } catch (error) {
      console.error('❌ Exception en guardarTokenEnBackend:', error);
      return false;
    }
  }

  // --- MÉTODOS DE SOPORTE (Los que se habían perdido) ---

  soportaNotificaciones(): boolean {
    return 'Notification' in window && 'serviceWorker' in navigator;
  }

  obtenerEstadoPermiso(): NotificationPermission {
    return 'Notification' in window ? Notification.permission : 'denied';
  }
}