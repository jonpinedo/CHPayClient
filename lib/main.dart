import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/theme.dart';
import 'bloc/tarjeta_bloc.dart';
import 'screens/home_screen.dart';
import 'screens/device_registration_screen.dart';
import 'services/auth_service.dart';

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
      } catch (e) {
        print('⚠️ Error al crear sesión: $e. Mostrando error.');
        return Future.value(Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Error de Sesión',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'No se pudo crear la sesión: $e',
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
        ));
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

