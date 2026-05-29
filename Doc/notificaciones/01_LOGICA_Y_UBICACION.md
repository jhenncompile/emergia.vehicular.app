# 1. Lógica y Ubicación - Sistema de Notificaciones

## 📋 Resumen General

El sistema de notificaciones funciona con **3 canales simultáneamente:**

```
Evento (ej: Asignar técnico)
    ├─ 1. Guardar en BD ✅
    ├─ 2. Enviar por WebSocket → web conectado
    └─ 3. Enviar por FCM → móvil + offline
```

**Flujo:**
1. Endpoint recibe acción (PATCH /incidentes/{id}/asignar-tecnico)
2. Llama a NotificacionService.crear_notificacion()
3. NotificacionService coordina los 3 canales
4. Usuario recibe notificación (inmediata si conectado)

## ✅ Estado Verificado de Eventos Críticos

| Evento | Endpoint que lo dispara | Destinatario | Tipo guardado | Estado actual |
|--------|--------------------------|--------------|---------------|---------------|
| Técnico asignado | `PATCH /api/v1/incidentes/{id}/asignar-tecnico` | Técnico | `tecnico_asignado` | ✅ Funciona |
| Taller acepta | `PATCH /api/v1/incidentes/{id}/aceptar` | Cliente | `incidente_aceptado` | ✅ Funciona |
| Auxilio en camino | `PATCH /api/v1/incidentes/{id}/aceptar` cambia el estado a `en_proceso`; también puede dispararse con `PUT /api/v1/incidentes/{id}` | Cliente, y técnico si ya está asignado | `cambio_estado_en_proceso` / `cambio_estado_en_proceso_tecnico` | ✅ Funciona |
| Taller rechaza | `PATCH /api/v1/incidentes/{id}/rechazar` | Cliente | `incidente_rechazado` | ✅ Funciona |
| Servicio atendido | `PUT /api/v1/incidentes/{id}` con `estado="atendido"` | Cliente y técnico asignado | `cambio_estado_atendido` / `cambio_estado_atendido_tecnico` | ✅ Funciona |
| Cambio de estado general | `PUT /api/v1/incidentes/{id}` | Según estado y relación | `cambio_estado_{estado}` | ✅ Funciona si el estado cambió realmente |

Nota: al aceptar un auxilio, el backend genera dos avisos para el cliente: "solicitud aceptada" y "auxilio en camino", porque aceptar también mueve el incidente a `en_proceso`.

---

## 🔴 CHANNEL 1: WebSocket (Tiempo Real Web)

### 🏗️ Arquitectura WebSocket

```
Cliente (Angular)
    ↓ ws://localhost:8000/ws/{usuario_id}
Servidor FastAPI
    ↓ WebSocketManager
    ↓ Mantiene conexiones activas
    ↓ Envía notificaciones JSON
Cliente (Angular) recibe → actualiza UI instantáneamente
```

### 📁 Archivos Backend

**1. Manager de Conexiones**
```
📄 backend/app/websocket/manager.py
   ├─ Clase: WebSocketManager
   ├─ Responsabilidad: Registrar/desregistrar conexiones
   ├─ Métodos:
   │  ├─ connect(usuario_id, websocket) → Registra conexión
   │  ├─ disconnect(usuario_id, websocket) → Desregistra
   │  ├─ send_personal_notification(usuario_id, data) → Envía a usuario
   │  ├─ send_personal_notification_background(usuario_id, data) → Programa envío desde endpoints sync/async
   │  ├─ send_to_multiple_users(usuario_ids, data) → Envía a varios
   │  ├─ get_connected_users() → Lista usuarios conectados
   │  └─ is_user_connected(usuario_id) → ¿Está conectado?
   └─ Instancia: manager = WebSocketManager()
```

**2. Endpoint WebSocket**
```
📄 backend/app/api/v1/endpoints/notificaciones.py
   ├─ Route: @router.websocket("/ws/{usuario_id}")
   ├─ Responsabilidad: Aceptar conexión + mantenerla viva
   ├─ Flujo:
   │  ├─ await manager.connect(usuario_id, websocket)
   │  ├─ while True: espera heartbeat ("ping")
   │  └─ En desconexión: manager.disconnect()
   └─ Nota: No envía notificaciones directamente, solo mantiene conexión
```

