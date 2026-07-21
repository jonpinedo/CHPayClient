import 'dart:convert';
import 'dart:typed_data';
import 'ziti_service.dart';

class APIService {
  // All traffic goes through the Ziti overlay to chpay-api.private
  static const String baseUrl = 'http://chpay-api.private';
  
  // Debug mode flag for UI elements
  static bool isDebugMode = false;
  
  // Bearer de sesión actual (se obtiene en cada inicio de app)
  static String? _sessionBearer;
  
  // Token hardcodeado para admin (solo para testing)
  static const String _adminToken = 'xlUBl5-niHn9JZxuRa5uY639I7Qs8eLZi4Wt_Zt4klw';
  
  /// Obtener token actual (para DeviceService, etc.)
  static Future<String> getToken() async {
    return _sessionBearer ?? _adminToken;
  }
  
  /// Establecer bearer de sesión
  static void setSessionBearer(String bearer) {
    _sessionBearer = bearer;
    print('🔐 Bearer de sesión actualizado');
  }
  
  /// Limpiar bearer de sesión
  static void clearSessionBearer() {
    _sessionBearer = null;
    print('🔐 Bearer de sesión limpiado');
  }
  
  /// Obtener headers con autorización actual
  static Map<String, String> get headers {
    final auth = _sessionBearer != null 
      ? 'Bearer $_sessionBearer'
      : 'Bearer $_adminToken';
    
    return {
      'Authorization': auth,
      'Content-Type': 'application/json',
    };
  }
  
  /// Headers solo para endpoints públicos (sin autenticación)
  static final Map<String, String> publicHeaders = {
    'Content-Type': 'application/json',
  };


  // Obtener información del dispositivo (roles + seguridad recarga)
  static Future<Map<String, dynamic>> obtenerInfoDispositivo() async {
    try {
      print('🔍 Intentando conectar a: $baseUrl/api/auth/me');
      
      final response = await ZitiService.get(
        '$baseUrl/api/auth/me',
        headers: headers,
      );
      
      print('✅ Respuesta recibida: ${response.statusCode}');
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        // Compatibilidad API vieja: si no viene, tratar como false
        data['exigir_identificacion_recarga'] =
            data['exigir_identificacion_recarga'] == true;
        data['seguridad_recarga'] =
            (data['seguridad_recarga'] as String?)?.toLowerCase() ?? 'desactivada';
        return data;
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
      final response = await ZitiService.post(
        '$baseUrl/api/tarjetas/validar',
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
      final response = await ZitiService.post(
        '$baseUrl/api/pagos/',
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

  // Hacer recarga. Pasar solo pin o uidOperador (nunca ambos).
  // Null/vacío = body legacy sin identificación.
  static Future<Map<String, dynamic>> hacerRecarga(
    String uid,
    double monto,
    String descripcion, {
    String? pin,
    String? uidOperador,
  }) async {
    try {
      final body = <String, dynamic>{
        'uid': uid,
        'monto': monto,
        'descripcion': descripcion,
      };
      if (pin != null && pin.isNotEmpty) {
        body['pin'] = pin;
      }
      if (uidOperador != null && uidOperador.isNotEmpty) {
        body['uid_operador'] = uidOperador;
      }

      final response = await ZitiService.post(
        '$baseUrl/api/recargas/',
        headers: headers,
        body: jsonEncode(body),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      final parsed = _parseErrorDetail(response.body);
      return {
        'error': parsed['mensaje'] ?? 'Error: ${response.statusCode}',
        'codigo': parsed['codigo'],
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Parseo tolerante de detail: string legacy o {codigo, mensaje}.
  static Map<String, String?> _parseErrorDetail(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map) {
        return {'mensaje': body, 'codigo': null};
      }
      final detail = data['detail'];
      if (detail is Map) {
        return {
          'codigo': detail['codigo']?.toString(),
          'mensaje': detail['mensaje']?.toString() ?? detail.toString(),
        };
      }
      if (detail != null) {
        return {'mensaje': detail.toString(), 'codigo': null};
      }
      return {'mensaje': body, 'codigo': null};
    } catch (_) {
      return {
        'mensaje': body.isNotEmpty ? body : 'Sin detalles',
        'codigo': null,
      };
    }
  }

  // Consultar historial
  static Future<Map<String, dynamic>> obtenerHistorial(String uid) async {
    try {
      final response = await ZitiService.get(
        '$baseUrl/api/recargas/historial/$uid',
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

  // Listar socios (requiere rol ADMIN).
  // Con sinTarjeta=true solo los que aún no tienen tarjeta NFC.
  static Future<List<Map<String, dynamic>>> listarSocios({
    bool sinTarjeta = false,
  }) async {
    try {
      final uri = sinTarjeta
          ? '$baseUrl/api/admin/socios?sin_tarjeta=true'
          : '$baseUrl/api/admin/socios';
      final response = await ZitiService.get(
        uri,
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
  static Future<Map<String, dynamic>> crearSocio({
    required String nombre,
    String? email,
    String? telefono,
    String saldoInicial = '0.00',
  }) async {
    try {
      final response = await ZitiService.post(
        '$baseUrl/api/admin/socios',
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
      final response = await ZitiService.post(
        '$baseUrl/api/admin/tarjetas',
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
      final response = await ZitiService.get(
        '$baseUrl/api/tarjetas/saldo/$uid',
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

  // ── Capítulos (Multi-tenancy) ───────────────────────────────────────────────

  /// Obtener lista de capítulos activos (endpoint público, sin auth)
  static Future<List<Map<String, dynamic>>> obtenerCapitulos() async {
    try {
      final response = await ZitiService.get(
        '$baseUrl/api/capitulos/',
        headers: publicHeaders,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error al obtener capítulos: $e');
      rethrow;
    }
  }

  /// Obtener logo de un capítulo (endpoint público, devuelve bytes de imagen)
  /// Retorna null si el capítulo no tiene logo (404).
  static Future<Uint8List?> obtenerLogoCapitulo(int capituloId) async {
    try {
      final response = await ZitiService.get(
        '$baseUrl/api/capitulos/$capituloId/logo',
        headers: publicHeaders,
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('⚠️ Error al obtener logo del capítulo $capituloId: $e');
      return null;
    }
  }
}
