import 'dart:async';
import 'package:flutter/material.dart';
import '../services/device_service.dart';

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
  String _status = 'loading'; // loading, not_registered, registrado, aprobado, certificado
  Map<String, dynamic> _deviceInfo = {};
  bool _isLoading = false;
  String _deviceName = '';
  final TextEditingController _deviceNameController = TextEditingController();
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _checkDeviceStatus();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _checkDeviceStatus() async {
    final status = await DeviceService.checkDeviceStatus();
    
    setState(() {
      _status = status['status'];
      _deviceInfo = status;
    });

    // Si está registrado pero no aprobado, empezar a verificar periódicamente
    if (_status == 'registrado') {
      _startPolling();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final status = await DeviceService.checkDeviceStatus();
      
      setState(() {
        _status = status['status'];
        _deviceInfo = status;
      });

      // Si ya fue aprobado, detener polling
      if (_status == 'aprobado') {
        _pollingTimer?.cancel();
      }
    });
  }

  Future<void> _registerDevice() async {
    if (_deviceNameController.text.isEmpty) {
      _showError('Por favor ingresa un nombre para el dispositivo');
      return;
    }

    print('🔔 [RegistrationScreen] Iniciando registro: ${_deviceNameController.text}');
    setState(() => _isLoading = true);

    final result = await DeviceService.registerDevice(_deviceNameController.text);

    print('📬 [RegistrationScreen] Resultado: $result');
    setState(() => _isLoading = false);

    if (result['success']) {
      print('✅ [RegistrationScreen] Registro exitoso');
      setState(() {
        _status = 'registrado';
        _deviceInfo = result;
      });
      _startPolling();
      _showSuccess('Dispositivo registrado. Esperando aprobación...');
    } else {
      print('❌ [RegistrationScreen] Error: ${result['error']}');
      final error = result['error'];
      final errorMessage = error is List ? error.join(', ') : error.toString();
      _showError(errorMessage);
    }
  }

  Future<void> _installCertificate() async {
    setState(() => _isLoading = true);

    final certData = await DeviceService.downloadCertificate();

    if (!certData['success']) {
      setState(() => _isLoading = false);
      _showError(certData['error']);
      return;
    }

    final installed = await DeviceService.installCertificate(
      certData['p12_base64'],
      certData['p12_password'],
    );

    setState(() => _isLoading = false);

    if (installed) {
      _showSuccess(
        'Certificado instalado correctamente.\n'
        'Debes importarlo en Ajustes > Seguridad > Credenciales',
      );
      setState(() => _status = 'certificado');
      
      // Completar registro después de 2 segundos
      Future.delayed(const Duration(seconds: 2), () {
        widget.onRegistrationComplete();
      });
    } else {
      _showError('Error al instalar certificado');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de Dispositivo')),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_status) {
      case 'loading':
        return const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verificando estado del dispositivo...'),
          ],
        );

      case 'not_registered':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices, size: 80, color: Colors.orange.shade700),
            const SizedBox(height: 24),
            const Text(
              'Dispositivo no registrado',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Para usar esta aplicación, debe registrar el dispositivo.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _deviceNameController,
              decoration: InputDecoration(
                hintText: 'Ej: TPV-Caja-01',
                labelText: 'Nombre del dispositivo',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _registerDevice,
                icon: const Icon(Icons.app_registration),
                label: _isLoading
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )
                    : const Text('Registrar Dispositivo'),
              ),
            ),
          ],
        );

      case 'registrado':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 80, color: Colors.amber),
            const SizedBox(height: 24),
            const Text(
              'Pendiente de aprobación',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'El dispositivo ha sido registrado.\n'
              'Esperando aprobación del administrador...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Verificando cada 5 segundos...'),
          ],
        );

      case 'aprobado':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            const Text(
              '¡Aprobado!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Tu dispositivo ha sido aprobado.\n'
              'Ahora instala el certificado para completar el registro.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _installCertificate,
                icon: const Icon(Icons.security),
                label: _isLoading
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )
                    : const Text('Instalar Certificado'),
              ),
            ),
          ],
        );

      case 'certificado':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            const Text(
              '¡Listo!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'El dispositivo está completamente configurado.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Inicializando aplicación...'),
          ],
        );

      default:
        return const Center(child: Text('Estado desconocido'));
    }
  }
}
