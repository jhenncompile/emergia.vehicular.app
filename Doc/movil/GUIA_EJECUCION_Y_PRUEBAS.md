# Guia desde cero para ejecutar y probar la app movil

Esta guia esta escrita para alguien que nunca trabajo con Flutter ni Android. El objetivo es llegar a este punto:

```text
Backend corriendo en la laptop + app Flutter abierta en emulador o celular + peticiones llegando al backend.
```

Escenario recomendado para este proyecto:

- Sistema operativo: Windows.
- App movil: Flutter.
- Plataforma de prueba: Android.
- IDE/herramienta Android: Android Studio.
- Backend local: FastAPI en puerto `8000`.

Fuentes oficiales usadas:

- Flutter manual install: https://docs.flutter.dev/install/manual
- Flutter Android setup: https://docs.flutter.dev/platform-integration/android/setup
- Flutter integration tests: https://docs.flutter.dev/testing/integration-tests

## 0. Que es cada cosa

- Flutter: framework para crear apps moviles.
- Dart: lenguaje que usa Flutter.
- Android Studio: herramienta oficial para instalar Android SDK, crear emuladores y depurar.
- Android SDK: herramientas que permiten compilar e instalar apps Android.
- Emulator / AVD: celular virtual que corre dentro de tu PC.
- Dispositivo fisico: tu celular real conectado por USB.
- `flutter doctor`: comando que revisa si tu instalacion esta lista.
- `flutter run`: comando que compila e instala la app en el emulador/celular.

## 1. Orden recomendado

Hazlo en este orden:

1. Instalar Git.
2. Instalar Flutter SDK.
3. Agregar Flutter al `PATH`.
4. Instalar Android Studio.
5. Instalar Android SDK y herramientas desde Android Studio.
6. Instalar plugins Flutter/Dart en Android Studio.
7. Aceptar licencias Android.
8. Crear un emulador Android o conectar un celular.
9. Ejecutar `flutter doctor -v`.
10. Levantar backend.
11. Ejecutar app movil.

## 2. Instalar Git

Git es necesario porque Flutter lo usa internamente.

1. Entra a:

```text
https://git-scm.com/download/win
```

2. Descarga el instalador de Windows.
3. Ejecuta el instalador.
4. Puedes dejar las opciones por defecto.
5. Cierra y vuelve a abrir PowerShell.
6. Verifica:

```powershell
git --version
```

Debe salir algo similar a:

```text
git version 2.x.x.windows.x
```

Si PowerShell dice que `git` no existe, reinicia Windows o revisa que Git se haya agregado al `PATH`.

## 3. Instalar Flutter SDK

Flutter SDK es la carpeta que contiene el comando `flutter`.

### 3.1 Crear carpeta para herramientas

Usa una ruta simple, sin espacios raros y sin permisos de administrador. Recomendado:

```text
C:\Users\TU_USUARIO\develop
```

En PowerShell:

```powershell
mkdir $env:USERPROFILE\develop
```

No lo pongas en:

```text
C:\Program Files
```

### 3.2 Descargar Flutter

1. Entra a:

```text
https://docs.flutter.dev/install/archive?tab=windows
```

2. Descarga la version `stable` para Windows.
3. El archivo sera parecido a:

```text
flutter_windows_x.x.x-stable.zip
```

### 3.3 Extraer Flutter

Si el zip esta en Descargas, puedes extraerlo asi:

```powershell
Expand-Archive -Path $env:USERPROFILE\Downloads\flutter_windows_*.zip -DestinationPath $env:USERPROFILE\develop
```

Al final deberia existir:

```text
C:\Users\TU_USUARIO\develop\flutter
C:\Users\TU_USUARIO\develop\flutter\bin
```

Si prefieres, tambien puedes hacer clic derecho sobre el `.zip` y extraerlo manualmente en `develop`.

## 4. Agregar Flutter al PATH

Esto permite escribir `flutter` desde cualquier terminal.

1. Presiona `Windows`.
2. Busca `Editar las variables de entorno del sistema`.
3. Entra a `Variables de entorno`.
4. En `Variables de usuario`, selecciona `Path`.
5. Clic en `Editar`.
6. Clic en `Nuevo`.
7. Agrega:

```text
%USERPROFILE%\develop\flutter\bin
```

8. Acepta todas las ventanas.
9. Cierra todas las terminales, VS Code y Android Studio si estaban abiertos.
10. Abre PowerShell nuevo.
11. Verifica:

```powershell
flutter --version
dart --version
```

Si ambos comandos responden, Flutter ya esta instalado.

## 5. Instalar Android Studio

