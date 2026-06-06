# Plan - Reestructuracion del flujo de estados de incidente

## Objetivo

Reestructurar el ciclo de vida del incidente para separar con claridad:

- busqueda y asignacion de taller,
- aceptacion del taller,
- asignacion y desplazamiento del tecnico,
- atencion en sitio,
- cierre operativo y pago,
- cancelaciones por taller o cliente.

El cambio modifica backend, frontend web y app movil, por lo que debe ejecutarse por fases y con compatibilidad temporal.

## Decisiones confirmadas

1. `pendiente` queda como estado inicial solamente.
2. Al iniciar la busqueda/asignacion automatica de taller, el incidente pasa a `buscando_taller`.
3. Al aceptar el taller, el incidente pasa a `asignado_taller`.
4. Se debe guardar `tiempo_asignacion_segundos` en `incidente`.
5. El tiempo de asignacion se mide en segundos desde que se ofrece el incidente al taller que finalmente acepta hasta que ese taller acepta.
6. Al asignar tecnico, el incidente pasa a `en_camino`.
7. Cuando el tecnico llegue al punto del incidente, el mapa/seguimiento lo marcara automaticamente como `en_atencion`.
8. No se usara estado `cobro_pendiente` en incidente; el pago mantiene su propio `pago_estado`.
9. El incidente pasa de `en_atencion` a `finalizado` cuando se complete el cierre del servicio/pago segun el flujo de pagos.
10. Las cancelaciones usan un solo estado `cancelado`, con campos `cancelado_por` y `motivo_cancelacion`.

## Estados nuevos del incidente

```text
pendiente
buscando_taller
asignado_taller
en_camino
en_atencion
finalizado
cancelado
```

## Flujo propuesto

```text
pendiente
  -> buscando_taller
  -> asignado_taller
  -> en_camino
  -> en_atencion
  -> finalizado
```

Cancelaciones:

```text
pendiente        -> cancelado  // cliente
buscando_taller  -> cancelado  // cliente
asignado_taller  -> cancelado  // taller o cliente
en_camino        -> cancelado  // taller o cliente antes de llegada
```

No deberia permitirse cancelacion normal una vez que el incidente este en `en_atencion`, salvo una regla especial de anulacion administrativa.

## Campos nuevos o ajustados

### `incidente.tiempo_asignacion_segundos`

Tipo sugerido:

```text
Integer nullable
```

Uso:

- Se llena cuando el taller acepta.
- Se calcula usando el candidato aceptado:

```text
tiempo_asignacion_segundos =
  fecha_aceptacion_taller - fecha_oferta_candidato
```

Donde:

- `fecha_oferta_candidato` puede salir de `IncidenteAsignacionCandidato.fecha_oferta`.
- `fecha_aceptacion_taller` puede ser `now()` al ejecutar `PATCH /incidentes/{id}/aceptar`.

Luego el promedio se calcula con:

```text
AVG(incidente.tiempo_asignacion_segundos)
```

### `incidente.cancelado_por`

Tipo sugerido:

```text
String(20) nullable
```

Valores sugeridos:

```text
cliente
taller
sistema
admin
```

### `incidente.motivo_cancelacion`

Ya existe. Debe mantenerse y usarse en todos los flujos de cancelacion.

### Timestamps recomendados

No son estrictamente obligatorios para esta primera etapa, pero ayudarian a auditoria y metricas:

```text
fecha_inicio_busqueda
fecha_asignacion_taller
fecha_asignacion_tecnico
fecha_llegada_tecnico
fecha_finalizacion
fecha_cancelacion
```

Si se quiere mantener el cambio pequeno, empezar solo con `tiempo_asignacion_segundos` y `cancelado_por`.

## Cambios backend

### Modelo y migracion

Archivos afectados:

```text
backend/app/models/incidente.py
backend/app/schemas/incidente.py
backend/alembic/versions/*.py
```

Cambios:

1. Agregar `tiempo_asignacion_segundos`.
2. Agregar `cancelado_por`.
3. Exponer ambos campos en schemas `IncidenteBase`, `IncidenteUpdate` y salida `Incidente`.
4. Crear migracion Alembic.
5. Definir constantes de estados para evitar strings repetidos.

### Creacion de incidente

Archivo afectado:

```text
backend/app/api/v1/endpoints/incidentes.py
```

Cambio:

1. Crear el incidente en `pendiente`.
2. Cuando se llame a `RankingTallerService.generar_y_ofrecer(...)`, cambiar el incidente a `buscando_taller` si hay ranking o si inicia busqueda.
3. Si no hay talleres candidatos, definir regla:
   - mantener `buscando_taller` con notificacion de "sin talleres", o
   - volver a `pendiente` para revision manual.

Recomendacion:

```text
Sin candidatos automaticos -> pendiente
Con candidatos/oferta activa -> buscando_taller
```

### Ranking y asignacion de taller

Archivos afectados:

```text
backend/app/services/ranking_taller_service.py
backend/app/models/asignacion_inteligente.py
```

Cambios:

1. Al generar candidatos y ofrecer el primero, actualizar incidente a `buscando_taller`.
2. Seguir excluyendo talleres cerrados y sin tecnicos activos.
3. Mantener la cola de candidatos con estados propios:

```text
pendiente
ofrecido
aceptado
rechazado
expirado
saltado
```

4. Cuando el taller acepta:
   - candidato pasa a `aceptado`,
   - incidente pasa a `asignado_taller`,
   - `incidente.taller_id` se llena,
   - `incidente.tiempo_asignacion_segundos` se calcula.
5. Si el taller rechaza:
   - candidato pasa a `rechazado`,
   - incidente sigue en `buscando_taller` si hay siguiente candidato,
   - si no hay candidatos, vuelve a `pendiente` o queda `buscando_taller` con alerta, segun regla final.
6. Si una oferta expira:
   - candidato pasa a `expirado`,
   - incidente sigue `buscando_taller` mientras haya candidatos.

### Aceptar incidente

Archivo afectado:

```text
backend/app/api/v1/endpoints/incidentes.py
backend/app/crud/crud_incidente.py
```

Cambio actual:

```text
aceptar -> en_proceso
```

Nuevo cambio:

```text
aceptar -> asignado_taller
```

Ademas:

1. Calcular `tiempo_asignacion_segundos`.
2. No disparar todavia "auxilio en camino"; eso debe ocurrir al asignar tecnico.
3. Notificar al cliente con evento/tipo de taller asignado.

### Asignar tecnico

Archivo afectado:

```text
backend/app/api/v1/endpoints/incidentes.py
backend/app/crud/crud_incidente.py
```

Cambio actual:

```text
asignar tecnico -> solo tecnico_id
```

Nuevo cambio:

```text
asignar tecnico -> tecnico_id + estado en_camino
```

Reglas:

1. Solo se puede asignar tecnico si el incidente esta en `asignado_taller`.
2. El tecnico debe pertenecer al taller asignado.
3. Al asignar tecnico, notificar al cliente y tecnico: `auxilio_en_camino`.

### Llegada automatica por mapa

Archivos/modulos a crear o ajustar:

```text
backend/app/api/v1/endpoints/incidentes.py
backend/app/api/v1/endpoints/seguimiento.py  // opcional nuevo
backend/app/websocket/manager.py
movil/lib/services/realtime_service.dart
```

Regla:

1. El tecnico envia ubicacion periodica.
2. Backend calcula distancia tecnico-incidente.
3. Si la distancia baja de un umbral configurable, cambia estado a `en_atencion`.

Umbral sugerido:

```text
50 a 100 metros
```

Debe evitarse marcar llegada por una lectura GPS mala. Recomendacion:

```text
2 o 3 lecturas consecutivas dentro del umbral
```

