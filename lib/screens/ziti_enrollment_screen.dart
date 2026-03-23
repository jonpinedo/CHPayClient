import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/ziti_service.dart';

/// Screen for enrolling a Ziti identity by scanning a QR code containing the JWT.
class ZitiEnrollmentScreen extends StatefulWidget {
  final VoidCallback onEnrollmentComplete;

  const ZitiEnrollmentScreen({Key? key, required this.onEnrollmentComplete})
      : super(key: key);

  @override
  State<ZitiEnrollmentScreen> createState() => _ZitiEnrollmentScreenState();
}

class _ZitiEnrollmentScreenState extends State<ZitiEnrollmentScreen> {
  bool _isProcessing = false;
  String? _statusMessage;
  bool _scanComplete = false;
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleQrDetected(String jwt) async {
    if (_isProcessing || _scanComplete) return;

    // Stop scanning immediately to avoid repeated detections
    _scannerController.stop();

    setState(() {
      _isProcessing = true;
      _scanComplete = true;
      _statusMessage = 'Enrollando identidad Ziti...';
    });

    try {
      final success = await ZitiService.enroll(jwt);

      if (!success) {
        setState(() {
          _isProcessing = false;
          _scanComplete = false;
          _statusMessage = 'Error en enrollment. Escanea de nuevo.';
        });
        // Restart scanner after failure
        _scannerController.start();
        return;
      }

      setState(() {
        _statusMessage = 'Conectando al overlay Ziti...';
      });

      final initialized = await ZitiService.initialize();

      if (!initialized) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Identidad guardada pero no se pudo conectar. Reinicia la app.';
        });
        return;
      }

      setState(() {
        _statusMessage = 'Conectado al overlay Ziti';
      });

      await Future.delayed(const Duration(milliseconds: 500));
      widget.onEnrollmentComplete();
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _scanComplete = false;
        _statusMessage = 'Error: $e';
      });
      // Restart scanner after error
      _scannerController.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración Ziti'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.security, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Escanear QR de Identidad',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Escanea el código QR proporcionado por el administrador para conectar este dispositivo a la red segura.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (_isProcessing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_statusMessage ?? '', textAlign: TextAlign.center),
            ] else ...[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isEmpty) return;
                      final jwt = barcodes.first.rawValue;
                      if (jwt != null && jwt.isNotEmpty) {
                        _handleQrDetected(jwt);
                      }
                    },
                  ),
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
