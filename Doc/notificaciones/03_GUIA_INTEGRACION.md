# 3. Guía de Integración y Configuración

## 🚀 Cómo Integrar en Tu Código

### A. Backend (FastAPI)

#### Paso 1: Importar en tus Endpoints

```python
# En cualquier endpoint donde quieras enviar notificación
from app.services.notificacion_service import NotificacionService

@router.patch("/{id}/asignar-tecnico")
def asignar_tecnico(
    db: Session = Depends(deps.get_db),
    id: int,
    tecnico_id: int,
    current_user = Depends(deps.get_current_admin_taller)
):
    # ... lógica del endpoint ...
    
    # ✅ Una sola línea para notificar:
    NotificacionService.notificar_tecnico_asignado(
        db=db,
        tecnico_id=tecnico_id,
        incidente_id=id,
        incidente=incidente_db
    )
```

#### Paso 2: Métodos Disponibles

```python
# Para técnico asignado
NotificacionService.notificar_tecnico_asignado(db, tecnico_id, incidente_id, incidente)

# Para cliente cuando taller acepta
NotificacionService.notificar_incidente_aceptado(db, cliente_id, incidente_id, taller_nombre)

# Para cliente cuando taller rechaza
NotificacionService.notificar_incidente_rechazado(db, cliente_id, incidente_id, taller_nombre, motivo)

# Para cambios de estado
NotificacionService.notificar_cambio_estado(db, incidente, estado_anterior, estado_nuevo)

# Para notificación personalizada
NotificacionService.crear_notificacion(
    db=db,
    usuario_id=5,
    titulo="Mi título",
    mensaje="Mi mensaje",
    tipo="mi_tipo",
    incidente_id=1
)
```

#### Paso 2.1: Eventos verificados en incidentes

| Evento | Código que debe existir | Resultado esperado |
|--------|--------------------------|--------------------|
| Taller acepta | `aceptar_incidente()` llama `notificar_incidente_aceptado()` | Cliente recibe `incidente_aceptado`. |
| Auxilio en camino | `aceptar_incidente()` también llama `notificar_cambio_estado(..., "en_proceso")` | Cliente recibe `cambio_estado_en_proceso`. |
| Taller rechaza | `rechazar_pedido_auxilio()` llama `notificar_incidente_rechazado()` | Cliente recibe `incidente_rechazado`. |
| Estado cambiado manualmente | `actualizar_estado_incidente()` llama `notificar_cambio_estado()` solo si `estado` cambió | Cliente/técnico reciben el aviso correspondiente. |
| Servicio atendido | `PUT /api/v1/incidentes/{id}` con `estado="atendido"` | Cliente y técnico reciben `cambio_estado_atendido`. |

#### Paso 3: Confirmar WebSocket + FCM en Main

```python
# backend/main.py
from app.websocket.manager import manager  # ✅ Importa para cargar

# Ya está integrado, no hay nada extra que configurar
```

---

### B. Frontend (Angular)

#### Paso 1: Inyectar Servicio WebSocket

```typescript
// En tu componente principal (dashboard, main-layout, etc)
import { WebSocketNotificacionService } from './core/services/websocket-notificacion.service';

export class DashboardComponent implements OnInit {
  constructor(
    private wsService: WebSocketNotificacionService,
    private sidebarService: SidebarService  // o el que actualice badges
  ) {}

  ngOnInit() {
    // Conectar WebSocket
    const usuarioId = localStorage.getItem('usuario_id');
    this.wsService.conectar(parseInt(usuarioId!));
    
    // Escuchar notificaciones
    this.wsService.notificaciones$.subscribe(notif => {
      if (notif) {
        console.log('📨 Notificación recibida:', notif);
        
        // ✅ Actualizar UI aquí
        // Opción 1: Recargar notificaciones
        this.sidebarService.cargarNotificacionesNoLeidas();
        
        // Opción 2: Mostrar toast
        this.showToast(notif.titulo, notif.mensaje);
        
        // Opción 3: Reproducir sonido
        this.playNotificationSound();
      }
    });
  }
}
```

