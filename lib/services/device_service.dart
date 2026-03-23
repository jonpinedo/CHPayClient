import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'ziti_service.dart';

class DeviceService {
  static const String _deviceIdKey = 'device_id';
  static const String _deviceNameKey = 'device_name';
  static const String _certificateStatusKey = 'certificate_status';
  static const String _certificateExpiresKey = 'certificate_expires';
  static const String _p12FileNameKey = 'device_certificate.p12';
  
  // Method Channel para comunicación con Kotlin
  static const platform = MethodChannel('com.chpayclient/certificate');

  /// Obtener información almacenada del dispositivo
  static Future<Map<String, dynamic>?> getDeviceInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getInt(_deviceIdKey);
    
    if (deviceId == null) return null;

    return {
      'device_id': deviceId,
      'device_name': prefs.getString(_deviceNameKey) ?? 'Unknown',
      'certificate_status': prefs.getString(_certificateStatusKey) ?? 'NONE',
      'certificate_expires': prefs.getString(_certificateExpiresKey),
    };
  }

  /// Registrar nuevo dispositivo
  static Future<Map<String, dynamic>> registerDevice(String deviceName) async {
    try {
      final url = '${APIService.baseUrl}/api/auth/register-device';
      final token = await APIService.getToken();
      
      print('🔍 [DeviceService] Registrando dispositivo: $deviceName');
      print('🔍 [DeviceService] URL: $url');
      print('🔍 [DeviceService] Token: ${token.substring(0, 10)}...');
      
      final response = await ZitiService.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'device_name': deviceName,
        }),
      );

      print('✅ [DeviceService] Respuesta: ${response.statusCode}');
      print('📦 [DeviceService] Body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        
        await prefs.setInt(_deviceIdKey, data['dispositivo_id']);
        await prefs.setString(_deviceNameKey, deviceName);
        await prefs.setString(_certificateStatusKey, 'REGISTRADO');

        return {
          'success': true,
          'device_id': data['dispositivo_id'],
          'message': data['mensaje'] ?? 'Dispositivo registrado',
        };
      } else {
        print('⚠️ [DeviceService] Error HTTP: ${response.statusCode}');
        try {
          final error = jsonDecode(response.body);
          print('📦 [DeviceService] Error body: $error');
          
          // Manejar diferentes formatos de error
          String errorMessage;
          if (error['detail'] != null) {
            final detail = error['detail'];
            if (detail is List) {
              // Formato FastAPI de errores de validación
              errorMessage = detail.map((e) => e['msg'] ?? e.toString()).join(', ');
            } else {
              errorMessage = detail.toString();
            }
          } else {
            errorMessage = 'Error al registrar dispositivo (${response.statusCode})';
          }
          
          return {
            'success': false,
            'error': errorMessage,
          };
        } catch (e) {
          print('❌ [DeviceService] Error parseando respuesta de error: $e');
          return {
            'success': false,
            'error': 'Error del servidor: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      print('❌ [DeviceService] Excepción: $e');
      return {
        'success': false,
        'error': 'Error de conexión: $e',
      };
    }
  }

  /// Verificar estado del dispositivo y certificado
  static Future<Map<String, dynamic>> checkDeviceStatus() async {
    final info = await getDeviceInfo();
    
    if (info == null) {
      return {
        'status': 'not_registered',
        'device_id': null,
      };
    }

    try {
      final deviceId = info['device_id'];
      final response = await ZitiService.get(
        '${APIService.baseUrl}/api/auth/device-status/$deviceId',
        headers: {
          'Authorization': 'Bearer ${await APIService.getToken()}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        
        // Actualizar estado en almacenamiento
        await prefs.setString(_certificateStatusKey, data['estado_certificado']);
        if (data['certificado_expira'] != null) {
          await prefs.setString(_certificateExpiresKey, data['certificado_expira']);
        }

        // Calcular días hasta expiración
        int? daysToExpiry;
        if (data['certificado_expira'] != null) {
          final expiryDate = DateTime.parse(data['certificado_expira']);
          daysToExpiry = expiryDate.difference(DateTime.now()).inDays;
        }

        return {
          'status': data['estado_certificado'].toLowerCase(),
          'device_id': deviceId,
          'device_name': info['device_name'],
          'puede_descargar': data['puede_descargar'] ?? false,
          'certificado_expira': data['certificado_expira'],
          'dias_para_expiry': daysToExpiry,
          'necesita_renovacion': data['necesita_renovacion'] ?? false,
        };
      } else if (response.statusCode == 404) {
        // Dispositivo no encontrado, limpiar
        await _clearDeviceInfo();
        return {
          'status': 'not_registered',
          'device_id': null,
        };
      } else {
        return {
          'status': 'error',
          'error': 'Error al verificar estado',
        };
      }
    } catch (e) {
      return {
        'status': 'error',
        'error': 'Error de conexión: $e',
      };
    }
  }

  /// Descargar certificado P12
  static Future<Map<String, dynamic>> downloadCertificate() async {
    final info = await getDeviceInfo();
    
    if (info == null) {
      print('❌ [DeviceService] downloadCertificate: Dispositivo no registrado');
      return {
        'success': false,
        'error': 'Dispositivo no registrado',
      };
    }

    try {
      final deviceId = info['device_id'];
      final token = await APIService.getToken();
      final url = '${APIService.baseUrl}/api/auth/download-certificate/$deviceId';
      
      print('🔍 [DeviceService] Descargando certificado para dispositivo: $deviceId');
      print('🔍 [DeviceService] URL: $url');
      print('🔍 [DeviceService] Token: ${token.substring(0, 10)}...');
      
      final response = await ZitiService.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      print('✅ [DeviceService] Respuesta descarga: ${response.statusCode}');
      print('📦 [DeviceService] Body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ [DeviceService] Certificado descargado exitosamente');
        return {
          'success': true,
          'p12_base64': data['p12_base64'],
          'p12_password': data['p12_password'],
          'certificado_cn': data['certificado_cn'],
          'certificado_serial': data['certificado_serial'],
          'emitido_en': data['emitido_en'],
          'expira_en': data['expira_en'],
        };
      } else {
        print('⚠️ [DeviceService] Error HTTP: ${response.statusCode}');
        print('📦 [DeviceService] Response body: ${response.body}');
        
        try {
          final error = jsonDecode(response.body);
          final detail = error['detail'];
          String errorMessage;
          
          if (detail is List) {
            errorMessage = detail.map((e) => e['msg'] ?? e.toString()).join(', ');
          } else {
            errorMessage = detail?.toString() ?? 'Error al descargar certificado';
          }
          
          return {
            'success': false,
            'error': errorMessage,
          };
        } catch (e) {
          return {
            'success': false,
            'error': 'Error del servidor: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      print('❌ [DeviceService] Excepción al descargar certificado: $e');
      return {
        'success': false,
        'error': 'Error de conexión: $e',
      };
    }
  }

  /// Instalar certificado P12 en el dispositivo
  /// Retorna true si la instalación fue exitosa
  static Future<bool> installCertificate(String p12Base64, String password) async {
    try {
      print('📦 Instalando certificado vía Method Channel...');
      
      // Llamar al método nativo de Android/iOS
      final bool success = await platform.invokeMethod<bool>(
        'installCertificate',
        {
          'p12_base64': p12Base64,
          'password': password,
        },
      ) ?? false;
      
      if (success) {
        print('✅ Certificado instalado en KeyStore');
        
        // Actualizar estado en SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_certificateStatusKey, 'CERTIFICADO');
        
        return true;
      } else {
        print('❌ Fallo al instalar certificado en KeyStore');
        return false;
      }
    } catch (e) {
      print('❌ Error al instalar certificado: $e');
      return false;
    }
  }
  
  /// Verificar si hay certificado instalado en KeyStore
  static Future<bool> hasCertificateInstalled() async {
    try {
      final bool hasCert = await platform.invokeMethod<bool>('hasCertificate') ?? false;
      return hasCert;
    } catch (e) {
      print('❌ Error verificando certificado: $e');
      return false;
    }
  }
  
  /// Obtener información del certificado instalado
  static Future<Map<String, String>?> getCertificateInfo() async {
    try {
      final Map<dynamic, dynamic>? info = await platform.invokeMapMethod('getCertificateInfo');
      
      if (info == null) return null;
      
      return Map<String, String>.from(info);
    } catch (e) {
      print('❌ Error obteniendo información del certificado: $e');
      return null;
    }
  }

  /// Verificar si necesita renovación
  static Future<bool> needsRenewal() async {
    final status = await checkDeviceStatus();
    
    if (status['dias_para_expiry'] == null) return false;
    
    return status['dias_para_expiry'] < 30;
  }

  /// Renovar certificado automáticamente
  static Future<bool> autoRenewCertificate() async {
    try {
      // Descargar nuevo certificado
      final certData = await downloadCertificate();
      
      if (!certData['success']) {
        print('❌ Error al descargar certificado: ${certData['error']}');
        return false;
      }

      // Instalar nuevo certificado
      final installed = await installCertificate(
        certData['p12_base64'],
        certData['p12_password'],
      );

      if (installed) {
        print('✅ Certificado renovado automáticamente');
        return true;
      } else {
        print('❌ Error al instalar certificado renovado');
        return false;
      }
    } catch (e) {
      print('❌ Error en renovación automática: $e');
      return false;
    }
  }

  /// Limpiar información del dispositivo
  static Future<void> _clearDeviceInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_deviceNameKey);
    await prefs.remove(_certificateStatusKey);
    await prefs.remove(_certificateExpiresKey);
  }

  /// Eliminar dispositivo (para testing)
  static Future<void> clearDevice() async {
    await _clearDeviceInfo();
  }
}