Android Studio instala las herramientas Android necesarias para compilar y correr la app.

1. Entra a:

```text
https://developer.android.com/studio
```

2. Descarga Android Studio para Windows.
3. Ejecuta el instalador.
4. Deja marcadas las opciones por defecto.
5. Abre Android Studio.
6. Si aparece el asistente inicial, elige `Standard`.
7. Espera que descargue componentes.

## 6. Instalar Android SDK y herramientas

Dentro de Android Studio:

1. Si estas en la pantalla inicial, ve a `More Actions`.
2. Entra a `SDK Manager`.
3. Si ya hay un proyecto abierto, ve a `Tools > SDK Manager`.

### 6.1 SDK Platforms

1. Entra a la pestana `SDK Platforms`.
2. Marca la API recomendada por Android Studio. En la documentacion actual de Flutter se menciona API Level 36.
3. Si API 36 no aparece, usa la version estable mas nueva disponible.
4. Clic en `Apply`.
5. Acepta e instala.

### 6.2 SDK Tools

Entra a `SDK Tools` y aseguremonos de tener:

- Android SDK Build-Tools.
- Android SDK Command-line Tools.
- Android Emulator.
- Android SDK Platform-Tools.
- CMake.
- NDK (Side by side).

Luego:

1. Clic en `Apply`.
2. Acepta.
3. Espera que termine.
4. Clic en `Finish`.

## 7. Instalar plugins Flutter y Dart en Android Studio

1. Abre Android Studio.
2. Ve a `File > Settings`.
3. Entra a `Plugins`.
4. Busca `Flutter`.
5. Instala el plugin `Flutter`.
6. Android Studio tambien pedira instalar `Dart`; acepta.
7. Reinicia Android Studio cuando lo pida.

## 8. Aceptar licencias Android

Abre PowerShell y ejecuta:

```powershell
flutter doctor --android-licenses
```

Te va a preguntar varias veces. Escribe:

```text
y
```

Luego revisa el estado general:

```powershell
flutter doctor -v
```

Lo ideal es que veas check verde en:

- Flutter.
- Android toolchain.
- Android Studio.
- Connected device, cuando ya tengas emulador o celular.

Notas:

- Si `Chrome` aparece con advertencia, no importa para probar Android.
- Si `Visual Studio` aparece con advertencia, no importa para probar Android.
- Si `Android toolchain` falla, normalmente faltan licencias o SDK tools.

## 9. Crear un emulador Android

Esta es la opcion mas ordenada para empezar si nunca trabajaste con movil.

1. Abre Android Studio.
2. En pantalla inicial: `More Actions > Virtual Device Manager`.
3. Si hay proyecto abierto: `Tools > Device Manager`.
4. Clic en el boton `+` o `Create Virtual Device`.
5. Elige `Phone`.
6. Elige un modelo, por ejemplo `Pixel 7` o `Pixel 8`.
7. Clic en `Next`.
8. Elige una imagen del sistema Android con `Google APIs`.
9. Si tiene icono de descarga, descargala.
10. Clic en `Next`.
11. En graficos, usa una opcion con `Hardware` si esta disponible.
12. Clic en `Finish`.
13. En `Device Manager`, presiona el boton de play para iniciar el emulador.

Verifica desde PowerShell:

```powershell
flutter emulators
flutter devices
```

Debes ver un dispositivo Android.

## 10. Conectar un celular Android fisico

Esto es opcional al inicio. El emulador suele ser mas facil para la primera prueba.

### 10.1 Activar opciones de desarrollador

En tu celular:

1. Abre `Configuracion`.
2. Entra a `Acerca del telefono`.
3. Busca `Numero de compilacion` o `Build number`.
4. Tocalo 7 veces.
5. El celular dira que ya eres desarrollador.

### 10.2 Activar depuracion USB

1. Vuelve a `Configuracion`.
2. Busca `Opciones de desarrollador`.
3. Activa `Depuracion USB`.

### 10.3 Conectar por USB

1. Conecta el celular a la laptop con cable USB de datos.
2. Si el celular pregunta permiso RSA, acepta.
3. Si Windows pide drivers, instala el driver del fabricante del celular.
4. Verifica:

```powershell
flutter devices
```

Debe aparecer el celular.

## 11. Preparar el backend local

La app movil necesita que el backend este corriendo.

Desde la raiz del proyecto:

```powershell
cd backend
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:DEBUG="True"
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Si no existe `venv`, crealo:

```powershell
cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Prueba que el backend responde:

```powershell
curl http://localhost:8000/
curl http://localhost:8000/api/v1/health
```

Swagger:

```text
http://localhost:8000/docs
```

Tambien existe este script:

