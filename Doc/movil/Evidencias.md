# Evidencias

## Objetivo

Cerrar el flujo para que el movil pueda reportar un incidente con texto opcional,
audio opcional, imagen opcional y ubicacion real/seleccionada. El backend debe
crear el incidente, guardar los archivos como evidencias y ejecutar IA cuando
existan archivos compatibles.

## Endpoint recomendado

```http
POST /api/v1/incidentes/reportar
Content-Type: multipart/form-data
Authorization: Bearer <token_cliente>
```

No usar directamente `/api/v1/emergencia/reportar` como endpoint final del
movil, porque actualmente solo procesa IA y no crea incidente, no guarda
evidencias, no valida vehiculo del cliente y no se integra con el flujo de
talleres/notificaciones.

## Parametros del request

| Campo | Tipo | Obligatorio | Descripcion |
| --- | --- | --- | --- |
| `vehiculo_id` | int | Si | Vehiculo del cliente autenticado. Debe pertenecer al usuario del token. |
| `descripcion` | string | No | Texto opcional del cliente. Si no hay audio ni imagen, debe existir descripcion. |
| `ubicacion` | string | No | Texto de referencia. Por defecto: `Ubicacion seleccionada en mapa`. |
| `latitud` | float | Si | Latitud GPS o punto seleccionado en mapa. |
| `longitud` | float | Si | Longitud GPS o punto seleccionado en mapa. |
| `audio` | file | No | Audio grabado desde el movil. |
| `imagen` | file | No | Foto tomada o elegida desde galeria. |

Regla minima: debe llegar al menos uno de estos datos descriptivos:

```text
descripcion o audio o imagen
```

## Formatos permitidos

Audio:

```text
audio/mpeg
audio/wav
audio/ogg
audio/flac
audio/mp4
```

Imagen:

```text
image/jpeg
image/png
image/webp
```

Limites recomendados:

```text
audio: 25 MB
imagen: 10 MB
```

## Guardado de archivos

Ruta sugerida:

```text
backend/uploads/incidentes/audio/<uuid>.<extension>
backend/uploads/incidentes/imagenes/<uuid>.<extension>
```

El backend debe montar archivos estaticos para consulta posterior:

```text
/uploads/incidentes/audio/...
/uploads/incidentes/imagenes/...
```

## Registro en Evidencia

Por cada archivo recibido se crea un registro en `evidencia`:

Audio:

```json
{
  "incidente_id": 1,
  "tipo_archivo": "audio",
  "url_archivo": "/uploads/incidentes/audio/<archivo>.m4a"
}
```

Imagen:

```json
{
  "incidente_id": 1,
  "tipo_archivo": "imagen",
  "url_archivo": "/uploads/incidentes/imagenes/<archivo>.jpg"
}
```

## IA esperada

Audio:

```text
AIService.transcribe_audio(audio_data)
```

Resultado esperado:

```text
transcripcion_audio
```

Imagen:

```text
AIService.detect_objects_in_image(imagen_data)
```

Resultado esperado:

```text
detecciones de objetos
resumen de imagen
```

Para el cierre funcional rapido, guardar el resumen de audio + imagen dentro de:

```text
incidente.resumen_ia
incidente.clasificacion_ia
incidente.transcripcion_audio
```

Mejora posterior recomendada:

```text
incidente.detecciones_imagen_ia
```

o una tabla separada:

```text
analisis_ia
```

## Respuesta esperada

El endpoint debe devolver el incidente creado con sus campos principales de IA:

```json
{
  "id": 1,
  "vehiculo_id": 10,
  "usuario_id": 3,
  "descripcion": "",
  "ubicacion": "Ubicacion seleccionada en mapa",
  "latitud": -17.783327,
  "longitud": -63.182140,
  "estado": "pendiente",
  "prioridad": "media",
  "transcripcion_audio": "El auto no arranca...",
  "clasificacion_ia": "Falla Electrica",
  "resumen_ia": "Audio: ... Imagen: se detecto vehiculo/persona..."
}
```

## Cambios requeridos en movil

Pantalla `Reportar Incidente`:

```text
- Mantener descripcion opcional.
- Mantener grabacion de audio.
- Mantener reproduccion local del audio.
- Agregar selector de imagen.
- Permitir camara y galeria.
- Mostrar vista previa de imagen.
- Permitir eliminar imagen antes de enviar.
- Enviar multipart con audio e imagen cuando existan.
- Mostrar respuesta de IA al finalizar.
```

Servicio movil:

```text
IncidenteService.reportarIncidente(...)
```

Debe enviar:

```text
vehiculo_id
descripcion
ubicacion
latitud
longitud
audio
imagen
```

## Criterios de aceptacion

```text
1. El cliente puede reportar incidente solo con audio.
2. El cliente puede reportar incidente solo con imagen.
3. El cliente puede reportar incidente con audio + imagen.
4. El cliente puede reportar incidente solo con descripcion.
5. El backend guarda cada archivo en uploads.
6. El backend registra cada archivo en evidencia.
7. El incidente aparece en Mis Incidentes.
8. Las evidencias se pueden listar por incidente.
9. La IA no bloquea la creacion del incidente si falla.
10. Si la IA falla, el resumen debe indicar el error de forma visible.
```

## Orden de implementacion

```text
1. Backend: endpoint multipart real en incidentes.
2. Backend: guardado de imagen/audio + registro Evidencia.
3. Backend: montar /uploads como archivos estaticos.
4. Backend: integrar IA de audio e imagen sin romper si falla.
5. Movil: selector/vista previa de imagen.
6. Movil: multipart con audio + imagen.
7. Prueba end-to-end con cliente del seeder.
```