### Finalizacion y pagos

Archivos afectados:

```text
backend/app/api/v1/endpoints/incidentes.py
backend/app/api/v1/endpoints/pagos.py
backend/app/models/pago.py
```

Regla propuesta:

1. El incidente permanece `en_atencion` mientras el servicio/pago no este cerrado.
2. `pago_estado` conserva el detalle financiero:

```text
pendiente
por_cobrar
pagado
```

3. Cuando el pago se confirma como completado, actualizar:

```text
incidente.pago_estado = pagado
incidente.estado = finalizado
```

4. Si se cancela o edita el pago, revisar si el incidente debe volver a `en_atencion` o mantener `finalizado` solo si el pago sigue completado.

### Cancelaciones

Archivos afectados:

```text
backend/app/api/v1/endpoints/incidentes.py
backend/app/services/notificacion_service.py
frontend/src/app/features/auxilios/*
movil/lib/screens/incidentes/*
```

Crear endpoints claros:

```text
PATCH /api/v1/incidentes/{id}/cancelar-cliente
PATCH /api/v1/incidentes/{id}/cancelar-taller
```

O un endpoint unico:

```text
PATCH /api/v1/incidentes/{id}/cancelar
body: { cancelado_por, motivo_cancelacion }
```

Recomendacion:

Endpoint unico con validacion por rol.

Reglas:

1. Cliente puede cancelar antes de llegada del tecnico:

```text
pendiente
buscando_taller
asignado_taller
en_camino
```

2. Taller puede cancelar cuando tenga asignado/ofrecido el incidente:

```text
asignado_taller
en_camino
```

3. Al cancelar:

```text
estado = cancelado
cancelado_por = cliente | taller
motivo_cancelacion = texto obligatorio
```

4. Si el taller cancela antes de aceptar, eso deberia seguir siendo rechazo de candidato, no cancelacion global del incidente.

### Notificaciones

Archivo afectado:

```text
backend/app/services/notificacion_service.py
```

Eventos a ajustar:

```text
buscando_taller
taller_asignado
auxilio_en_camino
tecnico_llego
servicio_finalizado
servicio_cancelado
```

Eliminar o reubicar usos actuales:

```text
en_proceso
atendido
rechazado
```

`rechazado` debe quedar como estado de candidato/oferta, no como estado final del incidente.

### Historial y metricas

Archivos afectados:

```text
backend/app/crud/crud_incidente.py
backend/app/api/v1/endpoints/incidentes.py
frontend/src/app/features/historial/*
```

Cambios:

1. Reemplazar filtros:

```text
atendido -> finalizado
en_proceso -> asignado_taller/en_camino/en_atencion
rechazado -> cancelado o estado de candidato
```

2. Agregar metrica:

```text
tiempo_promedio_asignacion = AVG(tiempo_asignacion_segundos)
```

3. Definir historico como:

```text
finalizado
cancelado
```

4. Definir activos como:

```text
buscando_taller
asignado_taller
en_camino
en_atencion
```

### Seeder y datos de prueba

Archivo afectado:

```text
backend/app/db/seeder.py
```

Cambios:

1. Actualizar lista de estados.
2. Crear incidentes de prueba en todos los estados nuevos.
3. Poblar `tiempo_asignacion_segundos` para incidentes `asignado_taller`, `en_camino`, `en_atencion` y `finalizado`.
4. Poblar `cancelado_por` y `motivo_cancelacion` para cancelados.

## Cambios frontend web

### Auxilios

Archivos afectados:

```text
frontend/src/app/features/auxilios/auxilios.ts
frontend/src/app/features/auxilios/auxilios.html
frontend/src/app/features/auxilios/auxilios.css
frontend/src/app/core/services/incidentes.ts
```

Cambios:

