import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import '../services/api_service.dart';
import '../services/nfc_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numeroSocioController = TextEditingController();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _saldoInicialController = TextEditingController(text: '0.00');
  
  bool _isLoading = false;
  String? _mensaje;
  bool _socioCreado = false;
  int? _numeroSocioCreado;

  @override
  void dispose() {
    _numeroSocioController.dispose();
    _nombreController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _saldoInicialController.dispose();
    super.dispose();
  }

  Future<void> _crearSocio() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _mensaje = null;
    });

    try {
      final resultado = await APIService.crearSocio(
        nombre: _nombreController.text,
        email: _emailController.text.isEmpty ? null : _emailController.text,
        telefono: _telefonoController.text.isEmpty ? null : _telefonoController.text,
        saldoInicial: _saldoInicialController.text,
      );

      if (resultado.containsKey('error')) {
        setState(() {
          _mensaje = 'Error: ${resultado['error']}';
          _isLoading = false;
        });
      } else {
        // El backend devuelve el numero_socio generado
        final numeroSocio = resultado['numero_socio'];
        setState(() {
          _mensaje = 'Socio creado correctamente\nNúmero de socio: $numeroSocio';
          _socioCreado = true;
          _numeroSocioCreado = numeroSocio is int ? numeroSocio : int.tryParse(numeroSocio.toString());
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _mensaje = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  void _limpiarFormulario() {
    _formKey.currentState?.reset();
    _numeroSocioController.clear();
    _nombreController.clear();
    _emailController.clear();
    _telefonoController.clear();
    _saldoInicialController.text = '0.00';
    setState(() {
      _socioCreado = false;
      _numeroSocioCreado = null;
      _mensaje = null;
    });
  }

  void _irAsociarTarjeta() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EsperarTarjetaNFCScreen(
          numeroSocio: _numeroSocioCreado!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '👤 Crear Nuevo Socio',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'El número de socio será generado automáticamente',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingrese el nombre del socio';
                  }
                  if (value.length < 3) {
                    return 'El nombre debe tener al menos 3 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoController,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _saldoInicialController,
                decoration: const InputDecoration(
                  labelText: 'Saldo Inicial (€)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.euro),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingrese el saldo inicial';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Ingrese un valor válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_mensaje != null)
                Card(
                  color: _socioCreado ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _mensaje!,
                      style: TextStyle(
                        color: _socioCreado ? Colors.green.shade900 : Colors.red.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (!_socioCreado)
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _crearSocio,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  label: Text(_isLoading ? 'Creando...' : 'Crear Socio'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              if (_socioCreado) ...[
                ElevatedButton.icon(
                  onPressed: _irAsociarTarjeta,
                  icon: const Icon(Icons.credit_card),
                  label: const Text('Asociar Tarjeta NFC'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _limpiarFormulario,
                  icon: const Icon(Icons.add),
                  label: const Text('Crear Otro Socio'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Pantalla para asociar tarjeta
class AsociarTarjetaScreen extends StatefulWidget {
  final int? numeroSocio;
  const AsociarTarjetaScreen({super.key, this.numeroSocio});

  @override
  State<AsociarTarjetaScreen> createState() => _AsociarTarjetaScreenState();
}

class _AsociarTarjetaScreenState extends State<AsociarTarjetaScreen> {
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoadingSocios = true;
  String? _mensaje;
  
  List<Map<String, dynamic>> _socios = [];
  int? _socioSeleccionado;

  @override
  void initState() {
    super.initState();
    _socioSeleccionado = widget.numeroSocio;
    _cargarSocios();
  }

  Future<void> _cargarSocios() async {
    setState(() => _isLoadingSocios = true);
    try {
      final socios = await APIService.listarSocios();
      setState(() {
        _socios = socios;
        _isLoadingSocios = false;
      });
    } catch (e) {
      setState(() {
        _mensaje = 'Error al cargar socios: $e';
        _isLoadingSocios = false;
      });
    }
  }

  void _navegarAEsperaNFC() {
    if (!_formKey.currentState!.validate()) return;
    if (_socioSeleccionado == null) {
      setState(() => _mensaje = 'Seleccione un socio');
      return;
    }

    // Navegar a la pantalla de espera de NFC
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EsperarTarjetaNFCScreen(numeroSocio: _socioSeleccionado!),
      ),
    ).then((_) {
      // Al volver, regresar a la pantalla anterior
      Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asociar Tarjeta NFC'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoadingSocios
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '💳 Asociar Tarjeta NFC',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<int>(
                      value: _socioSeleccionado,
                      decoration: const InputDecoration(
                        labelText: 'Seleccionar Socio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      items: _socios.map((socio) {
                        final numero = socio['numero_socio'];
                        final nombre = socio['nombre'] ?? 'Sin nombre';
                        return DropdownMenuItem<int>(
                          value: numero is int ? numero : int.tryParse(numero.toString()),
                          child: Text('#$numero - $nombre'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _socioSeleccionado = value);
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'Seleccione un socio';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    if (_mensaje != null)
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            _mensaje!,
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    if (_mensaje != null)
                      const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _navegarAEsperaNFC,
                      icon: const Icon(Icons.nfc),
                      label: const Text('Asociar Tarjeta'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// Pantalla simple de espera de tarjeta NFC (tras crear socio)
class EsperarTarjetaNFCScreen extends StatefulWidget {
  final int numeroSocio;
  
  const EsperarTarjetaNFCScreen({super.key, required this.numeroSocio});

  @override
  State<EsperarTarjetaNFCScreen> createState() => _EsperarTarjetaNFCScreenState();
}

class _EsperarTarjetaNFCScreenState extends State<EsperarTarjetaNFCScreen> {
  bool _leyendo = true;
  String _mensaje = 'Acerca la tarjeta NFC al dispositivo...';
  bool _exito = false;
  bool _nfcSessionActiva = false;

  @override
  void initState() {
    super.initState();
    _iniciarLecturaNFC();
  }
  
  @override
  void dispose() {
    _detenerSesionNfc();
    super.dispose();
  }
  
  Future<void> _detenerSesionNfc() async {
    if (_nfcSessionActiva) {
      try {
        await NfcManager.instance.stopSession();
        _nfcSessionActiva = false;
      } catch (e) {
        print('⚠️ Error al detener sesión NFC: $e');
      }
    }
  }

  Future<void> _iniciarLecturaNFC() async {
    try {
      bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) {
        setState(() {
          _leyendo = false;
          _mensaje = 'NFC no disponible';
          _exito = false;
        });
        return;
      }
      
      // Iniciar sesión NFC persistente
      await NfcManager.instance.startSession(
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          _nfcSessionActiva = true;
          
          // Extraer UID
          final androidTag = NfcTagAndroid.from(tag);
          if (androidTag != null && androidTag.id.isNotEmpty) {
            final uid = androidTag.id
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join('')
                .toUpperCase();
            
            // Asociar automáticamente
            final resultado = await APIService.asociarTarjeta(
              numeroSocio: widget.numeroSocio,
              uid: uid,
              descripcion: null,
            );

            if (resultado.containsKey('error')) {
              setState(() {
                _leyendo = false;
                _mensaje = 'Error: ${resultado['error']}';
                _exito = false;
              });
            } else {
              setState(() {
                _leyendo = false;
                _mensaje = resultado['mensaje'] ?? 'Tarjeta asociada correctamente';
                _exito = true;
              });
            }
          } else {
            setState(() {
              _leyendo = false;
              _mensaje = 'No se pudo leer la tarjeta';
              _exito = false;
            });
          }
        },
      );
      _nfcSessionActiva = true;
    } catch (e) {
      setState(() {
        _leyendo = false;
        _mensaje = 'Error: $e';
        _exito = false;
      });
    }
  }

  Future<void> _mockNFC() async {
    setState(() {
      _leyendo = true;
      _mensaje = 'Generando tarjeta mock...';
    });

    try {
      final uid = NFCService.generarUidAleatorio();
      final resultado = await APIService.asociarTarjeta(
        numeroSocio: widget.numeroSocio,
        uid: uid,
        descripcion: 'Tarjeta mock',
      );

      if (resultado.containsKey('error')) {
        setState(() {
          _leyendo = false;
          _mensaje = 'Error: ${resultado['error']}';
          _exito = false;
        });
      } else {
        setState(() {
          _leyendo = false;
          _mensaje = resultado['mensaje'] ?? 'Tarjeta mock asociada correctamente';
          _exito = true;
        });
      }
    } catch (e) {
      setState(() {
        _leyendo = false;
        _mensaje = 'Error: $e';
        _exito = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asociar Tarjeta NFC'),
        automaticallyImplyLeading: !_exito, // Solo permitir volver atrás si no tuvo éxito
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_leyendo) ...[
                const SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(strokeWidth: 6),
                ),
                const SizedBox(height: 32),
              ] else ...[
                Icon(
                  _exito ? Icons.check_circle : Icons.error,
                  size: 100,
                  color: _exito ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 32),
              ],
              Text(
                _mensaje,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_exito) ...[
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.grey,
                      ),
                    ),
                    if (APIService.isDebugMode && _leyendo) ...[
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _mockNFC,
                        icon: const Icon(Icons.nfc),
                        label: const Text('Mock NFC'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ],
                  ],
                  if (_exito)
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check),
                      label: const Text('Finalizar'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.green,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
