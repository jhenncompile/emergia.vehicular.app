# HU - Asignacion inteligente de talleres por IA

## Objetivo

Permitir que, al crearse un incidente, el backend identifique los talleres mas relevantes para atenderlo, los ordene por prioridad de asignacion y ofrezca el servicio al mejor candidato disponible. Si el taller no responde dentro de un tiempo definido o rechaza el incidente, el sistema debe ofrecerlo automaticamente al siguiente taller de la lista.

Esta funcionalidad combina:

- Analisis del incidente con IA.
- Catalogo controlado de categorias.
- Relacion entre categorias y especialidades.
- Ranking de talleres por relevancia.
- Asignacion progresiva con timeout.
- Notificaciones en tiempo real al cliente y al taller.

## Historia de usuario

Como cliente que reporta una emergencia vehicular, quiero que el sistema encuentre automaticamente los talleres mas adecuados y cercanos para mi incidente, para recibir una atencion rapida sin tener que elegir manualmente un taller.

Como taller, quiero recibir solo incidentes compatibles con mis especialidades y ubicacion, para aceptar servicios que realmente puedo atender.

Como sistema, quiero ordenar los talleres por relevancia y avanzar al siguiente candidato si el primero rechaza o no responde, para reducir el tiempo de espera del cliente.

## Alcance funcional

Cuando se reporte un incidente:

1. El backend crea el incidente en estado `pendiente`.
2. La IA analiza el audio, texto o imagen del reporte.
3. El sistema clasifica el incidente usando una categoria oficial del catalogo.
4. El backend obtiene las especialidades requeridas por esa categoria.
5. El backend busca talleres candidatos:
   - activos,
   - cercanos,
   - abiertos,
   - con tecnicos activos,
   - con especialidades compatibles.
6. El backend calcula un score por taller.
7. El backend guarda una lista ordenada de candidatos.
8. El incidente se ofrece al primer taller de la lista.
9. Si el taller acepta, se asigna el incidente.
10. Si el taller rechaza o no responde en X tiempo, se ofrece al siguiente.
11. El cliente recibe actualizaciones en tiempo real sobre el estado del proceso.

## Regla importante sobre la IA

La IA no debe crear categorias libres directamente en produccion.

La IA debe elegir una categoria dentro de un catalogo oficial, por ejemplo:

```text
Falla de Motor
Sistema de Frenos
Falla Electrica
Revision de Bateria
Pinchazo
Fuga de refrigerante
Aire Acondicionado
Transmisiones
Otro / No clasificado
```

Si la IA no puede clasificar con confianza suficiente, debe devolver:

```text
Otro / No clasificado
```

Opcionalmente puede sugerir una categoria nueva, pero esa categoria no debe usarse para asignacion automatica hasta que un administrador la cree y la relacione con especialidades.

## Estado actual del proyecto

El backend ya tiene una base compatible:

- `AIService` procesa audio e imagen con Hugging Face.
- Se usa `openai/whisper-large-v3` para transcripcion por defecto.
- Se usa `facebook/detr-resnet-50` para deteccion de objetos.
- El modelo `Incidente` ya tiene campos de IA:
  - `transcripcion_audio`
  - `clasificacion_ia`
  - `resumen_ia`
- El modelo `Taller` ya tiene:
  - `latitud`
  - `longitud`
  - `estado`
  - `especialidades_activas`
  - `esta_abierto_ahora`
- Ya existe calculo de distancia Haversine.
- Ya existen endpoints para aceptar y rechazar incidentes.
- Ya existe base de notificaciones por BD, WebSocket y FCM.

Primera base implementada:

- `POST /api/v1/incidentes/reportar` crea el incidente real desde movil.
- El reporte guarda audio/imagen como evidencias.
- El backend clasifica el incidente en una categoria oficial por reglas.
- El backend genera un resumen IA mas explicativo para el taller.
- Se agregaron tablas para categoria, mapeo de especialidades y candidatos.
- Se agrego `RankingTallerService`.
- Al crear el incidente, el backend genera candidatos y ofrece al primer taller.
- Aceptar/rechazar ya actualiza la cola cuando existe ranking.

Pendiente para cerrar completamente la HU:

