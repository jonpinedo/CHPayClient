# CHPay Client - Lector NFC

Aplicación Flutter para lectura de etiquetas NFC en Android.

##  Entorno Configurado

### Instalado
-  Flutter 3.38.3 (stable)
-  Android SDK 36.1.0
-  Android Build Tools 28.0.3
-  Android Studio 2024.2.1
-  Plugin NFC Manager 3.5.0

### Variables de Entorno
ANDROID_HOME = C:\Users\jpinedo\AppData\Local\Android\Sdk
PATH incluye:
  - C:\src\flutter\bin
  - %ANDROID_HOME%\platform-tools
  - %ANDROID_HOME%\cmdline-tools\latest\bin

##  Ejecutar en Dispositivo

### 1. Conectar teléfono Android
1. Activar **Modo Desarrollador**:
   - Ir a Ajustes > Acerca del teléfono
   - Tocar 7 veces en Número de compilación
   
2. Activar **Depuración USB**:
   - Ajustes > Sistema > Opciones de desarrollador
   - Activar Depuración USB

3. Conectar cable USB al PC
4. Autorizar el dispositivo (aparecerá diálogo en el teléfono)

### 2. Verificar conexión
adb devices

Debe mostrar tu dispositivo con estado device.

### 3. Ejecutar aplicación
cd C:\dev\chpayclient
flutter run

##  Uso de la Aplicación

1. Abrir la app en tu teléfono
2. Verificar que aparezca ícono NFC verde (indica NFC disponible)
3. Presionar botón "Leer Etiqueta NFC"
4. Acercar tarjeta/etiqueta NFC al teléfono
5. Los datos leídos aparecerán en pantalla

### Formatos Soportados
- NDEF (NFC Data Exchange Format)
- Registros de texto
- URIs
- Tipos MIME
- Payloads hexadecimales

##  Permisos Configurados

En android/app/src/main/AndroidManifest.xml:
<uses-permission android:name="android.permission.NFC"/>
<uses-feature android:name="android.hardware.nfc" android:required="true"/>

##  Comandos Útiles

# Ver dispositivos conectados
adb devices

# Ver logs en tiempo real
flutter logs

# Compilar APK
flutter build apk --release

# Limpiar y rebuildar
flutter clean
flutter pub get
flutter run

##  Troubleshooting

### Dispositivo no detectado
adb kill-server
adb start-server
adb devices

### NFC no disponible
- Verificar hardware NFC en teléfono
- Activar NFC en Ajustes > Conexiones > NFC
- Revisar permisos en AndroidManifest.xml