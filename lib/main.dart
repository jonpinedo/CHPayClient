import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/theme.dart';
import 'bloc/tarjeta_bloc.dart';
import 'screens/home_screen.dart';

void main() {
  // Inicializar NFC para capturar intents al arrancar
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const ChPayApp());
}

class ChPayApp extends StatelessWidget {
  const ChPayApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CHPay - TPV NFC',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: BlocProvider(
        create: (context) => TarjetaBloc(),
        child: const HomeScreen(),
      ),
    );
  }
}

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
