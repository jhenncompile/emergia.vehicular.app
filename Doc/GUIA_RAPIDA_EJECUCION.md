# Guia rapida para ejecutar backend, frontend y movil

Esta guia es para levantar el proyecto en desarrollo local cuando ya tienes las dependencias instaladas.

## 1. Backend

Abre una terminal en la raiz del proyecto:

```powershell
cd backend
.\venv\Scripts\Activate.ps1
$env:DEBUG="True"
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Tambien puedes usar el script del proyecto:

```powershell
cd backend
.\start-backend-dev.ps1
```

Verifica en el navegador:

```text
http://localhost:8000/docs
```

Para que el celular pueda entrar al backend, el servidor debe estar con `--host 0.0.0.0` y el celular debe estar en la misma red Wi-Fi que la laptop.

## 2. Frontend

Abre otra terminal:

```powershell
cd frontend
npm install
npm start
```

El frontend normalmente queda disponible en:

```text
http://localhost:4200
```

Si usas Yarn:

```powershell
cd frontend
yarn install
yarn start
```

## 3. Movil Flutter

Abre otra terminal:

```powershell
cd movil
flutter pub get
flutter analyze
flutter run --dart-define=BACKEND_URL=http://192.168.100.9:8000
```

Cambia `192.168.100.9` si la IP de la laptop cambia. Para verla:

```powershell
ipconfig
```

Busca la `Direccion IPv4` del adaptador Wi-Fi.

## 4. Crear APK de pruebas

Cuando quieras generar un APK para instalarlo manualmente en un celular:

```powershell
cd movil
flutter build apk --release --dart-define=BACKEND_URL=https://tu-backend-publico.com
```

El APK se genera en:

```text
movil\build\app\outputs\flutter-apk\app-release.apk
```

Si quieres crear un APK de pruebas apuntando al backend local de tu laptop, usa la IP Wi-Fi de la laptop:

```powershell
cd movil
flutter build apk --release --dart-define=BACKEND_URL=http://192.168.100.9:8000
```

Para que ese APK local funcione:

- El backend debe estar encendido con `--host 0.0.0.0`.
- El celular y la laptop deben estar en la misma red Wi-Fi.
- Si cambia la IP de la laptop, vuelve a generar el APK con la nueva IP.
- Si Android bloquea HTTP local, revisar configuracion de cleartext traffic para pruebas.

## 5. Vincular celular por Wi-Fi con adb

Usa esto si no quieres conectar el celular por cable.

### 5.1 En el celular

1. Ve a `Configuracion`.
2. Entra a `Opciones de desarrollador`.
3. Activa `Depuracion por Wi-Fi`.
4. Entra a `Depuracion por Wi-Fi`.
5. Toca `Vincular dispositivo con codigo de vinculacion`.
6. Deja esa pantalla abierta: muestra una IP, un puerto y un codigo.

### 5.2 En la laptop

Si `adb` esta en el `PATH`, usa:

```powershell
adb pair IP_DEL_CELULAR:PUERTO
```

Ingresa el codigo que muestra el telefono.

Si eso no funciona porque PowerShell no encuentra `adb`, usa la ruta completa:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" pair 192.168.100.17:38495
```

Cambia `192.168.100.17:38495` por la IP y puerto que aparezcan en tu celular.

Despues de vincular, vuelve a la pantalla de `Depuracion por Wi-Fi` y toma la IP/puerto de conexion. Luego ejecuta:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" connect IP_DEL_CELULAR:PUERTO_DE_CONEXION
flutter devices
```

Cuando el celular aparezca en `flutter devices`, puedes correr:

```powershell
cd movil
flutter run --dart-define=BACKEND_URL=http://192.168.100.9:8000
```

## 6. Orden recomendado

1. Encender backend.
2. Probar `http://localhost:8000/docs`.
3. Encender frontend.
4. Vincular o conectar el celular.
5. Ejecutar `flutter devices`.
6. Ejecutar `flutter run --dart-define=BACKEND_URL=http://192.168.100.9:8000`.