1. La pestaña "Disponibles" debe representar ofertas `buscando_taller` ofrecidas al taller.
2. Al aceptar, mostrar estado `asignado_taller`.
3. El modal de asignacion de tecnico debe cambiar a `en_camino`.
4. Reemplazar checks `estado !== 'atendido'` por estados activos nuevos.
5. Reemplazar finalizacion manual a `atendido` por flujo nuevo:

```text
en_atencion -> generar/confirmar pago -> finalizado
```

6. Agregar boton de cancelar para taller en estados permitidos.
7. Mostrar `tiempo_asignacion_segundos` en detalle o ranking si aplica.

### Dashboard tecnico web

Archivos afectados:

```text
frontend/src/app/features/tecnico-dashboard/*
```

Cambios:

1. Actualizar arreglo de estados.
2. Actualizar orden visual:

```text
en_camino
en_atencion
finalizado
cancelado
```

3. Actualizar badges CSS.
4. Reemplazar `en_proceso` por `en_camino`.
5. Reemplazar `atendido` por `finalizado`.
6. Integrar evento de llegada por mapa para `en_atencion`.

### Historial web

Archivos afectados:

```text
frontend/src/app/features/historial/*
```

Cambios:

1. Filtros por defecto:

```text
finalizado
cancelado
```

2. Agregar activos opcionales:

```text
buscando_taller
asignado_taller
en_camino
en_atencion
```

3. Agregar visualizacion de `tiempo_asignacion_segundos` y promedio si el backend lo expone.

### Finanzas

Archivos afectados:

```text
frontend/src/app/features/finanzas/*
frontend/src/app/core/services/incidentes.ts
```

Cambios:

1. Mantener `pago_estado`.
2. Al confirmar pago, esperar que backend devuelva incidente en `finalizado`.
3. Revisar textos que dependan de `atendido`.

## Cambios app movil

### Mis incidentes y seguimiento

Archivos afectados:

```text
movil/lib/screens/incidentes/mis_incidentes_screen.dart
movil/lib/screens/servicios/seguimiento_screen.dart
movil/lib/screens/servicios/mis_atenciones_screen.dart
movil/lib/main.dart
```

Cambios:

1. Actualizar estados activos:

```text
pendiente
buscando_taller
asignado_taller
en_camino
en_atencion
```

2. Actualizar estados historicos:

```text
finalizado
cancelado
```

3. Reemplazar textos:

```text
en_proceso -> en_camino
atendido -> finalizado
rechazado -> cancelado o mensaje de taller rechazo, no estado final
```

4. Mostrar timeline:

```text
Solicitud creada
Buscando taller
Taller asignado
Tecnico en camino
Tecnico en atencion
Finalizado
```

5. Permitir cancelacion de cliente antes de `en_atencion`.

### Seguimiento por mapa

Archivos afectados:

```text
movil/lib/services/realtime_service.dart
movil/lib/services/incidente_service.dart
movil/lib/screens/servicios/seguimiento_screen.dart
```

Cambios:

1. Enviar ubicacion del tecnico periodicamente.
2. Recibir ubicacion del tecnico para cliente.
3. Cuando backend detecte llegada, refrescar estado a `en_atencion`.
4. Evitar que cliente pueda cancelar despues de `en_atencion`.

### Pagos movil

Archivos afectados:

```text
movil/lib/screens/pagos/pagos_screen.dart
movil/lib/providers/pago_provider.dart
movil/lib/services/pago_service.dart
```

Cambios:

1. Mantener `pago_estado`.
2. Si pago queda `pagado`, mostrar incidente como `finalizado`.
3. Revisar listas que hoy dependen de `atendido`.

## Compatibilidad y migracion de datos

Estados antiguos a mapear:

```text
pendiente   -> pendiente o buscando_taller segun tenga candidatos/ofertas activas
en_proceso  -> en_camino si tiene tecnico_id, asignado_taller si no tiene tecnico_id
atendido    -> finalizado si pago_estado = pagado, en_atencion si no esta pagado
rechazado   -> cancelado si era estado del incidente; candidato rechazado queda en tabla de candidatos
cancelado   -> cancelado
```