### 📁 Archivos Frontend

**1. Servicio WebSocket**
```
📄 frontend/src/app/core/services/websocket-notificacion.service.ts
   ├─ Clase: WebSocketNotificacionService
   ├─ Responsabilidad: Cliente WebSocket
   ├─ Métodos:
   │  ├─ conectar(usuarioId) → Abre conexión
   │  ├─ desconectar() → Cierra conexión
   │  └─ isConectado() → ¿Está conectado?
   ├─ Observable:
   │  └─ notificaciones$ → Emite cuando llega notificación
   └─ Heartbeat: Envía "ping" cada 30s para mantener viva
```

**2. Dónde Suscribirse**
```
Cualquier componente que quiera recibir notificaciones:

constructor(private wsService: WebSocketNotificacionService) {}

ngOnInit() {
  const usuarioId = localStorage.getItem('usuario_id');
  this.wsService.conectar(usuarioId);
  
  this.wsService.notificaciones$.subscribe(notif => {
    // notif = {titulo, mensaje, tipo, incidente_id, ...}
    // Actualizar UI aquí
    console.log('📨 Notificación:', notif);
  });
}
```

### 🔄 Cómo Funciona WebSocket

```
PASO 1: Usuario abre la web
  └─ main-layout.ts o dashboard.ts llama wsService.conectar(usuarioId)

PASO 2: Cliente se conecta
  └─ new WebSocket('ws://localhost:8000/ws/5')

PASO 3: Servidor acepta
  └─ endpoint /ws/{usuario_id} llama manager.connect()
  └─ Mantiene conexión abierta (espera "ping")

PASO 4: Evento ocurre (ej: asignar técnico)
  └─ PATCH /incidentes/1/asignar-tecnico
  └─ NotificacionService.crear_notificacion()
  └─ manager.send_personal_notification_background(5, {titulo, mensaje, ...})

PASO 5: Servidor envía notificación
  └─ await websocket.send_json({...})

PASO 6: Cliente recibe
  └─ websocket.onmessage(event)
  └─ notificacionesSubject.next(data)
  └─ Todos los subscribers se actualizan
  └─ UI se actualiza (badge de sidebar, etc)
```

### ✅ Ventajas WebSocket
- ⚡ Inmediato (milisegundos)
- 💰 No cuesta (no es Firebase)
- 🌐 Funciona en web y navegadores
- 🔄 Bidireccional (cliente ↔ servidor)

### ⚠️ Limitaciones WebSocket
- ❌ No funciona si usuario cierra navegador
- ❌ No funciona en offline
- ❌ Solo web (no móvil)

---

## 🟢 CHANNEL 2: Firebase Cloud Messaging (FCM)

### 🏗️ Arquitectura FCM

```
Evento ocurre
    ↓
NotificacionService._enviar_fcm()
    ├─ Obtener token_dispositivo del usuario
    ├─ Crear mensaje Firebase
    └─ messaging.send(message)
        ↓
    Firebase Cloud Messaging
        ├─ Si móvil online → push inmediato
        ├─ Si móvil offline → encola (30 días)
        └─ Si token expirado → eliminar registro
        ↓
    Dispositivo recibe notificación
    ├─ Mostrar badge
    ├─ Reproducir sonido
    └─ Usuario abre app
```

### 📁 Archivos Backend

**1. Método FCM en Servicio**
```
📄 backend/app/services/notificacion_service.py
   ├─ Método: _enviar_fcm(db, usuario_id, titulo, mensaje, incidente_id)
   ├─ Responsabilidad: Enviar push por Firebase
   ├─ Flujo:
   │  ├─ 1. Obtener tokens: token_crud.obtener_tokens_usuario(usuario_id)
   │  ├─ 2. Para cada token:
   │  │  ├─ Crear mensaje con messaging.Message()
   │  │  ├─ Enviar: messaging.send(message)
   │  │  └─ Si falla: eliminar token expirado
   │  └─ 3. Retornar True si al menos uno se envió
   └─ Integración: Llamada automática desde crear_notificacion()
```