#### Paso 2: Actualizar Sidebar (Real-time)

```typescript
// frontend/src/app/shared/components/sidebar/sidebar.ts
export class SidebarComponent implements OnInit {
  private wsService = inject(WebSocketNotificacionService);
  public notificacionesNoLeidas: number = 0;

  ngOnInit() {
    // Cargar inicial
    this.cargarNotificacionesNoLeidas();
    
    // Escuchar cambios por WebSocket
    this.wsService.notificaciones$.subscribe(notif => {
      if (notif) {
        // Al llegar notificación nueva, recargar contador
        this.cargarNotificacionesNoLeidas();
      }
    });
  }

  cargarNotificacionesNoLeidas() {
    const usuarioId = localStorage.getItem('usuario_id');
    const token = localStorage.getItem('token');
    
    if (!usuarioId || !token) return;

    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);

    this.http.get<any[]>(
      `${environment.apiUrl}/notificaciones/usuario/${usuarioId}/pendientes`,
      { headers }
    ).subscribe({
      next: (notificaciones) => {
        this.notificacionesNoLeidas = notificaciones.length;
      },
      error: (err) => {
        console.error('Error cargando notificaciones:', err);
      }
    });
  }
}
```

#### Paso 3: Mostrar Toast (Feedback Visual)

```typescript
// Opción A: Usar librería (ngx-toastr)
constructor(private toastr: ToastrService) {}

showToast(titulo: string, mensaje: string) {
  this.toastr.info(mensaje, titulo, {
    timeOut: 5000,
    positionClass: 'toast-top-right'
  });
}

// Opción B: Toast nativo
showToast(titulo: string, mensaje: string) {
  if ('Notification' in window) {
    new Notification(titulo, { body: mensaje });
  }
}
```

---

## ⚙️ Configuración FCM

### Paso 1: Descargar Credentials

```
1. Ir a Firebase Console
   → https://console.firebase.google.com
2. Proyecto: "emergenciavehicular"
3. Project Settings → Service Accounts
4. Generar nueva clave privada (JSON)
5. Guardar como: backend/.firebase-credentials.json
```

### Paso 2: Instalar Firebase Admin

```bash
cd backend
pip install firebase-admin
```

### Paso 3: Configurar en .env

```bash
# backend/.env
FIREBASE_CREDENTIALS_PATH=/ruta/a/.firebase-credentials.json
```

### Paso 4: Inicializar en main.py

```python
# backend/main.py
import os
import firebase_admin
from firebase_admin import credentials

# Inicializar Firebase (una sola vez)
if not firebase_admin.get_app(name='default', error_on_duplicate=True):
    creds_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
    if creds_path:
        cred = credentials.Certificate(creds_path)
        firebase_admin.initialize_app(cred)
        print("✅ Firebase inicializado correctamente")
    else:
        print("⚠️  FIREBASE_CREDENTIALS_PATH no configurado, FCM desactivado")
```

### Paso 5: Frontend - Registrar Token FCM

```typescript
// frontend/src/app/core/services/firebase.service.ts
// YA EXISTE, solo hay que usarlo

// En tu componente:
constructor(private firebaseService: FirebaseService) {}

ngOnInit() {
  // Pedir permiso y registrar token
  this.firebaseService.requestNotificationPermission();
}
```

---

## 🧪 Testing

### Test 1: WebSocket Conectado

```bash
# Terminal 1: Iniciar backend
cd backend
python -m uvicorn main:app --reload

# Terminal 2: Frontend
cd frontend
yarn start

# En navegador:
1. Abre Developer Tools (F12)
2. Consola → Deberías ver:
   "✅ WebSocket conectado"
3. En Network → WS
   Deberías ver: ws://localhost:8000/ws/5
```