- tarea automatica de timeout,
- UI web para ofertas de ranking,
- mantenimiento administrativo de categorias/especialidades,
- metricas de historial y carga,
- notificaciones push reales con FCM si Firebase Admin esta configurado.

## Modelo implementado

### Tabla `categoria_incidente`

Catalogo oficial de categorias que la IA puede seleccionar.

Campos:

```text
id
nombre
descripcion
prioridad_default
activa
fecha_creacion
```

Regla:

- Una categoria activa debe tener al menos una especialidad asociada.
- Las categorias sin especialidades pueden existir como borrador, pero no deben usarse en asignacion automatica.

### Tabla `categoria_especialidad`

Relaciona categorias de incidente con especialidades de taller.

Campos:

```text
id
categoria_id
especialidad_id
peso
es_obligatoria
```

Ejemplo:

```text
Categoria: Pinchazo
Especialidad: Llanteria
Peso: 1.0
Obligatoria: si
```

```text
Categoria: Sobrecalentamiento
Especialidad: Refrigeracion
Peso: 0.8

Categoria: Sobrecalentamiento
Especialidad: Mecanica General
Peso: 0.6
```

### Tabla `incidente_asignacion_candidato`

Guarda la cola ordenada de talleres candidatos para un incidente.

Campos:

```text
id
incidente_id
taller_id
orden
score_total
score_distancia
score_especialidad
score_disponibilidad
estado
fecha_creacion
fecha_oferta
fecha_respuesta
expira_en
motivo_rechazo
```

Estados sugeridos:

```text
pendiente
ofrecido
aceptado
rechazado
expirado
saltado
```

## Comparacion entre categoria y especialidades

El sistema no debe comparar textos directamente de esta forma:

```text
"Pinchazo" == "Llanteria"
```

Debe usar la tabla `categoria_especialidad`.

Ejemplo:

```text
Incidente: Sobrecalentamiento
Especialidades requeridas:
- Refrigeracion: 0.8
- Mecanica General: 0.6
```

Taller A:

```text
Especialidades activas:
- Refrigeracion
- Mecanica General

score_especialidad = 1.4 / 1.4 = 100%
```

Taller B:

```text
Especialidades activas:
- Mecanica General

score_especialidad = 0.6 / 1.4 = 43%
```

Taller C:

```text
Especialidades activas:
- Electricidad Automotriz

score_especialidad = 0%
```

## Formula inicial de ranking

Para una primera version, el ranking debe ser deterministico y explicable.

Formula sugerida:

```text
score_total =
  score_distancia * 0.40
  + score_especialidad * 0.30
  + score_disponibilidad * 0.15
  + score_historial * 0.10
  + score_carga * 0.05
```

Donde:

- `score_distancia`: mayor si el taller esta mas cerca.
- `score_especialidad`: mayor si sus tecnicos activos cubren las especialidades requeridas.
- `score_disponibilidad`: mayor si el taller esta abierto y activo.
- `score_historial`: mayor si suele aceptar rapido y completar servicios.
- `score_carga`: mayor si tiene pocos incidentes activos.

Para la primera entrega implementada se usa:

```text
score_total =
  score_distancia * 0.45
  + score_especialidad * 0.40
  + score_disponibilidad * 0.15
```

Luego se puede ampliar con historial y carga.

## Flujo de asignacion

### 1. Cliente reporta incidente

El movil envia ubicacion, vehiculo y evidencias.

El backend crea:

```text
Incidente.estado = pendiente
Incidente.taller_id = null
```

### 2. IA clasifica el incidente

La IA actual puede transcribir audio y detectar objetos.

Despues se agrega una capa de clasificacion que debe devolver:

```json
{
  "categoria": "Pinchazo",
  "confianza": 0.91,
  "resumen": "El cliente reporta una llanta reventada."
}
```

Si no hay confianza suficiente:

```json
{
  "categoria": "Otro / No clasificado",
  "confianza": 0.38,
  "categoria_sugerida": "Ruido metalico frontal"
}
```

### 3. Backend calcula candidatos

El servicio de ranking:

1. Lee la categoria del incidente.
2. Obtiene especialidades requeridas.
3. Busca talleres activos.
4. Calcula distancia.
5. Verifica horario.
6. Verifica tecnicos activos.
7. Calcula score.
8. Guarda la lista ordenada.

