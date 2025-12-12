import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'dart:math';
import 'dart:async';

class NFCService {
  // UID de prueba para emulador/testing (tarjeta de Juan García López)
  static const String uidPrueba = 'ABCDEF1234567890';
  
  // Generar UID aleatorio para testing (para crear nuevas tarjetas en admin)
  static String generarUidAleatorio() {
    final random = Random();
    final bytes = List.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
  }
  
  static Future<String?> leerUID({bool generarAleatorio = false}) async {
    // Si se solicita aleatorio (para crear tarjetas en admin), generar siempre
    if (generarAleatorio) {
      return generarUidAleatorio();
    }
    
    // Verificar si NFC está disponible
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      throw Exception('NFC no disponible en este dispositivo');
    }

    final completer = Completer<String?>();
    
    print('📡 Iniciando lectura NFC... Acerca una tarjeta al lector');
    
    // Iniciar sesión de lectura NFC con nfc_manager 4.x
    await NfcManager.instance.startSession(
      pollingOptions: const {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
        NfcPollingOption.iso18092,
      },
      onDiscovered: (NfcTag tag) async {
        print('🏷️ Etiqueta NFC detectada');
        print('📋 Datos completos del tag: ${tag.data}');
        
        String? uid;
        // Extraer UID usando NfcTagAndroid directamente
        try {
          final androidTag = NfcTagAndroid.from(tag);
          if (androidTag != null && androidTag.id.isNotEmpty) {
            // Convertir bytes a hexadecimal sin separadores (formato backend)
            uid = androidTag.id
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join('')
                .toUpperCase();
            print('✅ UID leído: $uid (${androidTag.id.length} bytes)');
          } else {
            print('⚠️ Tarjeta detectada pero sin ID válido');
            print('androidTag: $androidTag');
            uid = null;
          }
        } catch (e) {
          print('❌ Error al leer UID: $e');
          uid = null;
        }
        
        // Detener sesión
        await NfcManager.instance.stopSession();
        
        // Completar el future con el resultado
        if (!completer.isCompleted) {
          completer.complete(uid);
        }
      },
    );

    return completer.future;
  }
}
