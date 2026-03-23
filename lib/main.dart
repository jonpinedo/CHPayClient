import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/theme.dart';
import 'bloc/tarjeta_bloc.dart';
import 'screens/home_screen.dart';
import 'screens/device_registration_screen.dart';
import 'screens/ziti_enrollment_screen.dart';
import 'services/auth_service.dart';
import 'services/ziti_service.dart';

void main() async {
  // Inicializar NFC para capturar intents al arrancar
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const ChPayApp());
}

class ChPayApp extends StatefulWidget {
  const ChPayApp({Key? key}) : super(key: key);

  @override
  State<ChPayApp> createState() => _ChPayAppState();
}

class _ChPayAppState extends State<ChPayApp> {
  late Future<Widget> _homeScreenFuture;

  @override
  void initState() {
    super.initState();
    _homeScreenFuture = _determineInitialScreen();
  }

  Future<Widget> _determineInitialScreen() async {
    try {
      // 1. Check Ziti identity
      print('🔍 Verificando identidad Ziti...');
      final hasIdentity = await ZitiService.hasIdentity();

      if (!hasIdentity) {
        print('📱 No hay identidad Ziti. Mostrando pantalla de enrollment.');
        return ZitiEnrollmentScreen(
          onEnrollmentComplete: () {
            setState(() {
              _homeScreenFuture = _determineInitialScreen();
            });
          },
        );
      }

      // 2. Initialize Ziti overlay
      print('🔄 Inicializando overlay Ziti...');
      final zitiOk = await ZitiService.initialize();
      if (!zitiOk) {
        print('⚠️ No se pudo conectar a Ziti. Mostrando error con opción de re-enroll.');
        return _buildErrorScreen(
          'Error de Conexión Ziti',
          'No se pudo conectar a la red segura.\n\nLa identidad puede haber sido revocada o el servidor no está accesible.',
          showReenroll: true,
        );
      } else {
        print('✅ Overlay Ziti conectado');
      }

      // 3. Check device authorization
      print('🔍 Verificando autenticación del dispositivo...');
      
      // Verificar si el dispositivo está autorizado
      final isAuthorized = await AuthService.isAuthorized();
      
      if (!isAuthorized) {
        print('❌ Dispositivo no autorizado. Mostrando pantalla de registro.');
        return DeviceRegistrationScreen(
          onRegistrationComplete: () {
            setState(() {
              _homeScreenFuture = Future.value(_buildHomeScreen());
            });
          },
        );
      }
      
      // Crear sesión para obtener bearer
      try {
        print('🔄 Creando sesión para obtener bearer...');
        await AuthService.createSession();
        print('✅ Sesión creada correctamente');
      } on AuthException catch (e) {
        print('⚠️ Error al crear sesión: $e (isAuthError=${e.isAuthError})');
        if (e.isAuthError) {
          // 401/403 — credentials are invalid, clear and re-register
          print('🔄 Credenciales rechazadas. Limpiando y mostrando registro...');
          await AuthService.clearCredentials();
          return DeviceRegistrationScreen(
            onRegistrationComplete: () {
              setState(() {
                _homeScreenFuture = _determineInitialScreen();
              });
            },
          );
        } else {
          // Other HTTP error — don't wipe credentials
          print('⚠️ Error de servidor, credenciales conservadas.');
          return _buildErrorScreen(
            'Error de Sesión',
            'No se pudo crear la sesión: $e',
          );
        }
      } catch (e) {
        // Network/connection error — definitely don't wipe credentials
        print('⚠️ Error de red al crear sesión: $e');
        return _buildErrorScreen(
          'Error de Conexión',
          'No se pudo conectar al servidor.\nVerifica tu conexión de red e inténtalo de nuevo.',
          showReenroll: true,
        );
      }
      
      print('✅ Dispositivo autorizado. Mostrando HomeScreen.');
      return _buildHomeScreen();
    } catch (e) {
      print('❌ Error en determineInitialScreen: $e');
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Error Inesperado',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '$e',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _homeScreenFuture = _determineInitialScreen();
                  });
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildHomeScreen() {
    return BlocProvider(
      create: (context) => TarjetaBloc(),
      child: const HomeScreen(),
    );
  }

  Widget _buildErrorScreen(String title, String message, {bool showReenroll = false}) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _homeScreenFuture = _determineInitialScreen();
                  });
                },
                child: const Text('Reintentar'),
              ),
              if (showReenroll) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ZitiService.deleteIdentity();
                    await AuthService.clearCredentials();
                    setState(() {
                      _homeScreenFuture = _determineInitialScreen();
                    });
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Re-enrollar identidad'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CHPay - TPV NFC',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: FutureBuilder<Widget>(
        future: _homeScreenFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Inicializando...'),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Error de Inicialización',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _homeScreenFuture = _determineInitialScreen();
                        });
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          return snapshot.data ?? const SizedBox.shrink();
        },
      ),
    );
  }
}