### 4. Backend ofrece al primer taller

Se crea o actualiza el primer candidato:

```text
estado = ofrecido
fecha_oferta = ahora
expira_en = ahora + X minutos
```

El taller recibe una notificacion:

```text
Nuevo incidente compatible cerca de tu ubicacion
```

### 5. Taller acepta

Si acepta:

```text
incidente.taller_id = taller_id
incidente.estado = en_proceso
candidato.estado = aceptado
```

El cliente recibe:

```text
taller_acepto
auxilio_en_camino
```

### 6. Taller rechaza

Si rechaza:

```text
candidato.estado = rechazado
incidente.estado = pendiente
incidente.taller_id = null
```

El sistema ofrece el incidente al siguiente candidato.

El cliente puede recibir:

```text
taller_rechazo
buscando_otro_taller
```

### 7. Taller no responde

Una tarea en segundo plano revisa candidatos vencidos.

Si `expira_en < ahora` y sigue `ofrecido`:

```text
candidato.estado = expirado
```

Luego se ofrece el incidente al siguiente candidato.

## Servicios backend recomendados

### `CategoriaIncidenteService`

Responsabilidades:

- Mantener catalogo de categorias.
- Validar que una categoria activa tenga especialidades.
- Buscar categoria por nombre.
- Resolver fallback `Otro / No clasificado`.

### `ClasificadorIncidenteService`

Responsabilidades:

- Recibir transcripcion, resumen y detecciones.
- Seleccionar una categoria oficial.
- Devolver confianza y explicacion.

Primera version posible:

- reglas por palabras clave.

Version futura:

- modelo IA de clasificacion.
- LLM con salida JSON controlada.

### `RankingTallerService`

Responsabilidades:

- Buscar talleres candidatos.
- Calcular distancia.
- Comparar especialidades.
- Calcular score total.
- Generar explicacion del ranking.

### `AsignacionIncidenteService`

Responsabilidades:

- Crear cola de candidatos.
- Ofrecer incidente al siguiente taller.
- Procesar aceptacion.
- Procesar rechazo.
- Procesar expiracion por timeout.

## Endpoints

### Administracion de categorias

```text
GET    /api/v1/categorias-incidente
POST   /api/v1/categorias-incidente
PUT    /api/v1/categorias-incidente/{id}
DELETE /api/v1/categorias-incidente/{id}
```

### Asociar categoria con especialidades

```text
POST   /api/v1/categorias-incidente/{id}/especialidades
PUT    /api/v1/categorias-incidente/{id}/especialidades/{especialidad_id}
DELETE /api/v1/categorias-incidente/{id}/especialidades/{especialidad_id}
```

### Ranking y asignacion

```text
POST  /api/v1/incidentes/{id}/generar-ranking
GET   /api/v1/incidentes/{id}/candidatos
POST  /api/v1/incidentes/{id}/ofrecer-siguiente
PATCH /api/v1/incidentes/{id}/aceptar
PATCH /api/v1/incidentes/{id}/rechazar
```

Los endpoints de ranking ya estan agregados. `aceptar` y `rechazar` ya trabajan contra la cola cuando el incidente tiene candidatos.

## Eventos de tiempo real

Eventos sugeridos:

```text
ranking_generado
incidente_ofrecido_taller
taller_acepto
taller_rechazo
taller_no_responde
buscando_otro_taller
auxilio_en_camino
servicio_atendido
sin_talleres_disponibles
```

El cliente movil debe recibir principalmente:

```text
buscando_taller
taller_acepto
taller_rechazo
buscando_otro_taller
auxilio_en_camino
servicio_atendido
sin_talleres_disponibles
```

El taller/web debe recibir:

```text
incidente_ofrecido_taller
incidente_expirado
incidente_asignado
```

## Criterios de aceptacion

