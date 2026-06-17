import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';
import '../services/nfc_service.dart';
import '../services/update_service.dart';
import '../services/auth_service.dart';
import 'pago_screen.dart';
import 'recarga_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  final UpdateInfo? pendingUpdate;
  const HomeScreen({Key? key, this.pendingUpdate}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String uid = '';
  String socioNombre = 'Esperando tarjeta...';
  int? numeroSocio;
  double saldo = 0.0;
  String estado = 'Listo';
  bool isLoading = false;
  bool tarjetaValida = false;
  
  // Información del dispositivo y roles
  String nombreDispositivo = 'Cargando...';
  List<String> roles = [];
  bool rolesLoaded = false;
  
  // Capítulo (multi-tenancy)
  int? capituloId;
  String? capituloNombre;
  Uint8List? capituloLogo;
  bool _sinCapitulo = false; // true si auth/me devuelve capitulo_id null
  
  // Control de sesión NFC persistente
  bool _nfcSessionActiva = false;
  bool _dismissedUpdate = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarInfoDispositivo();
    _cargarVersion();
    _iniciarSesionNfcPersistente();
    if (widget.pendingUpdate?.mandatory == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showMandatoryUpdateDialog(widget.pendingUpdate!);
      });
    }
  }

  @override
  void dispose() {
    _detenerSesionNfcPersistente();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Cuando la app vuelve al frente, reiniciar sesión NFC
      _iniciarSesionNfcPersistente();
    } else if (state == AppLifecycleState.paused) {
      // Cuando la app va al fondo, detener sesión NFC
      _detenerSesionNfcPersistente();
    }
  }

  Future<void> _cargarVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _appVersion = 'v${info.version}');
  }

  Future<void> _iniciarSesionNfcPersistente() async {
    if (_nfcSessionActiva) {
      print('ℹ️ Sesión NFC ya activa');
      return;
    }
    
    try {
      bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) {
        print('⚠️ NFC no disponible');
        return;
      }
      
      print('🔄 Iniciando sesión NFC persistente (foreground dispatch)');
      // Mantener sesión NFC activa sin cerrarla - esto implementa foreground dispatch
      // La sesión persistente tiene prioridad sobre el sistema Android
      await NfcManager.instance.startSession(
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          print('🏷️ Etiqueta NFC detectada en sesión persistente');
          await _procesarTagNfc(tag);
          // NO cerramos la sesión - se mantiene activa para bloquear el sistema
        },
      );
      _nfcSessionActiva = true;
      print('✅ Sesión NFC persistente activa');
    } catch (e) {
      print('❌ Error al iniciar sesión NFC persistente: $e');
      _nfcSessionActiva = false;
    }
  }
  
  Future<void> _detenerSesionNfcPersistente() async {
    if (!_nfcSessionActiva) return;
    
    try {
      print('🛑 Deteniendo sesión NFC persistente');
      await NfcManager.instance.stopSession();
      _nfcSessionActiva = false;
    } catch (e) {
      print('⚠️ Error al detener sesión NFC: $e');
    }
  }

  Future<void> _procesarTagNfc(NfcTag tag) async {
    try {
      setState(() {
        estado = 'Procesando tarjeta NFC...';
        isLoading = true;
        tarjetaValida = false;
      });

      // Extraer UID del tag
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag != null && androidTag.id.isNotEmpty) {
        final uidLeido = androidTag.id
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join('')
            .toUpperCase();
        
        print('✅ UID leído desde intent: $uidLeido');

        setState(() {
          uid = uidLeido;
          estado = 'Validando con servidor...';
        });

        // Validar tarjeta en API
        final resultado = await APIService.validarTarjeta(uidLeido);
        
        if (resultado.containsKey('error')) {
          setState(() {
            estado = 'Error: ${resultado['error']}';
            isLoading = false;
            tarjetaValida = false;
          });
          _mostrarError(resultado['error'].toString());
        } else {
          setState(() {
            socioNombre = resultado['nombre'] ?? 'Desconocido';
            numeroSocio = resultado['numero_socio'] as int?;
            final saldoValue = resultado['saldo'];
            if (saldoValue is double) {
              saldo = saldoValue;
            } else if (saldoValue is int) {
              saldo = saldoValue.toDouble();
            } else if (saldoValue is String) {
              saldo = double.tryParse(saldoValue) ?? 0.0;
            } else {
              saldo = 0.0;
            }
            estado = '✓ Tarjeta válida';
            isLoading = false;
            tarjetaValida = true;
          });
          
          if (resultado['monedero_creado'] == true) {
            _mostrarAvisoMonederoCreado();
          }
          HapticFeedback.mediumImpact();
        }
      }
    } catch (e) {
      print('❌ Error al procesar tag NFC: $e');
      setState(() {
        estado = 'Error al procesar: $e';
        isLoading = false;
        tarjetaValida = false;
      });
    }
  }

  Future<void> _cargarInfoDispositivo() async {
    try {
      print('📱 Cargando información del dispositivo...');
      final info = await APIService.obtenerInfoDispositivo();
      print('📦 Info recibida: $info');
      
      if (info.containsKey('error')) {
        print('⚠️ Error en respuesta: ${info['error']}');
        setState(() {
          nombreDispositivo = 'Error al cargar';
          estado = 'Error de conexión: ${info['error']}';
        });
      } else {
        // Extraer capítulo
        final capId = info['capitulo_id'];
        final capNombre = info['capitulo_nombre'] as String?;
        
        if (capId == null) {
          print('❌ Dispositivo sin capítulo asignado');
          setState(() {
            _sinCapitulo = true;
            nombreDispositivo = info['nombre'] ?? 'Dispositivo';
          });
          return;
        }
        
        print('✅ Dispositivo cargado: ${info['nombre']} - Capítulo: $capNombre');
        setState(() {
          nombreDispositivo = info['nombre'] ?? 'Dispositivo';
          roles = List<String>.from(info['roles'] ?? []);
          rolesLoaded = true;
          capituloId = capId is int ? capId : int.tryParse(capId.toString());
          capituloNombre = capNombre;
          estado = 'Listo';
        });
        
        // Cargar logo del capítulo en segundo plano
        if (capituloId != null) {
          _cargarLogoCapitulo(capituloId!);
        }
      }
    } catch (e) {
      print('❌ Excepción al cargar dispositivo: $e');
      setState(() {
        nombreDispositivo = 'Error';
        estado = 'No se pudo conectar al servidor: $e';
      });
    }
  }

  Future<void> _cargarLogoCapitulo(int id) async {
    final logo = await APIService.obtenerLogoCapitulo(id);
    if (logo != null && mounted) {
      setState(() => capituloLogo = logo);
    }
  }

  Future<void> _actualizarSaldoConUID({String? uidNuevo}) async {
    // Si se proporciona un nuevo UID, actualizarlo en el estado
    final uidAUsar = uidNuevo ?? uid;
    
    if (uidAUsar.isEmpty) return;
    
    try {
      setState(() {
        estado = 'Actualizando saldo...';
        isLoading = true;
      });
      
      // Validar tarjeta en API con el UID proporcionado o el existente
      final resultado = await APIService.validarTarjeta(uidAUsar);
      
      if (resultado.containsKey('error')) {
        setState(() {
          estado = 'Error: ${resultado['error']}';
          isLoading = false;
          tarjetaValida = false;
        });
      } else {
        setState(() {
          // Actualizar UID si se proporcionó uno nuevo
          if (uidNuevo != null) {
            uid = uidNuevo;
          }
          socioNombre = resultado['nombre'] ?? 'Desconocido';
          numeroSocio = resultado['numero_socio'] as int?;
          final saldoValue = resultado['saldo'];
          if (saldoValue is double) {
            saldo = saldoValue;
          } else if (saldoValue is int) {
            saldo = saldoValue.toDouble();
          } else if (saldoValue is String) {
            saldo = double.tryParse(saldoValue) ?? 0.0;
          } else {
            saldo = 0.0;
          }
          estado = '✓ Saldo actualizado';
          isLoading = false;
          tarjetaValida = true;
        });
        
        if (resultado['monedero_creado'] == true) {
          _mostrarAvisoMonederoCreado();
        }
      }
    } catch (e) {
      setState(() {
        estado = 'Error al actualizar: $e';
        isLoading = false;
      });
    }
  }

  Future<void> leerTarjeta() async {
    try {
      setState(() {
        estado = 'Leyendo tarjeta NFC...';
        isLoading = true;
        tarjetaValida = false;
      });
      
      final uidLeido = await NFCService.leerUID();
      
      if (uidLeido != null && uidLeido.isNotEmpty) {
        setState(() {
          uid = uidLeido;
          estado = 'Validando con servidor...';
        });
        
        // Validar tarjeta en API
        final resultado = await APIService.validarTarjeta(uidLeido);
        
        if (resultado.containsKey('error')) {
          setState(() {
            estado = 'Error: ${resultado['error']}';
            isLoading = false;
            tarjetaValida = false;
          });
          _mostrarError(resultado['error'].toString());
        } else {
          setState(() {
            socioNombre = resultado['nombre'] ?? 'Desconocido';
            numeroSocio = resultado['numero_socio'] as int?;
            // Convertir saldo de String a double
            final saldoValue = resultado['saldo'];
            if (saldoValue is double) {
              saldo = saldoValue;
            } else if (saldoValue is int) {
              saldo = saldoValue.toDouble();
            } else if (saldoValue is String) {
              saldo = double.tryParse(saldoValue) ?? 0.0;
            } else {
              saldo = 0.0;
            }
            estado = '✓ Tarjeta válida';
            isLoading = false;
            tarjetaValida = true;
          });
          
          if (resultado['monedero_creado'] == true) {
            _mostrarAvisoMonederoCreado();
          }
          // Vibración de éxito
          HapticFeedback.mediumImpact();
        }
      } else {
        setState(() {
          estado = 'No se pudo leer el UID';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        estado = 'Error: $e';
        isLoading = false;
        tarjetaValida = false;
      });
      _mostrarError(e.toString());
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _mostrarAvisoMonederoCreado() {
    if (!mounted) return;
    final cap = capituloNombre ?? 'este capítulo';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Monedero creado en $cap. Saldo: 0.00€'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showMandatoryUpdateDialog(UpdateInfo update) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Actualización requerida'),
        content: Text(
          'La versión ${update.versionName} es obligatoria.\n\n${update.changelog}',
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final bearer = await AuthService.getCurrentBearer();
              if (bearer != null) {
                await UpdateService.downloadAndInstall(bearer);
              }
            },
            child: const Text('Instalar ahora'),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateBanner(UpdateInfo update) {
    if (update.mandatory) {
      return const SizedBox.shrink();
    }
    return MaterialBanner(
      padding: const EdgeInsets.all(12),
      content: Text(
        'Nueva versión ${update.versionName} disponible',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      leading: const Icon(Icons.system_update, color: Colors.blue),
      backgroundColor: Colors.blue.shade50,
      actions: [
        TextButton(
          onPressed: () async {
            final bearer = await AuthService.getCurrentBearer();
            if (bearer != null) {
              await UpdateService.downloadAndInstall(bearer);
            }
          },
          child: const Text('INSTALAR'),
        ),
        TextButton(
          onPressed: () => setState(() => _dismissedUpdate = true),
          child: const Text('AHORA NO'),
        ),
      ],
    );
  }

  void _irAPago() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PagoScreen(
          uid: tarjetaValida ? uid : '',
          nombre: tarjetaValida ? socioNombre : '',
          saldoActual: tarjetaValida ? saldo : 0.0,
        ),
      ),
    ).then((resultado) {
      if (resultado is Map && resultado['actualizado'] == true) {
        // Actualizar saldo con el UID de la tarjeta usada en el pago
        final uidUsado = resultado['uid'] as String?;
        _actualizarSaldoConUID(uidNuevo: uidUsado);
      }
    });
  }

  void _irARecarga() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecargaScreen(
          uid: tarjetaValida ? uid : '',
          nombre: tarjetaValida ? socioNombre : '',
          saldoActual: tarjetaValida ? saldo : 0.0,
        ),
      ),
    ).then((resultado) {
      if (resultado is Map && resultado['actualizado'] == true) {
        // Actualizar saldo con el UID de la tarjeta usada en la recarga
        final uidUsado = resultado['uid'] as String?;
        _actualizarSaldoConUID(uidNuevo: uidUsado);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Bloquear si no tiene capítulo asignado
    if (_sinCapitulo) {
      return Scaffold(
        appBar: AppBar(title: const Text('CHPay')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Dispositivo sin capítulo asignado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Contacta al administrador para que asigne este dispositivo a un capítulo.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _sinCapitulo = false);
                    _cargarInfoDispositivo();
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (capituloLogo != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  radius: 14,
                  backgroundImage: MemoryImage(capituloLogo!),
                  backgroundColor: Colors.transparent,
                ),
              ),
            Text(capituloNombre ?? 'CHPay'),
          ],
        ),
        actions: [
          if (_appVersion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  _appVersion,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Banner de actualización disponible
              if (widget.pendingUpdate != null && !_dismissedUpdate)
                _buildUpdateBanner(widget.pendingUpdate!),
              // Banner de modo debug
              if (APIService.isDebugMode)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    border: Border.all(color: Colors.orange.shade700, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bug_report, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'MODO DEBUG: HTTP activo, NFC mockeado',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Panel información
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        tarjetaValida ? Icons.check_circle : Icons.nfc,
                        size: 48,
                        color: tarjetaValida ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        socioNombre,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saldo: ${saldo.toStringAsFixed(2)}€',
                        style: TextStyle(
                          fontSize: 28,
                          color: saldo > 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (numeroSocio != null)
                        Text(
                          'Socio #$numeroSocio',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isLoading
                              ? Colors.blue.shade50
                              : (tarjetaValida
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLoading)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            if (isLoading) const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                estado,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isLoading
                                      ? Colors.blue
                                      : (tarjetaValida
                                          ? Colors.green.shade700
                                          : Colors.grey.shade700),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Información del dispositivo
              if (rolesLoaded)
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.devices, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombreDispositivo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (capituloNombre != null)
                                Text(
                                  'Capítulo: $capituloNombre',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              Text(
                                'Roles: ${roles.join(", ")}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              
              // Botones de operación según roles
              if (rolesLoaded) ...[
                // Botones TERMINAL y CAJA
                if (roles.contains('TERMINAL') || roles.contains('CAJA'))
                  Row(
                    children: [
                      if (roles.contains('TERMINAL'))
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: !isLoading ? _irAPago : null,
                            icon: const Icon(Icons.payment),
                            label: const Text('COBRO'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.orange.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      if (roles.contains('TERMINAL') && roles.contains('CAJA'))
                        const SizedBox(width: 12),
                      if (roles.contains('CAJA'))
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: !isLoading ? _irARecarga : null,
                            icon: const Icon(Icons.add_circle),
                            label: const Text('RECARGA'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                
                // Botones ADMIN
                if (roles.contains('ADMIN')) ...[
                  if (roles.contains('TERMINAL') || roles.contains('CAJA'))
                    const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    '⚙️ Administración',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.admin_panel_settings),
                    label: const Text('Crear Socio'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AsociarTarjetaScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.credit_card),
                    label: const Text('Asociar Tarjeta NFC'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ] else
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
