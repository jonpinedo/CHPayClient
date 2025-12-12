import 'package:flutter/material.dart';
import '../services/device_service.dart';

class DeviceCertificateRenewalScreen extends StatefulWidget {
  final int? daysToExpiry;
  final VoidCallback onRenewalComplete;

  const DeviceCertificateRenewalScreen({
    Key? key,
    required this.daysToExpiry,
    required this.onRenewalComplete,
  }) : super(key: key);

  @override
  State<DeviceCertificateRenewalScreen> createState() =>
      _DeviceCertificateRenewalScreenState();
}

class _DeviceCertificateRenewalScreenState
    extends State<DeviceCertificateRenewalScreen> {
  bool _renewalInProgress = true;
  bool _renewalSuccess = false;
  String _message = 'Renovando certificado de seguridad...';

  @override
  void initState() {
    super.initState();
    _autoRenew();
  }

  Future<void> _autoRenew() async {
    try {
      print('🔄 Iniciando renovación automática de certificado');
      
      final success = await DeviceService.autoRenewCertificate();

      if (mounted) {
        setState(() {
          _renewalInProgress = false;
          _renewalSuccess = success;
          if (success) {
            _message = 'Certificado renovado correctamente';
          } else {
            _message = 'Error al renovar certificado';
          }
        });

        // Completar después de 2 segundos
        if (success) {
          await Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              widget.onRenewalComplete();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _renewalInProgress = false;
          _renewalSuccess = false;
          _message = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Renovación de Certificado'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_renewalInProgress) ...[
                Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  _message,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (widget.daysToExpiry != null)
                  Text(
                    'Certificado vence en ${widget.daysToExpiry} días',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ] else if (_renewalSuccess) ...[
                Icon(
                  Icons.check_circle,
                  size: 80,
                  color: Colors.green,
                ),
                const SizedBox(height: 24),
                const Text(
                  '¡Renovación completada!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _message,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Cargando aplicación...'),
              ] else ...[
                Icon(
                  Icons.error,
                  size: 80,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Error en la renovación',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _message,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _renewalInProgress = true;
                      _message = 'Renovando certificado de seguridad...';
                    });
                    _autoRenew();
                  },
                  child: const Text('Reintentar'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: widget.onRenewalComplete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                  ),
                  child: const Text('Continuar de todas formas'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
