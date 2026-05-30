# Flujo actual de IA en backend y movil

## Objetivo del documento

Este documento describe como funciona hoy la IA en el proyecto antes de implementar la asignacion inteligente de talleres.

La idea es separar claramente:

- Lo que ya esta implementado en backend.
- Lo que ya existe como servicio en movil.
- Lo que esta maquetado.
- Lo que todavia no esta conectado al flujo real de incidentes.

## Resumen ejecutivo

Actualmente el backend tiene una integracion real con IA usando Hugging Face.

Modelos usados:

```text
openai/whisper-tiny
facebook/detr-resnet-50
```

Uso actual:

- `openai/whisper-tiny`: transcribe audio.
- `facebook/detr-resnet-50`: detecta objetos en imagenes.

El endpoint principal es:

```text
POST /api/v1/emergencia/reportar
```

Este endpoint recibe:

```text
audio
imagen
```

Y devuelve:

```text
transcription
detections
detection_summary
priority
processing_status
```

Importante:

El flujo IA actual analiza audio e imagen, pero no crea un incidente en base de datos y no asigna talleres.

## Flujo actual en backend

### Archivos principales

```text
backend/app/services/ai_service.py
backend/app/api/v1/endpoints/emergencia.py
backend/app/models/incidente.py
backend/app/schemas/incidente.py
```

### Servicio IA

El servicio esta en:

```text
backend/app/services/ai_service.py
```

Clase principal:

```text
AIService
```

Responsabilidades actuales:

1. Leer el token `HF_API_TOKEN`.
2. Construir URLs hacia Hugging Face Inference API.
3. Enviar audio al modelo Whisper.
4. Enviar imagen al modelo DETR.
5. Combinar resultados.
6. Calcular prioridad simple.

### Configuracion requerida

El backend necesita esta variable:

```text
HF_API_TOKEN
```

Si no existe, `AIService` lanza error al inicializar.

Punto importante:

En `backend/app/api/v1/endpoints/emergencia.py` la instancia se inicializa de forma diferida:

```python
ai_service = None
_get_ai_service()
```

Esto permite que el backend arranque aunque `HF_API_TOKEN` no este configurado. Si se llama al endpoint de IA sin token, el error queda limitado a esa peticion.

### Endpoint IA

Archivo:

```text
backend/app/api/v1/endpoints/emergencia.py
```

Endpoint:

```text
POST /api/v1/emergencia/reportar
```

Campos esperados en multipart:

```text
audio
imagen
```

Formatos de audio aceptados por backend:

```text
audio/mpeg
audio/wav
audio/ogg
audio/flac
audio/mp4
```

Formatos de imagen aceptados:

```text
image/jpeg
image/png
image/webp
```

Limites:

```text
audio: 25 MB
imagen: 10 MB
```

### Secuencia backend

```text
Cliente movil o frontend
    |
    | POST /api/v1/emergencia/reportar
    | multipart: audio + imagen
    v
Endpoint emergencia.py
    |
    | valida tipo y tamano de archivos
    | lee audio e imagen como bytes
    v
AIService.process_emergency_report()
    |
    |-- transcribe_audio()
    |       |
    |       v
    |   Hugging Face: openai/whisper-tiny
    |
    |-- detect_objects_in_image()
    |       |
    |       v
    |   Hugging Face: facebook/detr-resnet-50
    |
    | calcula priority
    v
Respuesta JSON al cliente
```

### Respuesta del backend IA

Respuesta esperada:

```json
{
  "status": "success",
  "data": {
    "transcription": "texto transcrito del audio",
    "detections": [
      {
        "label": "car",
        "score": 0.95,
        "box": {
          "xmin": 100,
          "ymin": 50,
          "xmax": 400,
          "ymax": 350
        }
      }
    ],
    "detection_summary": ["car"],
    "priority": "Alta",
    "processing_status": "success"
  },
  "message": "Emergency report processed successfully..."
}
```

### Calculo actual de prioridad

La prioridad se calcula en `AIService.process_emergency_report()`.

Regla actual:

```text
Si detecta labels como car, vehicle, person, accident o fire:
  priority = Alta

Si hay mas de 2 objetos detectados:
  priority = Alta

Si hay al menos 1 objeto detectado:
  priority = Media

Si no hay objetos detectados:
  priority = Baja
```

Limitacion:

La prioridad depende de los objetos detectados en la imagen. La transcripcion del audio no se usa todavia para calcular la prioridad ni para clasificar el tipo de incidente.

### Manejo de errores

El servicio intenta procesar audio e imagen por separado.

Casos:

```text
Audio OK + Imagen OK
  processing_status = success

Audio OK + Imagen falla
  processing_status = partial

Audio falla + Imagen OK
  processing_status = partial

Audio falla + Imagen falla
  error 503
```

Errores posibles del endpoint:

```text
400: formato invalido o archivo vacio
413: archivo demasiado grande
503: error con Hugging Face o ambos procesamientos fallaron
500: error inesperado
```

