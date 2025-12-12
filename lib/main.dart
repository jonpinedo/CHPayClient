import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/theme.dart';
import 'bloc/tarjeta_bloc.dart';
import 'screens/home_screen.dart';
import 'screens/device_registration_screen.dart';
import 'screens/device_certificate_renewal_screen.dart';
import 'services/api_service.dart';
import 'services/device_service.dart';

void main() {
  // Configurar SSL para desarrollo (ignorar certificados self-signed)
  APIService.configurarSSL();
  
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
    // Verificar estado del dispositivo
    final status = await DeviceService.checkDeviceStatus();
    
    print('🔍 [ChPayApp] Estado del dispositivo: ${status['status']}');
    print('📦 [ChPayApp] Detalles: $status');
    
    if (status['status'] == 'not_registered') {
      // Dispositivo no registrado
      print('➡️ [ChPayApp] Navegando a DeviceRegistrationScreen (not_registered)');
      return DeviceRegistrationScreen(
        onRegistrationComplete: () {
          setState(() {
            _homeScreenFuture = Future.value(_buildHomeScreen());
          });
        },
      );
    } else if (status['status'] == 'registrado' || status['status'] == 'aprobado') {
      // Dispositivo registrado o aprobado, necesita instalar certificado
      print('➡️ [ChPayApp] Navegando a DeviceRegistrationScreen (${status['status']})');
      return DeviceRegistrationScreen(
        onRegistrationComplete: () {
          setState(() {
            _homeScreenFuture = Future.value(_buildHomeScreen());
          });
        },
      );
    } else if (status['status'] == 'certificado') {
      // Certificado instalado, verificar si necesita renovación
      final needsRenewal = status['dias_para_expiry'] != null && 
                          status['dias_para_expiry'] < 30;
      
      if (needsRenewal) {
        print('➡️ [ChPayApp] Navegando a DeviceCertificateRenewalScreen');
        return DeviceCertificateRenewalScreen(
          daysToExpiry: status['dias_para_expiry'],
          onRenewalComplete: () {
            setState(() {
              _homeScreenFuture = Future.value(_buildHomeScreen());
            });
          },
        );
      }
    }
    
    print('➡️ [ChPayApp] Navegando a HomeScreen');
    return _buildHomeScreen();
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
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 80, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Error al verificar dispositivo'),
                    const SizedBox(height: 16),
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
          
          return snapshot.data ?? const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}
