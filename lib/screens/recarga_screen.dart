import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import '../services/api_service.dart';

class RecargaScreen extends StatefulWidget {
  final String uid;
  final String nombre;
  final double saldoActual;
  final bool exigirIdentificacion;
  final String seguridadRecarga; // desactivada | pin | tarjeta

  const RecargaScreen({
    Key? key,
    required this.uid,
    required this.nombre,
    required this.saldoActual,
    this.exigirIdentificacion = false,
    this.seguridadRecarga = 'desactivada',
  }) : super(key: key);

  @override
  State<RecargaScreen> createState() => _RecargaScreenState();
}

enum _FaseNfc { cliente, operador }

class _RecargaScreenState extends State<RecargaScreen> {
  final TextEditingController _descripcionController = TextEditingController();
  bool isProcessing = false;
  bool esperandoTarjeta = false;
  double montoConfirmado = 0.0;
  String uidValidado = '';
  String _monto = '';
  bool _nfcSessionActiva = false;
  _FaseNfc _faseNfc = _FaseNfc.cliente;
  String? _ultimoError;

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
    if (_monto.isEmpty) {
      _mostrarError('Ingresa un monto');
      return;
    }

    final monto = double.tryParse(_monto);
    if (monto == null || monto <= 0) {
      _mostrarError('Monto inválido');
      return;
    }

    setState(() {
      esperandoTarjeta = true;
      montoConfirmado = monto;
      _faseNfc = _FaseNfc.cliente;
      _ultimoError = null;
    });