**2. CRUD para Tokens**
```
📄 backend/app/crud/crud_notificacion.py
   ├─ Clase: CRUDToken
   ├─ Método: obtener_tokens_usuario(db, usuario_id)
   │  └─ SELECT * FROM token_dispositivo WHERE usuario_id = {id}
   └─ Retorna: Lista de objetos TokenDispositivo
```

**3. Endpoint para Registrar Token**
```
📄 backend/app/api/v1/endpoints/notificaciones.py
   ├─ Route: @router.post("/tokens")
   ├─ Responsabilidad: Registrar token FCM del dispositivo
   ├─ Recibe:
   │  ├─ usuario_id
   │  ├─ token_fcm (del dispositivo)
   │  └─ plataforma ("android", "ios", "web")
   └─ Guarda en tabla: token_dispositivo
```

### 📁 Archivos Frontend / Móvil

**1. Servicio Firebase (ya existe)**
```
📄 frontend/src/app/core/services/firebase.service.ts
   ├─ Método: requestNotificationPermission()
   │  ├─ Pedir permiso al usuario
   │  ├─ Obtener token FCM
   │  └─ Llamar guardarTokenEnBackend()
   └─ Método: guardarTokenEnBackend()
      ├─ POST /notificaciones/tokens
      └─ Enviar: {usuario_id, token_fcm, plataforma}
```

**2. Móvil (Flutter) - Futuro**
```
📄 movil/lib/services/notificacion_service.dart
   └─ Cuando implementes:
      ├─ firebase_messaging.getToken()
      ├─ POST /notificaciones/tokens
      └─ Escuchar onMessage()
```

### 🔄 Cómo Funciona FCM

```
PASO 1: Usuario instala app (móvil o web)
  └─ firebase.requestNotificationPermission()
  └─ Obtiene token: "eiOl3x...nJp2"

PASO 2: Registra token en backend
  └─ POST /notificaciones/tokens
  └─ Guarda en tabla token_dispositivo
  └─ usuario_id: 5, token_fcm: "eiOl3x...", plataforma: "android"

PASO 3: Evento ocurre
  └─ PATCH /incidentes/1/asignar-tecnico
  └─ NotificacionService._enviar_fcm(db, 5, titulo, mensaje, 1)

PASO 4: Obtener tokens
  └─ SELECT * FROM token_dispositivo WHERE usuario_id = 5
  └─ Encuentra: token_fcm = "eiOl3x..."

PASO 5: Enviar con Firebase
  └─ import firebase_admin.messaging as messaging
  └─ message = Message(
       notification=Notification(title, body),
       data={...},
       token="eiOl3x..."
     )
  └─ messaging.send(message)

PASO 6: Firebase maneja entrega
  ├─ ✅ Online → Push inmediato
  ├─ ⏳ Offline → Encola 30 días
  └─ ❌ Token expirado → Eliminar registro

PASO 7: Dispositivo recibe
  └─ Muestra notificación
  └─ Usuario toca → abre app
  └─ App consulta GET /notificaciones/usuario/{id}/historial
```

### ✅ Ventajas FCM
- 📱 Funciona en móvil
- 🔌 Funciona offline (encola)
- 🔊 Sonido y badge nativos
- ⚡ Implementación Firebase (confiable)
- 🎯 Segmentación por tipo

### ⚠️ Limitaciones FCM
- 💰 Requiere cuenta Firebase
- ❌ No es real-time si dispositivo offline (puede esperar minutos)
- 🔐 Necesita credentials JSON (firebase-admin)

---

## 🟣 CHANNEL 3: Base de Datos (Fallback)

### Propósito
Almacenar notificaciones **permanentemente** para consulta:
- Si WebSocket falla
- Si FCM falla
- Si usuario no tiene token FCM
- Historial para auditoría