```powershell
cd backend
.\start-backend-dev.ps1
```

## 12. Instalar dependencias del proyecto movil

Abre otra terminal PowerShell.

Desde la raiz del proyecto:

```powershell
cd movil
flutter pub get
flutter analyze
```

Si algo sale raro:

```powershell
flutter clean
flutter pub get
flutter analyze
```

## 13. Ejecutar en emulador Android

El emulador Android no usa `localhost` para hablar con tu laptop. Usa esta IP especial:

```text
10.0.2.2
```

Con backend corriendo en `localhost:8000`, ejecuta:

```powershell
cd movil
flutter devices
flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

Si tienes varios dispositivos:

```powershell
flutter devices
flutter run -d ID_DEL_DISPOSITIVO --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

Ejemplo:

```powershell
flutter run -d emulator-5554 --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

## 14. Ejecutar en celular fisico por WiFi

Para celular real, la app debe llamar a la IP de tu laptop en la red local.

### 14.1 Sacar la IP de la laptop

En PowerShell:

```powershell
ipconfig
```

Busca el adaptador WiFi y toma la `Direccion IPv4`. Ejemplo:

```text
192.168.1.50
```

### 14.2 Probar desde el navegador del celular

En el celular abre:

```text
http://192.168.1.50:8000/
```

Si no abre:

- Backend no esta corriendo con `--host 0.0.0.0`.
- Celular y laptop no estan en la misma WiFi.
- Firewall de Windows esta bloqueando Python.
- La IP no es la correcta.

### 14.2.5 Vincular celular por Wi-Fi con adb

Usa esto si no quieres usar cable USB.

En el celular:

1. Ve a `Opciones de desarrollador`.
2. Activa `Depuracion por Wi-Fi`.
3. Entra a `Depuracion por Wi-Fi`.
4. Selecciona `Vincular dispositivo con codigo de vinculacion`.
5. Deja abierta esa pantalla porque muestra la IP, el puerto y el codigo.

En la laptop, si `adb` esta en el `PATH`:

```powershell
adb pair IP_DEL_CELULAR:PUERTO
```

Ingresa el codigo que aparece en el telefono.

Si `adb pair` no funciona porque PowerShell no encuentra `adb`, usa la ruta completa del SDK Android:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" pair 192.168.100.17:38495
```

Cambia `192.168.100.17:38495` por la IP y puerto que aparezcan en tu celular.

Despues de vincular, vuelve a la pantalla de `Depuracion por Wi-Fi`, toma la IP/puerto de conexion y ejecuta:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" connect IP_DEL_CELULAR:PUERTO_DE_CONEXION
flutter devices
```

Cuando el celular aparezca en `flutter devices`, ejecuta la app con la IP de la laptop:

```powershell
cd movil
flutter run --dart-define=BACKEND_URL=http://192.168.100.9:8000
```

### 14.3 Ejecutar app

```powershell
cd movil
flutter devices
flutter run --dart-define=BACKEND_URL=http://192.168.1.50:8000
```

Cambia `192.168.1.50` por tu IP real.

## 15. Ejecutar en celular fisico por USB con adb reverse

Esta alternativa evita depender de la WiFi local.

1. Conecta el celular por USB.
2. Verifica:

```powershell
flutter devices
```

3. Ejecuta:

```powershell
adb reverse tcp:8000 tcp:8000
```

4. Corre la app usando localhost del celular reenviado a la laptop:

```powershell
cd movil
flutter run --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

Si `adb` no se reconoce, Android SDK Platform-Tools no esta en el `PATH`. Normalmente Flutter igual puede correr la app, pero para `adb reverse` necesitas ubicar `adb.exe` en:

```text
C:\Users\TU_USUARIO\AppData\Local\Android\Sdk\platform-tools
```

## 16. Ejecutar contra Render

Para probar sin backend local:

```powershell
cd movil
flutter run --dart-define=BACKEND_URL=https://emergencia-vehicular.onrender.com
```

Esto ayuda a separar problemas:

- Si con Render funciona y local no, el problema es red local/firewall/IP/backend local.
- Si con Render tampoco funciona, el problema probablemente esta en app, auth, endpoints o datos.

## 17. Comandos durante flutter run

Cuando la app esta corriendo, la terminal acepta:

- `r`: hot reload, aplica cambios rapidos.
- `R`: hot restart, reinicia la app.
- `q`: detiene la app.

Primer build puede tardar mucho porque descarga Gradle y dependencias Android.

## 18. Primer checklist de prueba

### Instalacion

- `git --version` funciona.
- `flutter --version` funciona.
- `dart --version` funciona.
- `flutter doctor -v` no muestra errores criticos en Android.
- `flutter devices` muestra emulador o celular.