## Relacion actual con incidentes

El modelo `Incidente` ya tiene campos preparados para guardar resultado IA:

```text
transcripcion_audio
clasificacion_ia
resumen_ia
```

Estan en:

```text
backend/app/models/incidente.py
backend/app/schemas/incidente.py
```

Pero hoy el endpoint:

```text
POST /api/v1/emergencia/reportar
```

no crea registros en la tabla `incidente`.

El flujo normal de creacion de incidentes es otro:

```text
POST /api/v1/incidentes/
```

Ese endpoint recibe un `IncidenteCreate` y lo guarda mediante:

```text
incidente_crud.create()
```

Por tanto, hoy existen dos caminos separados:

```text
Camino A: /emergencia/reportar
  analiza audio/imagen con IA
  devuelve JSON
  no crea incidente

Camino B: /incidentes/
  crea incidente
  puede recibir campos IA si ya vienen preparados
  no llama a Hugging Face
```

## Flujo actual en movil

### Archivos principales

```text
movil/lib/services/emergencia_service.dart
movil/lib/models/emergencia_models.dart
movil/lib/screens/ia/diagnostico_ia_screen.dart
movil/lib/screens/servicios/mis_atenciones_screen.dart
movil/lib/screens/servicios/seguimiento_screen.dart
movil/lib/screens/incidentes/reportar_incidente_screen.dart
movil/lib/services/incidente_service.dart
movil/lib/screens/emergencia_example.dart
movil/lib/screens/emergencia_integration_guide.dart
```

## Servicio movil real para IA

El servicio real esta en:

```text
movil/lib/services/emergencia_service.dart
```

Clase:

```text
EmergenciaService
```

Metodo principal:

```text
enviarReporte()
```

Responsabilidades:

1. Recibir `audioPath` e `imagePath`.
2. Validar que ambos archivos existan.
3. Validar tamano:
   - audio maximo 25 MB,
   - imagen maxima 10 MB.
4. Detectar MIME type por extension.
5. Armar un `MultipartRequest`.
6. Enviar los archivos a:

```text
/api/v1/emergencia/reportar
```

7. Enviar token JWT si existe.
8. Parsear la respuesta a `EmergenciaReporte`.
9. Devolver `Result<EmergenciaReporte>`:

```text
Success(reporte)
Failure(error)
```

### Modelos movil para respuesta IA

Archivo:

```text
movil/lib/models/emergencia_models.dart
```

Modelos principales:

```text
EmergenciaReporte
Detection
Result<T>
Success<T>
Failure<T>
EmergenciaException
FileSizeException
FileTypeException
NoInternetException
TimeoutException
HttpException
```

`EmergenciaReporte` contiene:

```text
status
transcription
detections
detectionSummary
priority
processingStatus
message
```

### Secuencia movil del servicio IA

```text
Pantalla o provider
    |
    | EmergenciaService.enviarReporte(audioPath, imagePath)
    v
Validacion local de archivos
    |
    | crea MultipartRequest
    v
POST {BackendConfig.baseUrl}/api/v1/emergencia/reportar
    |
    | audio + imagen + Authorization opcional
    v
Backend IA
    |
    | respuesta JSON
    v
EmergenciaReporte.fromJson()
    |
    v
Success(reporte) o Failure(error)
```

## Pantallas moviles actuales

### Reportar incidente

Archivo:

```text
movil/lib/screens/incidentes/reportar_incidente_screen.dart
```

Esta es la pantalla usada para crear incidentes desde movil.

Flujo actual:

```text
Usuario selecciona vehiculo
Usuario escribe descripcion
Usuario escribe ubicacion
App obtiene coordenadas GPS reales del celular
App llama IncidenteProvider.reportarIncidente()
IncidenteService llama POST /api/v1/incidentes/
```

Este flujo no llama a:

```text
EmergenciaService.enviarReporte()
```

Por tanto, el reporte normal desde movil no usa la IA actual.

Observacion:

El movil envia campos como:

```text
descripcion
ubicacion
latitud
longitud
```

El backend ya cuenta con campos para persistir `descripcion`, `ubicacion`, `latitud` y `longitud` en el incidente. Para IA futura, esos datos deben alimentar la clasificacion y el ranking.

### Diagnostico IA visible en movil

Archivo:

```text
movil/lib/screens/ia/diagnostico_ia_screen.dart
```

Esta pantalla actualmente esta maquetada.

Comportamiento:

1. Muestra el texto:

```text
Analizando reporte con IA
Modulo solo maquetado por ahora
```

2. Avanza una barra de progreso con un `Timer`.
3. Cuando llega a 100%, cierra la pantalla.
4. Ejecuta `onCompleted()`.

No llama al backend.
No llama a `EmergenciaService`.
No usa audio, imagen, transcripcion ni detecciones reales.

### Mis atenciones

Archivo:

