# Flujo actual de IA en backend y movil

## Objetivo

Este documento describe el flujo real de IA despues de integrar el reporte movil con audio, imagen, evidencias y la primera base de asignacion inteligente de talleres.

## Resumen ejecutivo

El proyecto tiene dos caminos relacionados con IA:

1. `POST /api/v1/emergencia/reportar`
   - Endpoint historico de analisis IA.
   - Procesa audio e imagen y devuelve una respuesta JSON.
   - No crea incidente ni guarda evidencias.

2. `POST /api/v1/incidentes/reportar`
   - Endpoint principal usado por el movil para reportar incidentes reales.
   - Crea el incidente en base de datos.
   - Guarda audio e imagen como evidencias.
   - Transcribe audio y analiza imagen si la IA esta disponible.
   - Clasifica el incidente en una categoria oficial.
   - Calcula prioridad/criticidad.
   - Genera resumen IA para que el taller decida si acepta.
   - Genera la cola inicial de talleres candidatos.

## IA usada

Servicio:

```text
backend/app/services/ai_service.py
```

Clase:

```text
AIService
```

Proveedor:

```text
Hugging Face
```

Variables relevantes:

```text
HF_API_TOKEN
HF_INFERENCE_BASE_URL=https://router.huggingface.co/hf-inference/models
HF_AUDIO_MODEL=openai/whisper-large-v3
HF_VISION_MODEL=facebook/detr-resnet-50
```

Modelos por defecto actuales:

```text
audio: openai/whisper-large-v3
imagen: facebook/detr-resnet-50
```

Uso:

- Whisper transcribe el audio grabado desde el movil.
- DETR detecta objetos en la imagen enviada como evidencia.
- El backend no depende 100% de la IA externa: si falla audio o imagen, el incidente igual puede crearse y queda una nota en `resumen_ia`.

## Flujo principal desde movil

Archivo movil:

```text
movil/lib/screens/incidentes/reportar_incidente_screen.dart
movil/lib/services/incidente_service.dart
```

Secuencia:

```text
Cliente logueado
  |
  | selecciona vehiculo
  | graba audio opcional
  | adjunta imagen opcional
  | selecciona ubicacion en mapa / GPS
  v
POST /api/v1/incidentes/reportar
  |
  | vehiculo_id
  | descripcion opcional
  | ubicacion
  | latitud / longitud
  | audio opcional
  | imagen opcional
  v
Backend crea incidente pendiente
  |
  | guarda evidencias en /uploads/incidentes
  | procesa IA si hay audio/imagen
  | clasifica categoria oficial
  | calcula prioridad
  | genera resumen IA
  v
Backend genera ranking de talleres candidatos
  |
  | categoria -> especialidades
  | distancia
  | disponibilidad
  | tecnicos activos
  v
Se ofrece el incidente al primer taller candidato
```

## Datos guardados en incidente

Modelo:

```text
backend/app/models/incidente.py
```

Campos relevantes:

```text
descripcion
ubicacion
latitud
longitud
prioridad
estado
fecha_creacion
transcripcion_audio
clasificacion_ia
resumen_ia
```

La fecha se guarda en backend mediante:

```text
fecha_creacion = server_default=now()
```

Por eso el movil no debe enviar manualmente la fecha del incidente.

## Evidencias

Modelo:

```text
backend/app/models/evidencia.py
```

Endpoint para consultar:

```text
GET /api/v1/evidencias/incidente/{incidente_id}
```

El movil ya puede listar evidencias en el detalle de "Mis incidentes":

- imagenes: se muestran como vista previa y pueden abrirse en grande.
- audio: puede reproducirse desde el detalle.

Los archivos se guardan como rutas publicas:

```text
/uploads/incidentes/audio/{archivo}
/uploads/incidentes/imagenes/{archivo}
```

El movil resuelve esas rutas contra `BACKEND_URL`.

## Clasificacion actual

El backend no deja que la IA cree categorias libres para asignacion.

Despues de transcribir audio y leer etiquetas de imagen, aplica una capa de clasificacion controlada por reglas:

```text
texto del usuario
+ transcripcion
+ etiquetas de imagen
-> categoria oficial
```

Archivo:

```text
backend/app/api/v1/endpoints/incidentes.py
```

Categorias actuales principales:

```text
Accidente / Colision
Pinchazo
Dano en Rueda o Rin
Falla Electrica
Revision de Bateria
Alternador
Fuga de refrigerante
Fuga de Aceite
Fuga de Combustible
Sobrecalentamiento
Sistema de Frenos
Falla de Motor
Motor no arranca
Bomba de Gasolina
Transmisiones
Falla de Embrague
Direccion
Ruido en Suspension
Alineacion y Balanceo
Aire Acondicionado
Llave o Inmovilizador
Cerrajeria Vehicular
Escape / Catalizador
Cristales / Parabrisas
Carroceria
Mantenimiento Preventivo
Cambio de Aceite
Filtro de Aire
Correa de Distribucion
Bujias
Otro / No clasificado
```