Regla sugerida para datos existentes:

1. Si `estado = pendiente` y no tiene taller, dejar `pendiente`.
2. Si tiene candidatos `ofrecido`, usar `buscando_taller`.
3. Si `estado = en_proceso` y tiene `taller_id` pero no `tecnico_id`, usar `asignado_taller`.
4. Si `estado = en_proceso` y tiene `tecnico_id`, usar `en_camino`.
5. Si `estado = atendido` y `pago_estado = pagado`, usar `finalizado`.
6. Si `estado = atendido` y `pago_estado != pagado`, usar `en_atencion`.
7. Si `estado = rechazado`, usar `cancelado` con `cancelado_por = taller` si hay taller, si no `sistema`.

## Fases de implementacion

### Fase 1 - Contrato y migracion

1. Definir constantes de estados.
2. Crear migracion para `tiempo_asignacion_segundos` y `cancelado_por`.
3. Actualizar modelo y schemas.
4. Actualizar seeder.
5. Agregar pruebas unitarias de transicion basica.

### Fase 2 - Backend de asignacion

1. `pendiente` solo al crear.
2. `buscando_taller` al generar/ofrecer ranking.
3. `asignado_taller` al aceptar.
4. Calcular `tiempo_asignacion_segundos`.
5. Rechazo de candidato no debe convertirse en estado `rechazado` del incidente.
6. Mantener exclusion de talleres cerrados.

### Fase 3 - Tecnico y mapa

1. Asignar tecnico cambia a `en_camino`.
2. Crear endpoint/evento de tracking.
3. Llegada automatica cambia a `en_atencion`.
4. Notificaciones nuevas.

### Fase 4 - Pagos y cierre

1. Mantener `pago_estado`.
2. Confirmar pago cambia incidente a `finalizado`.
3. Ajustar cancelacion/edicion de pagos.
4. Actualizar metricas e historial.

### Fase 5 - Frontend web

1. Auxilios.
2. Dashboard tecnico.
3. Historial.
4. Finanzas.
5. Badges y filtros de estado.

### Fase 6 - Movil

1. Timeline del cliente.
2. Seguimiento por mapa.
3. Cancelacion de cliente.
4. Mis atenciones / historial.
5. Pagos.

### Fase 7 - QA integral

Casos minimos:

1. Crear incidente -> `pendiente`.
2. Generar ranking -> `buscando_taller`.
3. Taller acepta -> `asignado_taller` y `tiempo_asignacion_segundos > 0`.
4. Admin asigna tecnico -> `en_camino`.
5. Tracking detecta llegada -> `en_atencion`.
6. Pago confirmado -> `finalizado`.
7. Cliente cancela antes de llegada -> `cancelado`, `cancelado_por = cliente`.
8. Taller cancela despues de aceptar -> `cancelado`, `cancelado_por = taller`.
9. Taller rechaza oferta -> no cancela incidente si quedan candidatos.
10. Taller cerrado no entra en candidatos.

## Riesgos

1. `estado` y `pago_estado` pueden quedar inconsistentes si pagos no actualiza incidente.
2. Frontend y movil pueden ocultar incidentes si siguen filtrando por `en_proceso` o `atendido`.
3. Notificaciones antiguas pueden mostrar mensajes incorrectos.
4. Migracion de datos historicos puede mezclar `rechazado` de incidente con rechazo de candidato.
5. Llegada por GPS puede dispararse por lecturas imprecisas.

## Recomendacion de implementacion

Primero cambiar backend y contratos, luego UI web, y finalmente movil/mapa. El mapa puede quedar para una fase posterior si se necesita cerrar primero la maquina de estados.

Orden recomendado:

```text
modelo + migracion
-> estados backend
-> asignacion/ranking
-> pagos/finalizacion
-> frontend web
-> movil
-> seguimiento automatico por mapa
```