### Backend

- `curl http://localhost:8000/` responde.
- `curl http://localhost:8000/api/v1/health` responde.
- En celular fisico, el navegador abre `http://IP_DE_LAPTOP:8000/`.

### App movil

- `flutter pub get` termina bien.
- `flutter analyze` no muestra errores bloqueantes.
- `flutter run` instala la app.
- La app abre sin pantalla roja.
- La terminal muestra la URL `BACKEND_URL` esperada.
- El backend recibe peticiones.

### Funcionalidad minima

- Login con usuario cliente.
- Carga de vehiculos.
- Registro de vehiculo.
- Reporte de incidente.
- Ver incidente en frontend web/admin.
- Asignar taller/tecnico desde web.
- Revisar estado del incidente en movil.

## 19. Advertencia sobre el estado actual del movil

El proyecto movil existe, pero no esta completamente listo para pruebas reales.

Puntos ya detectados:

- `movil/lib/main.dart` esta en modo desarrollo y salta el login real.
- `movil/lib/backend_config.dart` define `10.0.2.2`, pero no lo usa automaticamente para emulador.
- Conviene usar siempre `--dart-define=BACKEND_URL=...` por ahora.
- El manifest principal Android no tiene permiso `INTERNET` para release.
- Las notificaciones moviles no tienen Firebase/FCM configurado.
- El historial de incidentes del cliente parece incompleto.
- Las rutas de vehiculos del backend deben revisarse porque `/vehiculos/usuario/{id}` puede chocar con `/vehiculos/{id}`.

## 20. Problemas comunes

### `flutter` no se reconoce

Flutter no esta en el `PATH`.

Solucion:

1. Revisa que exista `C:\Users\TU_USUARIO\develop\flutter\bin`.
2. Agregalo al `Path` de usuario.
3. Cierra y abre PowerShell.
4. Ejecuta `flutter --version`.

### `cmdline-tools component is missing`

Faltan herramientas Android.

Solucion:

1. Android Studio.
2. `More Actions > SDK Manager`.
3. `SDK Tools`.
4. Marca `Android SDK Command-line Tools`.
5. `Apply`.
6. Ejecuta `flutter doctor -v`.

### `Android license status unknown`

Faltan licencias.

Solucion:

```powershell
flutter doctor --android-licenses
```

Acepta con `y`.

### `No connected devices`

Flutter no ve emulador ni celular.

Solucion emulador:

```powershell
flutter emulators
```

Luego abre el emulador desde Android Studio.

Solucion celular:

- Activa `Depuracion USB`.
- Cambia cable USB si solo carga.
- Acepta el permiso RSA.
- Instala driver OEM si Windows no reconoce el telefono.

### `Connection refused`

La app intenta conectar, pero no hay servidor escuchando.

Revisa:

- Backend encendido.
- Puerto `8000`.
- URL correcta.
- Para emulador: `http://10.0.2.2:8000`.
- Para celular WiFi: `http://IP_DE_LAPTOP:8000`.
- Backend con `--host 0.0.0.0`.

### Timeout desde celular

La app no llega a la laptop.

Revisa:

- Celular y laptop en la misma WiFi.
- IP correcta.
- Firewall de Windows.
- Red WiFi no bloquea dispositivos entre si.

### Gradle tarda mucho o parece congelado

El primer build descarga dependencias. Puede tardar varios minutos. Dejalo correr.

Si falla por internet:

- Reintenta.
- Revisa conexion.
- Prueba `flutter clean` y `flutter pub get`.

### Error por ruta con espacios

El proyecto esta dentro de una ruta larga con espacios. Normalmente funciona, pero si Gradle o Flutter se ponen raros, una prueba util es clonar/copiar el repo a una ruta simple:

```text
C:\dev\emergencia.vehicular
```

## 21. Ruta recomendada para tu primera prueba

Para empezar desde cero, haz exactamente esto:

1. Instala Git.
2. Instala Flutter SDK.
3. Agrega Flutter al `PATH`.
4. Instala Android Studio.
5. Instala SDK Platforms y SDK Tools.
6. Instala plugins Flutter/Dart.
7. Ejecuta `flutter doctor --android-licenses`.
8. Ejecuta `flutter doctor -v`.
9. Crea un emulador Android.
10. Levanta backend local:

```powershell
cd backend
.\venv\Scripts\Activate.ps1
$env:DEBUG="True"
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

11. En otra terminal:

```powershell
cd movil
flutter pub get
flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

12. Cuando eso funcione en emulador, recien prueba celular fisico.