Ejemplo importante:

Si el audio dice que hubo golpe/derrape, el auto enciende o funciona, pero no puede avanzar, el backend lo trata como patron compatible con `Pinchazo` o dano de rueda, aunque el usuario no diga literalmente "llanta pinchada".

## Resumen IA actual

El resumen intenta ser util para el taller, no solo repetir la transcripcion.

Incluye:

- resumen de situacion,
- categoria sugerida,
- nivel de confianza,
- criticidad,
- senales usadas para clasificar,
- motivos detectados,
- nota visual si la imagen solo confirma presencia de vehiculo,
- categorias alternativas,
- accion sugerida.

Ejemplo:

```text
Resumen: El vehiculo no puede continuar por posible pinchazo o dano de rueda.
Categoria sugerida: Pinchazo (confianza media).
Criticidad: Media (vehiculo inmovilizado sin senales de lesion).
Senales usadas para clasificar: patron compatible con vehiculo que enciende pero no avanza.
Imagen: vehiculo detectado.
Nota visual: la imagen confirma presencia de vehiculo, pero no confirma el tipo de falla.
Accion sugerida: Enviar apoyo para cambio o reparacion de llanta.
```

## Asignacion inteligente iniciada

La primera base de ranking ya queda conectada al reporte de incidentes.

Modelos nuevos:

```text
backend/app/models/asignacion_inteligente.py
```

Tablas:

```text
categoria_incidente
categoria_especialidad
incidente_asignacion_candidato
```

Servicio:

```text
backend/app/services/ranking_taller_service.py
```

Responsabilidades actuales:

1. Crear/asegurar catalogo base de categorias.
2. Relacionar categorias con especialidades existentes.
3. Buscar talleres activos con tecnicos activos.
4. Calcular distancia desde el incidente.
5. Calcular compatibilidad por especialidad.
6. Calcular disponibilidad por horario.
7. Guardar candidatos ordenados.
8. Ofrecer el incidente al primer candidato.

Formula inicial:

```text
score_total =
  score_disponibilidad * 0.45
  + score_especialidad * 0.35
  + score_distancia * 0.20
```

Antes de calcular el score, se excluyen talleres fuera de horario laboral y talleres sin tecnicos activos.

Endpoints agregados:

```text
POST /api/v1/incidentes/{id}/generar-ranking
GET  /api/v1/incidentes/{id}/candidatos
POST /api/v1/incidentes/{id}/ofrecer-siguiente
POST /api/v1/incidentes/procesar-timeouts
```

El endpoint:

```text
GET /api/v1/incidentes/pendientes
```

ahora prioriza mostrar al taller solo incidentes que esten `ofrecidos` para ese taller. Si un incidente no tiene ranking, mantiene el comportamiento anterior como fallback.

## Aceptar y rechazar

El flujo actual queda compatible con la cola:

### Aceptar

```text
PATCH /api/v1/incidentes/{id}/aceptar
```

Si el incidente tiene candidatos, solo puede aceptar el taller que tenga el candidato en estado:

```text
ofrecido
```

Al aceptar:

```text
incidente.estado = asignado_taller
incidente.taller_id = taller_id
incidente.tiempo_asignacion_segundos = segundos desde oferta hasta aceptacion
candidato.estado = aceptado
otros candidatos pendientes/ofrecidos = saltado
```

### Rechazar

```text
PATCH /api/v1/incidentes/{id}/rechazar
```

Al rechazar:

```text
candidato.estado = rechazado
incidente.estado = pendiente
incidente.taller_id = null
```

Luego el sistema intenta ofrecer el incidente al siguiente candidato pendiente.

## Pendiente para completar la HU

Todavia falta cerrar:

1. UI web para que el taller vea que un incidente fue ofrecido por ranking.
2. Pantalla/admin de catalogo `categoria_incidente`.
3. Pantalla/admin para mantener `categoria_especialidad`.
4. Metricas historicas para `score_historial` y `score_carga`.
5. Notificaciones push FCM reales si Firebase Admin no esta configurado.
6. Mostrar ranking/candidatos de forma amigable en frontend administrativo.

## Timeout automatico

El backend tiene un worker ligero en `app.main` que revisa ofertas vencidas.

Configuracion:

```text
ASSIGNMENT_TIMEOUT_WORKER_ENABLED=true
ASSIGNMENT_TIMEOUT_CHECK_SECONDS=30
```

Comportamiento:

```text
candidato.ofrecido con expira_en vencido
  -> candidato.expirado
  -> notifica al cliente taller_no_responde
  -> ofrece al siguiente candidato pendiente
```

Tambien se puede forzar manualmente:

```text
POST /api/v1/incidentes/procesar-timeouts
```

## Diferencia con el endpoint historico

`/api/v1/emergencia/reportar` sigue siendo util para probar IA de forma aislada.

Pero el flujo real del producto para movil es:

```text
/api/v1/incidentes/reportar
```

Ese es el endpoint que debe usarse para crear incidentes reales con evidencia, IA y ranking.
