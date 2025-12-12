import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'device_service.dart';

class APIService {
  // Method Channel para peticiones mTLS
  static const platform = MethodChannel('com.chpayclient/certificate');
  
  // Flags de configuración
  static const bool isDebugMode = true; // Cambiar a false en producción
  
  // URL base según modo debug y plataforma
  static String get baseUrl {
    if (isDebugMode) {
      // En desarrollo con HTTPS/mTLS, conectar directamente a WSL2
      // IP de WSL2: 172.26.28.154 (verificar con: wsl hostname -I)
      if (!kIsWeb && Platform.isAndroid) {
        return 'https://172.26.28.154'; // IP directa de WSL2 para mTLS
      }
      return 'https://172.26.28.154'; // IP directa de WSL2
    }
    return 'https://192.168.1.146'; // HTTPS para producción
  }
  
  static const String token = 'xlUBl5-niHn9JZxuRa5uY639I7Qs8eLZi4Wt_Zt4klw'; // Terminal Admin Principal

  // Obtener token de autorización
  static Future<String> getToken() async {
    // Por ahora retorna el token hardcodeado
    // En el futuro, podría obtenerlo de SharedPreferences
    return token;
  }

  // Ignorar errores SSL en desarrollo (certificado self-signed)
  static void configurarSSL() {
    HttpOverrides.global = _DevHttpOverrides();
  }

  static final Map<String, String> headers = {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  /// Hacer petición HTTP con o sin mTLS según disponibilidad de certificado
  static Future<Map<String, dynamic>> _makeRequest({
    required String url,
    required String method,
    Map<String, String>? headers,
    String? body,
  }) async {
    try {
      // Verificar si hay certificado instalado
      final hasCert = await DeviceService.hasCertificateInstalled();
      
      if (hasCert && !kIsWeb && Platform.isAndroid) {
        // Usar petición nativa con mTLS
        print('🔐 [APIService] Usando mTLS nativo para: $method $url');
        
        final response = await platform.invokeMethod('httpRequest', {
          'url': url,
          'method': method,
          'headers': headers ?? {},
          'body': body,
        });
        
        return {
          'statusCode': response['statusCode'],
          'body': response['body'],
          'headers': response['headers'],
        };
      } else {
        // Usar HTTP estándar sin mTLS
        print('📡 [APIService] Usando HTTP estándar para: $method $url');
        
        http.Response httpResponse;
        if (method == 'GET') {
          httpResponse = await http.get(
            Uri.parse(url),
            headers: headers,
          );
        } else if (method == 'POST') {
          httpResponse = await http.post(
            Uri.parse(url),
            headers: headers,
            body: body,
          );
        } else if (method == 'PUT') {
          httpResponse = await http.put(
            Uri.parse(url),
            headers: headers,
            body: body,
          );
        } else {
          throw Exception('Método HTTP no soportado: $method');
        }
        
        return {
          'statusCode': httpResponse.statusCode,
          'body': httpResponse.body,
          'headers': httpResponse.headers,
        };
      }
    } catch (e) {
      print('❌ [APIService] Error en _makeRequest: $e');
      rethrow;
    }
  }

  // Obtener información del dispositivo (roles)
  static Future<Map<String, dynamic>> obtenerInfoDispositivo() async {
    try {
      print('🔍 Intentando conectar a: $baseUrl/api/auth/me');
      
      final response = await _makeRequest(
        url: '$baseUrl/api/auth/me',
        method: 'GET',
        headers: headers,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Timeout: No se pudo conectar al servidor');
        },
      );
      
      final statusCode = response['statusCode'] as int;
      final body = response['body'] as String;
      
      print('✅ Respuesta recibida: $statusCode');
      if (statusCode == 200) {
        return jsonDecode(body);
      } else {
        print('❌ Error HTTP: $statusCode - $body');
        throw Exception('Error: $statusCode');
      }
    } catch (e) {
      print('❌ Excepción al obtener info dispositivo: $e');
      return {'error': e.toString()};
    }
  }

  // Validar tarjeta
  static Future<Map<String, dynamic>> validarTarjeta(String uid) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/tarjetas/validar'),
        headers: headers,
        body: jsonEncode({'uid': uid}),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Hacer pago
  static Future<Map<String, dynamic>> hacerPago(
    String uid,
    double monto,
    String descripcion,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pagos/'),
        headers: headers,
        body: jsonEncode({
          'uid': uid,
          'monto': monto,
          'descripcion': descripcion,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Hacer recarga (igual que pago pero endpoint diferente)
  static Future<Map<String, dynamic>> hacerRecarga(
    String uid,
    double monto,
    String descripcion,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/recargas/'),
        headers: headers,
        body: jsonEncode({
          'uid': uid,
          'monto': monto,
          'descripcion': descripcion,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Consultar historial
  static Future<Map<String, dynamic>> obtenerHistorial(String uid) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/recargas/historial/$uid'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Listar todos los socios (requiere rol ADMIN)
  static Future<List<Map<String, dynamic>>> listarSocios() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/socios'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error al listar socios: $e');
      return [];
    }
  }

  // Crear socio (requiere rol ADMIN)
  // El número de socio ya NO se envía, es generado por el backend
  static Future<Map<String, dynamic>> crearSocio({
    required String nombre,
    String? email,
    String? telefono,
    String saldoInicial = '0.00',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/socios'),
        headers: headers,
        body: jsonEncode({
          'nombre': nombre,
          if (email != null) 'email': email,
          if (telefono != null) 'telefono': telefono,
          'saldo_inicial': saldoInicial,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Asociar tarjeta (requiere rol ADMIN)
  static Future<Map<String, dynamic>> asociarTarjeta({
    required int numeroSocio,
    required String uid,
    String? descripcion,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/tarjetas'),
        headers: headers,
        body: jsonEncode({
          'numero_socio': numeroSocio,
          'uid': uid,
          if (descripcion != null) 'descripcion': descripcion,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Consultar saldo
  static Future<Map<String, dynamic>> consultarSaldo(String uid) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/tarjetas/saldo/$uid'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}

// Clase para ignorar errores SSL en desarrollo
class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    client.connectionTimeout = const Duration(seconds: 10);
    client.idleTimeout = const Duration(seconds: 15);
    return client;
  }
}