### Test 2: Asignar Técnico → WebSocket Llega

```bash
# En Postman:
1. PATCH http://localhost:8000/api/v1/incidentes/1/asignar-tecnico?tecnico_id=5
2. Body: {}
3. Headers: Authorization: Bearer {token}

# En consola del navegador (técnico):
   "📨 Notificación recibida:"
   {
     id: 100,
     titulo: "🔧 Nuevo incidente asignado",
     mensaje: "Se te ha asignado el incidente #1 en {taller}",
     tipo: "tecnico_asignado",
     incidente_id: 1
   }

# Badge actualizado en sidebar al instante
```

### Test 3: Eventos de aceptación, rechazo y estado

```bash
# Taller acepta:
PATCH http://localhost:8000/api/v1/incidentes/1/aceptar
# Debe crear:
# - tipo = incidente_aceptado
# - tipo = cambio_estado_en_proceso

# Taller rechaza:
PATCH http://localhost:8000/api/v1/incidentes/1/rechazar?motivo=Sin disponibilidad
# Debe crear:
# - tipo = incidente_rechazado

# Servicio atendido:
PUT http://localhost:8000/api/v1/incidentes/1
# Body JSON: {"estado": "atendido"}
# Debe crear:
# - tipo = cambio_estado_atendido
# - tipo = cambio_estado_atendido_tecnico si hay técnico asignado
```

### Test 4: Verificar en BD

```bash
# En DB:
SELECT * FROM notificacion WHERE tipo = 'tecnico_asignado' ORDER BY id DESC LIMIT 5;

# Deberías ver la notificación creada
```

### Test 5: FCM (si Firebase configurado)

```bash
# En backend/app/services/notificacion_service.py
# Busca los logs:

"📤 FCM enviado a android: bk3023..."
# Significa que la push fue enviada a Firebase

# Si ves: "ℹ️  FCM: usuario X no tiene tokens registrados"
# Significa que el usuario no tiene dispositivos registrados
```

---

## 🐛 Debugging

### WebSocket No Conecta

```python
# Backend log:
logger.info(f"✅ Usuario 5 conectado")
# Si NO ves esto → verificar:
# 1. ¿usuario_id correcto en URL?
# 2. ¿Firewall bloqueando puerto 8000?
# 3. ¿CORS configurado?

# Frontend console:
"❌ WebSocket cerrado"
# Verificar:
# 1. Está wsService.conectar() siendo llamado?
# 2. URL correcta?
# 3. Backend corriendo?
```

### Notificación No Llega

```
Checklist:
1. ¿Se creó en BD?
   SELECT * FROM notificacion ORDER BY id DESC LIMIT 1;
   
2. ¿WebSocket conectado?
   Consola browser: "✅ WebSocket conectado"
   
3. ¿Usuario conectado en servidor?
   Backend logs: "Usuario X conectado"
   
4. ¿FCM token registrado?
   SELECT * FROM token_dispositivo WHERE usuario_id = X;
   
5. ¿Firebase configurado?
   Backend logs: "✅ Firebase inicializado"
```

### Token FCM Expirado

```
Síntoma: Notificación se guarda en BD pero NO llega a móvil

Solución automática:
  1. NotificacionService._enviar_fcm()
  2. Recibe InvalidArgumentError
  3. token_crud.delete(db, id=token_obj.id)
  4. Registro eliminado automáticamente

Verificación:
  SELECT * FROM token_dispositivo WHERE usuario_id = X;
  El token expirado ya no está
```

---

## 📱 Integración Móvil (Futuro)

### Flutter

```dart
// En tu servicio de notificaciones Flutter:

// 1. Obtener token FCM
FirebaseMessaging messaging = FirebaseMessaging.instance;
String? token = await messaging.getToken();

// 2. Registrar en backend
var response = await http.post(
  Uri.parse('http://localhost:8000/notificaciones/tokens'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'usuario_id': userId,
    'token_fcm': token,
    'plataforma': 'android' // o 'ios'
  })
);

// 3. Escuchar mensajes
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  print('Notificación recibida: ${message.notification?.title}');
  // Mostrar en app
});

// 4. Manejo cuando app en background
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
```

