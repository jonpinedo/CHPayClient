import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import '../services/api_service.dart';

class PagoScreen extends StatefulWidget {
  final String uid;
  final String nombre;
  final double saldoActual;

  const PagoScreen({
    Key? key,
    required this.uid,
    required this.nombre,
    required this.saldoActual,
  }) : super(key: key);

  @override
  State<PagoScreen> createState() => _PagoScreenState();
}

class _PagoScreenState extends State<PagoScreen> {
  final TextEditingController _descripcionController = TextEditingController();
  bool isProcessing = false;
  bool esperandoTarjeta = false;
  double montoConfirmado = 0.0;
  String uidValidado = '';
  bool _nfcSessionActiva = false;
  
  // Estado de la calculadora
  String _displayOperaciones = '';
  String _numeroActual = '';
  double _total = 0;
  String? _operacionPendiente;
  double? _valorParaMultiplicar;
  bool _multiplicarProximo = false;

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
      if (numero == '.' && _numeroActual.contains('.')) return;
      _numeroActual += numero;
    });
  }

  void _presionarSumar() {
    if (_numeroActual.isEmpty) return;
    
    setState(() {
      double valor = double.parse(_numeroActual);
      
      if (_multiplicarProximo && _valorParaMultiplicar != null) {
        valor = _valorParaMultiplicar! * valor;
        _multiplicarProximo = false;
        _valorParaMultiplicar = null;
      }
      
      _total += valor;
      _displayOperaciones += _numeroActual + ' + ';
      _numeroActual = '';
    });
  }

  void _presionarMultiplicar() {
    if (_numeroActual.isEmpty) return;
    
    setState(() {
      _valorParaMultiplicar = double.parse(_numeroActual);
      _displayOperaciones += _numeroActual + ' × ';
      _numeroActual = '';
      _multiplicarProximo = true;
    });
  }

  void _borrar() {
    setState(() {
      if (_numeroActual.isNotEmpty) {
        // Borrar último dígito del número actual
        _numeroActual = _numeroActual.substring(0, _numeroActual.length - 1);
      } else if (_displayOperaciones.isNotEmpty) {
        // Eliminar hasta el anterior '+'
        if (_multiplicarProximo) {
          // Si había multiplicación pendiente, cancelarla
          final lastPlus = _displayOperaciones.lastIndexOf(' + ');
          if (lastPlus != -1) {
            _displayOperaciones = _displayOperaciones.substring(0, lastPlus + 3);
          }
          _multiplicarProximo = false;
          _valorParaMultiplicar = null;
        } else {
          // Eliminar última suma
          final lastPlus = _displayOperaciones.lastIndexOf(' + ');
          if (lastPlus != -1) {
            final beforePlus = _displayOperaciones.substring(0, lastPlus);
            _displayOperaciones = beforePlus.contains(' + ') 
                ? beforePlus.substring(0, beforePlus.lastIndexOf(' + ') + 3)
                : '';
            _recalcularTotal();
          }
        }
      }
    });
  }

  void _limpiar() {
    setState(() {
      _numeroActual = '';
      _displayOperaciones = '';
      _total = 0;
      _operacionPendiente = null;
      _valorParaMultiplicar = null;
      _multiplicarProximo = false;
    });
  }

  void _recalcularTotal() {
    // Recalcular total desde displayOperaciones
    _total = 0;
    final ops = _displayOperaciones.split(' + ');
    for (var op in ops) {
      op = op.trim();
      if (op.isEmpty) continue;
      
      if (op.contains(' × ')) {
        final parts = op.split(' × ');
        double result = 1;
        for (var part in parts) {
          result *= double.tryParse(part.trim()) ?? 0;
        }
        _total += result;
      } else {
        _total += double.tryParse(op) ?? 0;
      }
    }
  }

  double get _totalCalculado {
    double resultado = _total;
    if (_numeroActual.isNotEmpty) {
      double valorActual = double.tryParse(_numeroActual) ?? 0;
      if (_multiplicarProximo && _valorParaMultiplicar != null) {
        resultado += _valorParaMultiplicar! * valorActual;
      } else {
        resultado += valorActual;
      }
    }
    return resultado;
  }

  Future<void> _procesarPago() async {
    final monto = _totalCalculado;
    final descripcion = _descripcionController.text.trim();

    if (monto <= 0) {
      _mostrarError('Ingresa un monto');
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
      final resultado = await APIService.hacerPago(
        uidValidado,
        montoConfirmado,
        descripcion.isEmpty ? 'Pago' : descripcion,
      );

      setState(() => isProcessing = false);

      if (resultado.containsKey('error')) {
        _mostrarError(resultado['error'].toString());
      } else {
        HapticFeedback.heavyImpact();
        _mostrarExito('Pago realizado: ${montoConfirmado.toStringAsFixed(2)}€');
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
              final saldoTarjeta = resultado['saldo'] is double 
                  ? resultado['saldo'] 
                  : double.tryParse(resultado['saldo'].toString()) ?? 0.0;
              
              if (montoConfirmado > saldoTarjeta) {
                setState(() => isProcessing = false);
                _mostrarError('Saldo insuficiente en la tarjeta');
                return;
              }
              
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

  Widget _buildTeclaOperacion(String texto, VoidCallback onPressed, {bool habilitado = true}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ElevatedButton(
          onPressed: (isProcessing || !habilitado) ? null : onPressed,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            backgroundColor: habilitado ? Colors.orange.shade700 : Colors.grey.shade400,
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
    final bool multiplicarHabilitado = _numeroActual.isNotEmpty && !_multiplicarProximo;
    final bool sumarHabilitado = _numeroActual.isNotEmpty;
    
    // Si estamos esperando tarjeta, mostrar pantalla de confirmación
    if (esperandoTarjeta) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Confirmar Pago'),
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
                  color: Colors.orange.shade700,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Acerca la tarjeta para confirmar el pago',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Monto: ${montoConfirmado.toStringAsFixed(2)}€',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
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
        title: const Text('Realizar Pago'),
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
                      'Saldo: ${widget.saldoActual.toStringAsFixed(2)}€',
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
          // Display de operaciones (pequeño)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _displayOperaciones + _numeroActual + (_multiplicarProximo ? ' (× pendiente)' : ''),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
          // Display principal (grande)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Text(
              '${_totalCalculado.toStringAsFixed(2)}€',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
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
                        _buildTeclaOperacion('C', _limpiar),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('4'),
                        _buildTeclaNumero('5'),
                        _buildTeclaNumero('6'),
                        _buildTeclaOperacion('⌫', _borrar),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('1'),
                        _buildTeclaNumero('2'),
                        _buildTeclaNumero('3'),
                        _buildTeclaOperacion('+', _presionarSumar, habilitado: sumarHabilitado),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('.'),
                        _buildTeclaNumero('0'),
                        _buildTeclaOperacion('×', _presionarMultiplicar, habilitado: multiplicarHabilitado),
                        _buildTeclaOperacion('OK', _procesarPago, habilitado: _totalCalculado > 0),
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
