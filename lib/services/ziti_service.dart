import 'dart:convert';
import 'package:flutter/services.dart';

/// Dart wrapper around the Kotlin ZitiManager via MethodChannel.
/// All HTTP traffic to the Ziti overlay goes through this service.
class ZitiService {
  static const _channel = MethodChannel('com.chpayclient/ziti');

  /// Whether a Ziti identity file exists on disk.
  static Future<bool> hasIdentity() async {
    return await _channel.invokeMethod<bool>('hasIdentity') ?? false;
  }

  /// Enroll a new identity using a JWT string (from QR scan).
  static Future<bool> enroll(String jwt) async {
    return await _channel.invokeMethod<bool>('enroll', {'jwt': jwt}) ?? false;
  }

  /// Initialize the Ziti context from the stored identity.
  /// Must be called once at app startup before making HTTP requests.
  static Future<bool> initialize() async {
    return await _channel.invokeMethod<bool>('initialize') ?? false;
  }

  /// Whether the Ziti overlay connection is active.
  static Future<bool> isConnected() async {
    return await _channel.invokeMethod<bool>('isConnected') ?? false;
  }

  /// Get Ziti status info (hasIdentity, isConnected, identityName).
  static Future<Map<String, dynamic>> getStatus() async {
    final result = await _channel.invokeMethod<Map>('getStatus');
    return Map<String, dynamic>.from(result ?? {});
  }

  /// Delete the stored identity (requires re-enrollment).
  static Future<bool> deleteIdentity() async {
    return await _channel.invokeMethod<bool>('deleteIdentity') ?? false;
  }

  // ---------------------------------------------------------------------------
  // HTTP through Ziti overlay
  // ---------------------------------------------------------------------------

  /// Perform a GET request through the Ziti overlay.
  static Future<ZitiResponse> get(String url, {Map<String, String>? headers}) {
    return _httpRequest('GET', url, headers: headers);
  }

  /// Perform a POST request through the Ziti overlay.
  static Future<ZitiResponse> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _httpRequest('POST', url, headers: headers, body: body);
  }

  /// Perform a PUT request through the Ziti overlay.
  static Future<ZitiResponse> put(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _httpRequest('PUT', url, headers: headers, body: body);
  }

  /// Perform a DELETE request through the Ziti overlay.
  static Future<ZitiResponse> delete(String url, {Map<String, String>? headers}) {
    return _httpRequest('DELETE', url, headers: headers);
  }

  /// Internal: route the HTTP request through Kotlin via MethodChannel.
  static Future<ZitiResponse> _httpRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    String? bodyStr;
    if (body != null) {
      bodyStr = body is String ? body : jsonEncode(body);
    }

    final result = await _channel.invokeMethod<Map>('httpRequest', {
      'method': method,
      'url': url,
      'headers': headers ?? <String, String>{},
      'body': bodyStr,
    });

    final map = Map<String, dynamic>.from(result ?? {});
    return ZitiResponse(
      statusCode: map['statusCode'] as int? ?? -1,
      body: map['body'] as String? ?? '',
      headers: Map<String, String>.from(map['headers'] ?? {}),
    );
  }
}

/// Simple response wrapper for HTTP responses coming through Ziti.
class ZitiResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const ZitiResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic> jsonBody() => jsonDecode(body);
}
