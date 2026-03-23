import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'api_service.dart';
import 'ziti_service.dart';

/// Exception with HTTP status code to distinguish auth errors from network errors.
class AuthException implements Exception {
  final String message;
  final int statusCode;
  AuthException(this.message, this.statusCode);

  bool get isAuthError => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class AuthService {
  static final _deviceInfo = DeviceInfoPlugin();
  
  // Storage keys
  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceName = 'device_name';
  static const String _keyPermanentToken = 'permanent_token';
  static const String _keyDeviceStatus = 'device_status';
  
  /// Get or initialize SharedPreferences
  static Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }
  
  /// Get or generate device UUID
  static Future<String> getDeviceId() async {
    try {
      final prefs = await _getPrefs();
      
      // Try to get existing UUID - with explicit type handling
      try {
        final existingId = prefs.getString(_keyDeviceId);
        if (existingId != null && existingId.isNotEmpty) {
          print('✅ UUID del dispositivo recuperado: $existingId');
          return existingId;
        }
      } catch (e) {
        print('⚠️ Could not retrieve existing UUID, generating new one: $e');
        // Continue to generate new UUID
      }
      
      // Generate new UUID if not exists
      const uuid = Uuid();
      final newId = uuid.v4();
      await prefs.setString(_keyDeviceId, newId);
      
      print('🆔 Nuevo UUID del dispositivo generado: $newId');
      return newId;
    } catch (e) {
      print('❌ Error al obtener device ID: $e');
      rethrow;
    }
  }
  
  /// Get stored device name
  static Future<String?> getDeviceName() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_keyDeviceName);
    } catch (e) {
      print('❌ Error al obtener nombre dispositivo: $e');
      return null;
    }
  }
  
  /// Save device name
  static Future<void> setDeviceName(String name) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyDeviceName, name);
      print('✅ Nombre del dispositivo guardado: $name');
    } catch (e) {
      print('❌ Error al guardar nombre dispositivo: $e');
      rethrow;
    }
  }
  
  /// Get device status
  static Future<String> getDeviceStatus() async {
    try {
      final prefs = await _getPrefs();
      String? status = prefs.getString(_keyDeviceStatus);
      return status ?? 'not_registered';
    } catch (e) {
      return 'not_registered';
    }
  }
  
  /// Get stored permanent token
  static Future<String?> getPermanentToken() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_keyPermanentToken);
    } catch (e) {
      print('❌ Error al obtener token permanente: $e');
      return null;
    }
  }
  
  /// Save permanent token
  static Future<void> _savePermanentToken(String token) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyPermanentToken, token);
      print('✅ Token permanente guardado');
    } catch (e) {
      print('❌ Error al guardar token permanente: $e');
      rethrow;
    }
  }
  
  /// Set device status
  static Future<void> _setDeviceStatus(String status) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyDeviceStatus, status);
    } catch (e) {
      print('❌ Error al guardar estado: $e');
    }
  }
  
  /// Get device model name
  static Future<String> getDeviceModel() async {
    try {
      final androidInfo = await _deviceInfo.androidInfo;
      return '${androidInfo.manufacturer} ${androidInfo.model}';
    } catch (e) {
      return 'Android Device';
    }
  }
  
  /// Step 1: Request device registration
  static Future<Map<String, dynamic>> requestDeviceRegistration({
    required String deviceName,
  }) async {
    try {
      final deviceId = await getDeviceId();
      
      print('📝 Solicitando registro del dispositivo...');
      print('   IMEI/UUID: $deviceId');
      print('   Nombre: $deviceName');
      
      final response = await ZitiService.post(
        '${APIService.baseUrl}/api/auth/register-request',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imei': deviceId,
          'nombre': deviceName,
        }),
      );
      
      if (response.statusCode == 200) {
        await setDeviceName(deviceName);
        await _setDeviceStatus('pending');
        print('✅ Solicitud de registro enviada exitosamente');
        return jsonDecode(response.body);
      } else {
        print('❌ Error en solicitud de registro: ${response.statusCode} - ${response.body}');
        String detail = _extractErrorDetail(response.body);
        throw Exception('Error ${response.statusCode}: $detail');
      }
    } catch (e) {
      print('❌ Excepción al solicitar registro: $e');
      rethrow;
    }
  }
  
  /// Step 2: Authorize device after admin approval
  static Future<Map<String, dynamic>> authorizeDevice() async {
    try {
      final deviceId = await getDeviceId();
      final deviceName = await getDeviceName();
      
      if (deviceName == null) {
        throw Exception('Nombre del dispositivo no configurado');
      }
      
      print('🔐 Solicitando autorización del dispositivo...');
      
      final response = await ZitiService.post(
        '${APIService.baseUrl}/api/auth/authorize',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imei': deviceId,
          'nombre': deviceName,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'] as String;
        
        await _savePermanentToken(token);
        await _setDeviceStatus('authorized');
        print('✅ Dispositivo autorizado. Token permanente guardado.');
        return data;
      } else {
        print('❌ Error en autorización: ${response.statusCode} - ${response.body}');
        String detail = _extractErrorDetail(response.body);
        throw Exception('Error ${response.statusCode}: $detail');
      }
    } catch (e) {
      print('❌ Excepción en autorización: $e');
      rethrow;
    }
  }
  
  /// Step 3: Create session and get bearer token
  static Future<String> createSession({int maxRetries = 3}) async {
    int attempt = 0;
    
    while (attempt < maxRetries) {
      try {
        attempt++;
        print('🔄 Creando sesión (intento $attempt/$maxRetries)...');
        
        final deviceId = await getDeviceId();
        final permanentToken = await getPermanentToken();
        
        if (permanentToken == null) {
          throw Exception('Token permanente no disponible');
        }
        
        final response = await ZitiService.post(
          '${APIService.baseUrl}/api/auth/session',
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'imei': deviceId,
            'token': permanentToken,
          }),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final bearer = data['bearer'] as String;
          
          // Save bearer in memory (session-only, no persistence)
          APIService.setSessionBearer(bearer);
          
          await _setDeviceStatus('authorized');
          print('✅ Sesión creada. Bearer de sesión obtenido.');
          return bearer;
        } else if (response.statusCode == 401 && attempt < maxRetries) {
          print('⚠️ Error de autorización, reintentando...');
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        } else {
          print('❌ Error en sesión: ${response.statusCode} - ${response.body}');
          String detail = _extractErrorDetail(response.body);
          throw AuthException('Error ${response.statusCode}: $detail', response.statusCode);
        }
      } catch (e) {
        if (attempt < maxRetries) {
          print('⚠️ Error en sesión (intento $attempt/$maxRetries): $e');
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        } else {
          print('❌ Error final en sesión: $e');
          rethrow;
        }
      }
    }
    
    throw Exception('No se pudo crear sesión después de $maxRetries intentos');
  }
  
  /// Check if device is authorized
  static Future<bool> isAuthorized() async {
    try {
      final status = await getDeviceStatus();
      final token = await getPermanentToken();
      return status == 'authorized' && token != null;
    } catch (e) {
      return false;
    }
  }
  
  /// Extract error detail from response body (JSON "detail" field or raw body)
  static String _extractErrorDetail(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
      return body;
    } catch (_) {
      return body.isNotEmpty ? body : 'Sin detalles';
    }
  }

  /// Clear credentials on logout
  static Future<void> clearCredentials() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_keyPermanentToken);
      await _setDeviceStatus('not_registered');
      APIService.clearSessionBearer();
      print('✅ Credenciales limpiadas');
    } catch (e) {
      print('❌ Error al limpiar credenciales: $e');
    }
  }
}