```text
movil/lib/screens/servicios/mis_atenciones_screen.dart
```

Muestra incidentes del cliente cargados desde:

```text
GET /api/v1/incidentes/mis-incidentes
```

En cada incidente activo aparece un boton:

```text
Diagnostico IA
```

Ese boton navega a:

```text
DiagnosticoIAScreen
```

Pero como esa pantalla esta maquetada, no consume el diagnostico real del backend.

### Seguimiento

Archivo:

```text
movil/lib/screens/servicios/seguimiento_screen.dart
```

Tambien muestra datos IA maquetados:

```text
Tipo de problema estimado: Falla mecanica
Prioridad estimada: ALTA
Estado IA: Maquetado
```

No lee `clasificacion_ia`, `resumen_ia` ni `transcripcion_audio` desde el incidente.

## Archivos de ejemplo e integracion

Existen archivos que muestran como integrar el servicio IA:

```text
movil/lib/screens/emergencia_example.dart
movil/lib/screens/emergencia_integration_guide.dart
```

Estos archivos si usan o demuestran:

```text
EmergenciaService.enviarReporte()
```

Pero son ejemplos/guias dentro del codigo movil. No parecen estar conectados como flujo principal de la app.

## Estado real de integracion

### Backend

```text
IA real: si
Endpoint IA: si
Hugging Face: si
Crea incidente: no
Asigna taller: no
Clasifica categoria oficial: no
Guarda cola de talleres: no
```

### Movil

```text
Servicio para llamar IA: si
Modelos para parsear respuesta IA: si
Pantalla principal reporta usando IA: no
Diagnostico IA visible: maquetado
Seguimiento IA visible: maquetado
Carga resultados IA desde incidente: no
```

## Incompatibilidades y detalles a revisar

### 1. Timeout movil vs backend

Movil usa timeout por defecto:

```text
15 segundos
```

Backend usa timeout hacia Hugging Face:

```text
30 segundos por llamada
```

Como el backend llama audio e imagen, una respuesta real podria tardar mas que el timeout movil.

Recomendacion:

Subir el timeout del movil para el endpoint IA o manejarlo como proceso asincrono.

### 2. MIME audio/mp4

Movil permite:

```text
audio/mp4
```

Backend tambien lo acepta actualmente.

Backend acepta:

```text
audio/mpeg
audio/wav
audio/ogg
audio/flac
audio/mp4
```

Observacion:

Este formato es importante porque Android puede generar `.m4a` con MIME `audio/mp4`.

### 3. Endpoint IA sin creacion de incidente

El endpoint IA devuelve analisis, pero no persiste nada.

Para integrarlo con el flujo real habria que elegir una estrategia:

```text
Opcion A:
  primero llamar /emergencia/reportar
  luego crear /incidentes/ con los campos IA resultantes

Opcion B:
  crear un endpoint unico que reciba datos del incidente + audio + imagen
  procese IA
  guarde incidente
  guarde evidencias
  dispare ranking de talleres
```

Para la asignacion inteligente, la opcion B es mas limpia.

### 4. Prioridad basada solo en imagen

La prioridad actual no usa la transcripcion.

Ejemplo:

Si el audio dice:

```text
Mi llanta se revento y estoy varado
```

pero la imagen no detecta objetos relevantes, la prioridad podria quedar baja.

Recomendacion:

Usar la transcripcion para clasificar categoria y apoyar prioridad.

### 5. No existe categoria oficial

La IA actual no devuelve una categoria controlada del sistema.

Devuelve:

```text
transcription
detection_summary
priority
```

Para la futura asignacion inteligente hace falta una capa posterior:

```text
resultado IA
-> clasificador de categoria oficial
-> categoria_incidente
-> categoria_especialidad
-> ranking de talleres
```

## Flujo recomendado para integracion futura

Para conectar la IA actual con la futura asignacion inteligente:

```text
Movil reporta incidente con datos + audio + imagen
    |
    v
Backend recibe un unico reporte
    |
    | crea incidente pendiente
    | procesa audio/imagen con IA
    | guarda transcripcion_audio
    | clasifica categoria oficial
    | guarda clasificacion_ia
    | guarda resumen_ia
    v
Backend calcula talleres candidatos
    |
    | categoria -> especialidades
    | talleres activos/cercanos/abiertos
    | score por taller
    v
Backend ofrece al primer taller
    |
    v
Movil recibe estado por WebSocket/FCM
```

## Conclusion

La IA actual existe y funciona como analizador multimodal independiente.

El movil ya tiene un servicio preparado para consumir ese endpoint, pero el flujo principal de reporte de incidentes todavia no lo usa.

Antes de implementar asignacion inteligente, el paso natural es unificar el reporte de incidente con el analisis IA, para que cada incidente real quede guardado con:

```text
transcripcion_audio
clasificacion_ia
resumen_ia
prioridad
```

Despues de eso, el ranking de talleres puede apoyarse en la categoria oficial resultante.