    _leerTarjeta(fase: _FaseNfc.cliente);
  }

  Future<void> _confirmarConTarjeta({String? pin, String? uidOperador}) async {
    final descripcion = _descripcionController.text.trim();

    setState(() {
      isProcessing = true;
      _ultimoError = null;
    });

    try {
      final resultado = await APIService.hacerRecarga(
        uidValidado,
        montoConfirmado,
        descripcion.isEmpty ? 'Recarga' : descripcion,
        pin: pin,
        uidOperador: uidOperador,
      );

      if (!mounted) return;

      if (resultado.containsKey('error')) {
        setState(() => isProcessing = false);
        await _manejarErrorRecarga(
          resultado['error']?.toString() ?? 'Error desconocido',
          resultado['codigo']?.toString(),
        );
        return;
      }

      setState(() => isProcessing = false);
      HapticFeedback.heavyImpact();
      _mostrarExito(
          'Recarga realizada: +${montoConfirmado.toStringAsFixed(2)}€');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pop(context, {'actualizado': true, 'uid': uidValidado});
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isProcessing = false);
      _mostrarError('Error al procesar: $e');
    }
  }

  Future<void> _manejarErrorRecarga(String mensaje, String? codigo) async {
    setState(() => _ultimoError = mensaje);
    _mostrarError(mensaje);

    switch (codigo) {
      case 'PIN_INVALIDO':
      case 'IDENTIFICACION_REQUERIDA':
        if (widget.seguridadRecarga == 'pin') {
          await _pedirPinYConfirmar();
        } else if (widget.seguridadRecarga == 'tarjeta') {
          setState(() {
            _faseNfc = _FaseNfc.operador;
            esperandoTarjeta = true;
          });
          _leerTarjeta(fase: _FaseNfc.operador);
        }
        break;
      case 'TARJETA_OPERADOR_INVALIDA':
        setState(() {
          _faseNfc = _FaseNfc.operador;
          esperandoTarjeta = true;
        });
        _leerTarjeta(fase: _FaseNfc.operador);
        break;
      case 'IDENTIFICACION_MODO_INCORRECTO':
        _mostrarError(
            'Error de cliente: modo de identificación incorrecto');
        break;
    }
  }

  Future<void> _despuesDeClienteValidado() async {
    if (!widget.exigirIdentificacion) {
      await _confirmarConTarjeta();
      return;
    }

    switch (widget.seguridadRecarga) {
      case 'pin':
        await _pedirPinYConfirmar();
        break;
      case 'tarjeta':
        setState(() {
          isProcessing = false;
          _faseNfc = _FaseNfc.operador;
          _ultimoError = null;
        });
        _leerTarjeta(fase: _FaseNfc.operador);
        break;
      default:
        await _confirmarConTarjeta();
    }
  }

  Future<void> _pedirPinYConfirmar() async {
    setState(() => isProcessing = false);
    await _detenerSesionNfc();

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinDialog(),
    );

    if (!mounted) return;

    if (pin == null) {
      // Cancelar aborta la recarga
      _cancelarConfirmacion();
      return;
    }

    await _confirmarConTarjeta(pin: pin);
  }

  Future<void> _leerTarjeta({required _FaseNfc fase}) async {
    try {
      setState(() {
        isProcessing = true;
        _faseNfc = fase;
      });

      await _detenerSesionNfc();

      bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) {
        setState(() => isProcessing = false);
        _mostrarError('NFC no disponible');
        return;
      }

      await NfcManager.instance.startSession(
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          _nfcSessionActiva = true;

          final androidTag = NfcTagAndroid.from(tag);
          if (androidTag == null || androidTag.id.isEmpty) {
            setState(() => isProcessing = false);
            _mostrarError('No se pudo leer la tarjeta');
            return;
          }

          final uidLeido = androidTag.id
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join('')
              .toUpperCase();

          if (fase == _FaseNfc.operador) {
            await _detenerSesionNfc();
            await _confirmarConTarjeta(uidOperador: uidLeido);
            return;
          }

          // Fase cliente: validar tarjeta
          final resultado = await APIService.validarTarjeta(uidLeido);

          if (resultado.containsKey('error')) {
            setState(() => isProcessing = false);
            _mostrarError(resultado['error'].toString());
            return;
          }

          if (resultado['monedero_creado'] == true) {
            _mostrarAvisoMonederoCreado();
          }

          uidValidado = uidLeido;
          await _detenerSesionNfc();
          await _despuesDeClienteValidado();
        },
      );
      _nfcSessionActiva = true;
    } catch (e) {
      setState(() => isProcessing = false);
      _mostrarError('Error al leer tarjeta: $e');
    }
  }

  void _simularLecturaTarjeta() async {
    if (_faseNfc == _FaseNfc.operador) {
      // Mock: reutilizar UID de la tarjeta en pantalla como operador
      if (widget.uid.isNotEmpty) {
        await _confirmarConTarjeta(uidOperador: widget.uid);
      } else {
        _mostrarError('No hay UID para mock de operador');
      }
      return;
    }

    if (widget.uid.isNotEmpty) {
      uidValidado = widget.uid;
      await _despuesDeClienteValidado();
    } else {
      _mostrarError(
          'No hay tarjeta cargada. Lee una tarjeta primero desde la pantalla principal.');
    }
  }

  void _cancelarConfirmacion() {
    _detenerSesionNfc();
    setState(() {
      esperandoTarjeta = false;
      isProcessing = false;
      montoConfirmado = 0.0;
      uidValidado = '';
      _faseNfc = _FaseNfc.cliente;
      _ultimoError = null;
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

  void _mostrarAvisoMonederoCreado() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Monedero creado en este capítulo. Saldo: 0.00€'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 4),
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
            textStyle:
                const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          child: Text(texto),
        ),
      ),
    );
  }

  Widget _buildTeclaOperacion(String texto, VoidCallback onPressed,
      {Color? color}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ElevatedButton(
          onPressed: isProcessing ? null : onPressed,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            backgroundColor: color ?? Colors.blue.shade700,
            foregroundColor: Colors.white,
            textStyle:
                const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          child: Text(texto),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double montoActual = double.tryParse(_monto) ?? 0;

    if (esperandoTarjeta) {
      final esOperador = _faseNfc == _FaseNfc.operador;
      return Scaffold(
        appBar: AppBar(
          title: Text(esOperador
              ? 'Identificación operador'
              : 'Confirmar Recarga'),
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
                  color: esOperador
                      ? Colors.orange.shade700
                      : Colors.green.shade700,
                ),
                const SizedBox(height: 24),
                Text(
                  esOperador
                      ? 'Acerca la tarjeta del operador'
                      : 'Acerca la tarjeta para confirmar la recarga',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
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
                if (_ultimoError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _ultimoError!,
                    style: TextStyle(color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Realizar Recarga'),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    widget.nombre.isNotEmpty
                        ? widget.nombre
                        : 'Sin tarjeta leída',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: montosRapidos.map((monto) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      onPressed: isProcessing
                          ? null
                          : () => _seleccionarMontoRapido(monto),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade100,
                        foregroundColor: Colors.green.shade900,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('${monto.toStringAsFixed(0)}€',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
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
                        _buildTeclaOperacion('C', _limpiar,
                            color: Colors.red.shade700),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('4'),
                        _buildTeclaNumero('5'),
                        _buildTeclaNumero('6'),
                        _buildTeclaOperacion('⌫', _borrar,
                            color: Colors.orange.shade700),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _buildTeclaNumero('1'),
                        _buildTeclaNumero('2'),
                        _buildTeclaNumero('3'),
                        _buildTeclaOperacion('OK', _procesarRecarga,
                            color: Colors.green.shade700),
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

/// Modal PIN: 4 dígitos numéricos, ocultos, teclado numérico.
class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final pin = _controller.text;
    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = 'El PIN debe tener exactamente 4 dígitos');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Identificación requerida'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Introduce el PIN del operador (4 dígitos)'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            obscuringCharacter: '•',
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: 'PIN',
              counterText: '',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _confirmar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _confirmar,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
