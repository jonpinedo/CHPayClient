package com.example.chpayclient

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Aplicación Flutter básica sin Method Channel
}

        
        // Inicializar gestores de certificados
        certificateManager = CertificateManager(this)
        httpClientManager = HttpClientManager(this)
        
        // Configurar Method Channel para comunicación con Flutter
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installCertificate" -> {
                    val p12Base64 = call.argument<String>("p12_base64") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    
                    if (p12Base64.isEmpty() || password.isEmpty()) {
                        result.error("INVALID_ARGS", "P12 base64 o password vacíos", null)
                        return@setMethodCallHandler
                    }
                    
                    val success = certificateManager.importCertificate(p12Base64, password)
                    
                    if (success) {
                        // Actualizar SSLContext para usar el nuevo certificado
                        httpClientManager.updateSSLContext()
                        android.util.Log.i(TAG, "✅ Certificado instalado y SSLContext actualizado")
                        result.success(true)
                    } else {
                        android.util.Log.e(TAG, "❌ Fallo al instalar certificado")
                        result.success(false)
                    }
                }
                
                "hasCertificate" -> {
                    val hasCert = certificateManager.hasCertificate()
                    android.util.Log.d(TAG, "Verificación de certificado: $hasCert")
                    result.success(hasCert)
                }
                
                "getCertificateInfo" -> {
                    val info = certificateManager.getCertificateInfo()
                    if (info != null) {
                        android.util.Log.i(TAG, "📋 Información del certificado obtenida")
                        result.success(info)
                    } else {
                        android.util.Log.w(TAG, "⚠️ No hay certificado disponible")
                        result.success(null)
                    }
                }
                
                "deleteCertificate" -> {
                    val success = httpClientManager.deleteCertificate()
                    android.util.Log.i(TAG, if (success) "✅ Certificado eliminado" else "❌ Error al eliminar certificado")
                    result.success(success)
                }
                
                "updateSSLContext" -> {
                    httpClientManager.updateSSLContext()
                    val hasContext = httpClientManager.hasSSLContext()
                    android.util.Log.i(TAG, "🔄 SSLContext actualizado: $hasContext")
                    result.success(hasContext)
                }
                
                "httpRequest" -> {
                    val url = call.argument<String>("url") ?: ""
                    val method = call.argument<String>("method") ?: "GET"
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val body = call.argument<String>("body")
                    
                    if (url.isEmpty()) {
                        result.error("INVALID_ARGS", "URL vacía", null)
                        return@setMethodCallHandler
                    }
                    
                    android.util.Log.i(TAG, "🌐 Iniciando petición mTLS: $method $url")
                    
                    Thread {
                        try {
                            val response = httpClientManager.makeRequest(url, method, headers, body)
                            android.util.Log.i(TAG, "✅ Respuesta recibida: ${response["statusCode"]}")
                            runOnUiThread {
                                result.success(response)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e(TAG, "❌ Error en petición mTLS: ${e.message}", e)
                            runOnUiThread {
                                result.error("HTTP_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
