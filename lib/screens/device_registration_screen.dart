import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class DeviceRegistrationScreen extends StatefulWidget {
  final VoidCallback onRegistrationComplete;
  
  const DeviceRegistrationScreen({
    Key? key,
    required this.onRegistrationComplete,
  }) : super(key: key);

  @override
  State<DeviceRegistrationScreen> createState() => _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  late TextEditingController _nameController;
  String _status = 'input'; // input, requesting, pending, authorizing, authorized, error
  String _errorMessage = '';
  String _deviceId = '';
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadDeviceInfo();
  }
  
  Future<void> _loadDeviceInfo() async {
    try {
      final deviceId = await AuthService.getDeviceId();
      final model = await AuthService.getDeviceModel();
      
      setState(() {
        _deviceId = deviceId;
        _nameController.text = model;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al obtener info del dispositivo: $e';
        _status = 'error';
      });
    }
  }
  
  Future<void> _requestRegistration() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa un nombre para el dispositivo')),
      );
      return;
    }
    
    setState(() {
      _status = 'requesting';
      _errorMessage = '';
    });
    
    try {
      await AuthService.requestDeviceRegistration(
        deviceName: _nameController.text,
      );
      
      setState(() {
        _status = 'pending';
      });
      
      // Mostrar diálogo de instrucciones
      if (mounted) {
        _showPendingDialog();
      }
    } catch (e) {
      setState(() {
        _status = 'error';
        _errorMessage = 'Error: $e';
      });
    }
  }
  
  Future<void> _checkAuthorization() async {
    setState(() {
      _status = 'authorizing';
      _errorMessage = '';
    });
    
    try {
      await AuthService.authorizeDevice();
      
      setState(() {
        _status = 'authorized';
      });
      
      // Crear sesión automáticamente
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _createSession();
      }
    } catch (e) {
      setState(() {
        _status = 'pending';
        _errorMessage = 'Dispositivo aún no aprobado. Espera la aprobación del administrador.';
      });
    }
  }
  
  Future<void> _createSession() async {
    try {
      await AuthService.createSession();
      
      if (mounted) {
        widget.onRegistrationComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'error';
          _errorMessage = 'Error al crear sesión: $e';
        });
      }
    }
  }
  
  void _showPendingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Solicitud Registrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tu dispositivo ha sido registrado exitosamente.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'El administrador debe aprobar tu solicitud antes de que puedas usar la app.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📱 ID del Dispositivo:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _deviceId,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '⏱️ Comprueba periódicamente si ha sido aprobado.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro del Dispositivo'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _buildContent(),
      ),
    );
  }
  
  Widget _buildContent() {
    switch (_status) {
      case 'input':
        return _buildInputForm();
      case 'requesting':
        return _buildLoadingState('Enviando solicitud...');
      case 'pending':
        return _buildPendingState();
      case 'authorizing':
        return _buildLoadingState('Verificando aprobación...');
      case 'authorized':
        return _buildLoadingState('Creando sesión...');
      case 'error':
        return _buildErrorState();
      default:
        return const SizedBox.shrink();
    }
  }
  
  Widget _buildInputForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          '📱 Configurar Dispositivo',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        const Text(
          'Por favor asigna un nombre identificable para este dispositivo:',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Nombre del dispositivo',
            hintText: 'ej: TPV Principal, Caja 1',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            prefixIcon: const Icon(Icons.devices),
          ),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _requestRegistration,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Solicitar Registro',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildLoadingState(String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          message,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  Widget _buildPendingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            border: Border.all(color: Colors.amber.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.hourglass_top,
                size: 48,
                color: Colors.amber,
              ),
              const SizedBox(height: 16),
              const Text(
                'Solicitud en Espera de Aprobación',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'El administrador debe aprobar tu solicitud. Esto puede tomar unos minutos.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _checkAuthorization,
            icon: const Icon(Icons.refresh),
            label: const Text('Comprobar Aprobación'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () {
            setState(() {
              _status = 'input';
              _nameController.clear();
            });
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Volver'),
        ),
      ],
    );
  }
  
  Widget _buildErrorState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            border: Border.all(color: Colors.red.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _status = 'input';
                _errorMessage = '';
              });
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
