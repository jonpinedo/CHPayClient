import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import '../services/api_service.dart';

class RecargaScreen extends StatefulWidget {
  final String uid;
  final String nombre;
  final double saldoActual;

  const RecargaScreen({
    Key? key,
    required this.uid,
    required this.nombre,
    required this.saldoActual,
  }) : super(key: key);

  @override
  State<RecargaScreen> createState() => _RecargaScreenState();
}

class _RecargaScreenState extends State<RecargaScreen> {
  final TextEditingController _descripcionController = TextEditingController();
  bool isProcessing = false;
  bool esperandoTarjeta = false;
  double montoConfirmado = 0.0;
  String uidValidado = '';
  String _monto = '';
  bool _nfcSessionActiva = false;

  // Montos rápidos predefinidos
  final List<double> montosRapidos = [5.0, 10.0, 20.0, 50.0];

  @override
  void dispose() {
    _detenerSesionNfc();
    _descripcionController.dispose();
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

  void _presionarNumero(String numero) {
    setState(() {
      if (numero == '.' && _monto.contains('.')) return;
      _monto += numero;
    });
  }

  void _borrar() {
    setState(() {
      if (_monto.isNotEmpty) {
        _monto = _monto.substring(0, _monto.length - 1);
      }
    });
  }

  void _limpiar() {
    setState(() {
      _monto = '';
    });
  }

  void _seleccionarMontoRapido(double monto) {
    setState(() {
      _monto = monto.toStringAsFixed(2);
    });
  }

  Future<void> _procesarRecarga() async {
    final descripcion = _descripcionController.text.trim();

    if (_monto.isEmpty) {
      _mostrarError('Ingresa un monto');
      return;
    }

    final monto = double.tryParse(_monto);
    if (monto == null || monto <= 0) {
      _mostrarError('Monto inválido');
      return;
    }

    // Cambiar a modo esperando tarjeta
    setState(() {
      esperandoTarjeta = true;
      montoConfirmado = monto;
    });
    
    // Iniciar lectura automática de NFC
    _leerTarjetaParaConfirmar();
  }

  Future<void> _confirmarConTarjeta() async {
    final descripcion = _descripcionController.text.trim();

    setState(() => isProcessing = true);

    try {
      final resultado = await APIService.hacerRecarga(
        uidValidado,
        montoConfirmado,
        descripcion.isEmpty ? 'Recarga' : descripcion,
      );

      setState(() => isProcessing = false);

      if (resultado.containsKey('error')) {
        _mostrarError(resultado['error'].toString());
      } else {
        HapticFeedback.heavyImpact();
        _mostrarExito('Recarga realizada: +${montoConfirmado.toStringAsFixed(2)}€');
        Future.delayed(const Duration(seconds: 1), () {
          Navigator.pop(context, {'actualizado': true, 'uid': uidValidado});
        });
      }
    } catch (e) {
      setState(() => isProcessing = false);
      _mostrarError('Error al procesar: $e');
    }
  }

  Future<void> _leerTarjetaParaConfirmar() async {
    try {
      setState(() {
        isProcessing = true;
      });
      
      bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) {
        setState(() => isProcessing = false);
        _mostrarError('NFC no disponible');
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
            final uidLeido = androidTag.id
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join('')
                .toUpperCase();
            
            // Validar tarjeta en API
            final resultado = await APIService.validarTarjeta(uidLeido);
            
            if (resultado.containsKey('error')) {
              setState(() => isProcessing = false);
              _mostrarError(resultado['error'].toString());
            } else {
              uidValidado = uidLeido;
              await _confirmarConTarjeta();
            }
          } else {
            setState(() => isProcessing = false);
            _mostrarError('No se pudo leer la tarjeta');
          }
        },
      );
      _nfcSessionActiva = true;
    } catch (e) {
      setState(() => isProcessing = false);
      _mostrarError('Error al leer tarjeta: $e');
    }
  }

  void _simularLecturaTarjeta() async {
    // Simular lectura en modo debug
    if (widget.uid.isNotEmpty) {
      uidValidado = widget.uid;
      await _confirmarConTarjeta();
    } else {
      _mostrarError('No hay tarjeta cargada. Lee una tarjeta primero desde la pantalla principal.');
    }
  }

  void _cancelarConfirmacion() {
    _detenerSesionNfc();
    setState(() {
      esperandoTarjeta = false;
      montoConfirmado = 0.0;
      uidValidado = '';
    });
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildTeclaNumero(String texto) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ElevatedButton(
          onPressed: isProcessing ? null : () => _presionarNumero(texto),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          child: Text(texto),
        ),
      ),
    );
  }

  Widget _buildTeclaOperacion(String texto, VoidCallback onPressed, {Color? color}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ElevatedButton(
          onPressed: isProcessing ? null : onPressed,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            backgroundColor: color ?? Colors.blue.shade700,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          child: Text(texto),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double montoActual = double.tryParse(_monto) ?? 0;
    
    // Si estamos esperando tarjeta, mostrar pantalla de confirmación
    if (esperandoTarjeta) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Confirmar Recarga'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _cancelarConfirmacion,
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.contactless,
                  size: 100,
                  color: Colors.green.shade700,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Acerca la tarjeta para confirmar la recarga',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Monto: +${montoConfirmado.toStringAsFixed(2)}€',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 32),
                if (isProcessing) ...[
                  const SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(strokeWidth: 6),
                  ),
                  const SizedBox(height: 32),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isProcessing) ...[
                      ElevatedButton.icon(
                        onPressed: _cancelarConfirmacion,
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: Colors.grey,
                        ),
                      ),
                      if (APIService.isDebugMode) ...[
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _simularLecturaTarjeta,
                          icon: const Icon(Icons.nfc),
                          label: const Text('Mock NFC'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // Pantalla normal de cálculo
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realizar Recarga'),
      ),
      body: Column(
        children: [
          // Info del socio
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    widget.nombre.isNotEmpty ? widget.nombre : 'Sin tarjeta leída',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (widget.uid.isNotEmpty)
                    Text(
                      'Saldo actual: ${widget.saldoActual.toStringAsFixed(2)}€',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    Text(
                      'Lee una tarjeta para ver el saldo',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Botones de montos rápidos
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: montosRapidos.map((monto) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      onPressed: isProcessing ? null : () => _seleccionarMontoRapido(monto),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade100,
                        foregroundColor: Colors.green.shade900,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('${monto.toStringAsFixed(0)}€', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Display principal
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Text(
              '${montoActual.toStringAsFixed(2)}€',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          // Teclado numérico
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('7'),
                        _buildTeclaNumero('8'),
                        _buildTeclaNumero('9'),
                        _buildTeclaOperacion('C', _limpiar, color: Colors.red.shade700),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('4'),
                        _buildTeclaNumero('5'),
                        _buildTeclaNumero('6'),
                        _buildTeclaOperacion('⌫', _borrar, color: Colors.orange.shade700),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('1'),
                        _buildTeclaNumero('2'),
                        _buildTeclaNumero('3'),
                        _buildTeclaOperacion('OK', _procesarRecarga, color: Colors.green.shade700),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('.'),
                        _buildTeclaNumero('0'),
                        Expanded(child: Container()),
                        Expanded(child: Container()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