1. Al crear un incidente, el backend debe clasificarlo en una categoria oficial.
2. Si la IA no encuentra una categoria confiable, debe usar `Otro / No clasificado`.
3. Una categoria activa no puede quedar sin especialidades asociadas.
4. El backend debe generar una lista ordenada de talleres candidatos.
5. Cada candidato debe tener un score y una explicacion basica.
6. El incidente debe ofrecerse primero al taller con mayor score.
7. Si el taller acepta, el incidente queda asignado a ese taller.
8. Si el taller rechaza, el sistema ofrece el incidente al siguiente candidato.
9. Si el taller no responde dentro del tiempo configurado, el candidato expira y se ofrece al siguiente.
10. Si no quedan candidatos, el incidente queda como pendiente sin taller y se notifica al cliente.
11. El cliente debe recibir actualizaciones en tiempo real.
12. El taller debe recibir la oferta del incidente en tiempo real.

## Compatibilidad con la IA actual

La propuesta es compatible con la IA actual.

La IA actual se mantiene para:

- transcripcion de audio,
- deteccion de objetos,
- resumen,
- prioridad inicial.

Lo nuevo seria agregar una capa posterior:

```text
resultado IA actual
-> clasificador de categoria oficial
-> especialidades requeridas
-> ranking de talleres
-> asignacion progresiva
```

No es necesario llamar a la IA cada vez que un taller rechaza. La IA se llama al inicio del incidente. La lista de candidatos queda guardada y el sistema avanza al siguiente candidato usando la base de datos.

## Consumo de IA y tokens

Version recomendada para primera entrega:

- La IA se usa solo al crear el incidente.
- El ranking se calcula con reglas en backend.
- El cambio de candidato no llama a la IA.
- No hay consumo adicional por rechazo o timeout.

Si mas adelante se usa un LLM para clasificar categorias, se debe limitar su respuesta a JSON y a categorias oficiales del catalogo.

## Plan de implementacion

### Fase 0 - Preparar datos reales del incidente - Implementada

1. Unificar el flujo de creacion de incidente con el analisis IA.
2. Guardar `descripcion`, `ubicacion`, coordenadas reales y campos IA en cada incidente.
3. Evitar coordenadas de prueba en movil.
4. Alinear formatos de audio aceptados entre movil y backend.
5. Confirmar que el backend pueda arrancar aunque la IA externa no este configurada.

### Fase 1 - Catalogo y mapeo - Implementada base

1. Crear modelo `CategoriaIncidente`.
2. Crear modelo `CategoriaEspecialidad`.
3. Crear migracion.
4. Asegurar categorias base desde `RankingTallerService`.
5. Relacionar categorias base con especialidades actuales.
6. Pendiente: administrar categorias y relaciones desde UI.

### Fase 2 - Clasificacion del incidente - Implementada por reglas

1. Reusar transcripcion y resumen actual.
2. Implementar clasificacion inicial por palabras clave.
3. Detectar patrones como "enciende, pero no puede avanzar despues de golpe/derrape".
4. Guardar `clasificacion_ia` con una categoria oficial.
5. Guardar resumen IA con confianza textual, criticidad y accion sugerida.

### Fase 3 - Ranking de talleres - Implementada base

1. Crear `RankingTallerService`.
2. Obtener talleres activos.
3. Calcular distancia desde el incidente.
4. Calcular compatibilidad por especialidades.
5. Calcular disponibilidad por horario y tecnicos activos.
6. Guardar candidatos ordenados.

### Fase 4 - Asignacion progresiva - Parcial

1. Crear tabla `incidente_asignacion_candidato`.
2. Ofrecer al primer candidato desde `RankingTallerService`.
3. Adaptar aceptar/rechazar para actualizar la cola.
4. Agregar timeout configurable.
5. Pendiente: tarea en segundo plano para expirar ofertas sin accion manual.

### Fase 5 - Notificaciones - Parcial

1. Notificar al taller cuando reciba una oferta.
2. Notificar al cliente cuando se acepte.
3. Notificar al cliente cuando se rechace y se busque otro taller.
4. Notificar si no hay talleres disponibles.
5. Pendiente: validar FCM real en dispositivos.

## Recomendacion final

Implementar primero una version explicable y controlada:

```text
IA actual para analizar
reglas para clasificar
base de datos para mapear categoria -> especialidades
ranking deterministico para ordenar talleres
cola persistente para aceptar, rechazar o expirar
```

Esto evita categorias huerfanas, reduce consumo de IA, permite explicar por que se eligio un taller y mantiene el sistema compatible con la arquitectura actual.