### 📁 Ubicación
```
📄 backend/app/models/notificacion.py
   └─ Tabla: notificacion
      ├─ id (PK)
      ├─ usuario_id (FK)
      ├─ incidente_id (FK)
      ├─ titulo
      ├─ mensaje
      ├─ tipo
      ├─ leido (Boolean)
      └─ fecha_envio (Timestamp)

📄 backend/app/crud/crud_notificacion.py
   ├─ crear_notificacion() → INSERT
   ├─ obtener_no_leidas() → SELECT leido = False
   └─ obtener_historial() → SELECT * ORDER BY fecha DESC

📄 backend/app/api/v1/endpoints/notificaciones.py
   ├─ GET /usuario/{id}/pendientes → No leídas
   └─ GET /usuario/{id}/historial → Todas
```

### 🔄 Cuándo se usa
```
1. Evento ocurre → siempre se guarda en BD
2. WebSocket enviado → si conectado
3. FCM enviado → si tiene token
4. Usuario abre web/app → consulta GET /notificaciones/usuario/{id}/historial
5. Lee notificación → PATCH /{id}/leer (leido = True)
```

---

## 🔀 Comparación de Canales

| Característica | WebSocket | FCM | BD |
|---------------|-----------|-----|-----|
| **Tiempo Real** | ✅ <100ms | ⚠️ 1-5s | ❌ Manual |
| **Web** | ✅ | ⚠️ | ✅ |
| **Móvil** | ❌ | ✅ | ✅ |
| **Offline** | ❌ | ✅ (30d) | ✅ |
| **Costo** | 🆓 | 🆓 | 🆓 |
| **Fallback** | BD | BD | N/A |
| **Requiere Config** | ❌ | ⚠️ (Firebase) | ❌ |
| **Sonido/Badge** | ❌ | ✅ | ❌ |

---

## 📊 Flujo Completo Integrado

```
Usuario abre web en browser
  ├─ wsService.conectar(5) ← WebSocket
  └─ firebase.requestPermission() ← FCM

Usuario en navegador VIENDO dashboard
  └─ Admin asigna técnico: PATCH /incidentes/1/asignar-tecnico
     ├─ NotificacionService.crear_notificacion()
     │  ├─ 1. Guardar en BD ✅
     │  ├─ 2. manager.send_personal_notification_background() → WebSocket
     │  │  └─ ⚡ Usuario ve badge actualizado al instante
     │  └─ 3. _enviar_fcm() → Firebase
     │     └─ (No usado si solo en web, pero registrado)
     └─ Usuario recibe notificación

Usuario en MÓVIL
  └─ Mismo evento: PATCH /incidentes/1/asignar-tecnico
     ├─ NotificacionService.crear_notificacion()
     │  ├─ 1. Guardar en BD ✅
     │  ├─ 2. manager.send_personal_notification_background() → WebSocket
     │  │  └─ (No conectado, WebSocket falla gracefully)
     │  └─ 3. _enviar_fcm() → Firebase
     │     └─ 📱 Push inmediato al móvil
     └─ Usuario recibe notificación push

Usuario OFFLINE
  └─ Mismo evento: PATCH /incidentes/1/asignar-tecnico
     ├─ NotificacionService.crear_notificacion()
     │  ├─ 1. Guardar en BD ✅
     │  ├─ 2. manager.send_personal_notification_background() → WebSocket
     │  │  └─ (Falla, no conectado)
     │  └─ 3. _enviar_fcm() → Firebase
     │     └─ 📱 FCM encola la notificación
     └─ Cuando usuario conecta → recibe push

Usuario abre web DESPUÉS
  └─ GET /notificaciones/usuario/5/historial
     ├─ Obtiene todas las notificaciones de BD
     └─ Ve el historial (aunque haya estado offline)
```

---

## 🎯 Resumen para Desarrolladores

**Para AGREGAR una nueva notificación:**
1. Ubicarse en endpoint relevante (ej: /asignar-tecnico)
2. Llamar: `NotificacionService.notificar_xxxx(...)`
3. ✅ Automáticamente:
   - Se guarda en BD
   - Se envía por WebSocket (si conectado)
   - Se envía por FCM (si tiene token)
   - Se puede consultar por API

**No necesitas hacer nada más.** El sistema es automático.

---

**Versión:** 1.0  
**Fecha:** 2026-05-27  
**Estado:** Completo y auditado para eventos críticos
