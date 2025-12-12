import 'package:http/http.dart' as http;
import 'dart:convert';

class APIService {
  // Flags de configuración
  static const bool isDebugMode = true; // Cambiar a false en producción
  
  // URL base según modo debug
  static String get baseUrl {
    if (isDebugMode) {
      // En desarrollo, usar IP de Windows que redirige a WSL2
      return 'http://192.168.1.146';
    }
    return 'http://192.168.1.146'; // Producción
  }
  
  static const String token = 'xlUBl5-niHn9JZxuRa5uY639I7Qs8eLZi4Wt_Zt4klw'; // Terminal Admin Principal

  // Obtener token de autorización
  static Future<String> getToken() async {
    // Por ahora retorna el token hardcodeado
    // En el futuro, podría obtenerlo de SharedPreferences
    return token;
  }

  static final Map<String, String> headers = {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };


  // Obtener información del dispositivo (roles)
  static Future<Map<String, dynamic>> obtenerInfoDispositivo() async {
    try {
      print('🔍 Intentando conectar a: $baseUrl/api/auth/me');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: headers,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Timeout: No se pudo conectar al servidor');
        },
      );
      
      print('✅ Respuesta recibida: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('❌ Error HTTP: ${response.statusCode} - ${response.body}');
        throw Exception('Error: ${response.statusCode}');
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