---

## 🔐 Seguridad en Producción

### 1. Agregar Autenticación JWT a WebSocket

```python
# backend/app/api/v1/endpoints/notificaciones.py
from app.api import deps

@router.websocket("/ws/{usuario_id}/{token}")
async def websocket_notificaciones(
    websocket: WebSocket,
    usuario_id: int,
    token: str
):
    # Validar token JWT
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        if payload.get("sub") != usuario_id:
            await websocket.close(code=4001, reason="Unauthorized")
            return
    except:
        await websocket.close(code=4001, reason="Unauthorized")
        return
    
    # Resto igual...
```

### 2. Rate Limiting

```python
# Limitar envíos por usuario por minuto
from slowapi import Limiter

limiter = Limiter(key_func=get_remote_address)

@router.post("/tokens")
@limiter.limit("5/minute")
def registrar_token_dispositivo(...):
    pass
```

### 3. Validación de Tokens FCM

```python
# En _enviar_fcm()
if not token_obj.token_fcm or len(token_obj.token_fcm) < 50:
    logger.warning(f"Token inválido para {usuario_id}")
    token_crud.delete(db, id=token_obj.id)
    return False
```

---

## 📊 Monitoreo

### Logs Importantes

```
✅ ¿Sistema funcionando?

Backend:
  ✅ "Usuario {id} conectado"        → WebSocket OK
  ✅ "Notificación creada en BD"      → BD OK
  ✅ "FCM enviado a android"          → FCM OK
  ⚠️ "ℹ️  FCM: usuario no tiene tokens" → OK (sin móvil)
  ❌ "Error creando notificación"     → PROBLEMA

Frontend:
  ✅ "✅ WebSocket conectado"         → Conexión OK
  ✅ "📨 Notificación recibida"       → Recepción OK
  ❌ "👋 WebSocket desconectado"      → Reconectando (normal)
```

### Queries de Monitoring

```sql
-- ¿Cuántas notificaciones por usuario?
SELECT usuario_id, COUNT(*) as total 
FROM notificacion 
GROUP BY usuario_id 
ORDER BY total DESC;

-- ¿Cuántas sin leer?
SELECT COUNT(*) as no_leidas 
FROM notificacion 
WHERE leido = FALSE;

-- ¿Tokens registrados por plataforma?
SELECT plataforma, COUNT(*) as total 
FROM token_dispositivo 
GROUP BY plataforma;

-- ¿Últimas notificaciones?
SELECT id, usuario_id, titulo, tipo, fecha_envio 
FROM notificacion 
ORDER BY fecha_envio DESC 
LIMIT 20;
```

---

## ✅ Checklist de Integración Completa

- [x] WebSocket endpoint implementado (`/ws/{usuario_id}`)
- [x] WebSocketManager importado
- [x] NotificacionService integrado en endpoints críticos
- [x] Frontend servicio WebSocket creado
- [x] Dashboard técnico se conecta al WebSocket
- [x] Centro de notificaciones disponible para admin y técnico
- [ ] Firebase Admin instalado (pip install firebase-admin)
- [ ] Credentials JSON descargado
- [ ] .env con FIREBASE_CREDENTIALS_PATH
- [ ] main.py inicializa Firebase
- [ ] Frontend registra tokens FCM
- [x] Testing de WebSocket/TypeScript OK
- [ ] Testing de FCM OK (si Firebase configurado)
- [ ] Logs verificados
- [ ] Producción: JWT agregado a WebSocket
- [ ] Producción: Rate limiting configurado

---

**Versión:** 1.0  
**Fecha:** 2026-05-27  
**Estado:** Integrado para WebSocket/BD; FCM queda condicionado a configuración Firebase
