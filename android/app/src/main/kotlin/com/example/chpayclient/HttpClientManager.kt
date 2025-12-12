package com.example.chpayclient

import android.content.Context
import android.util.Log
import java.net.URL
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import javax.net.ssl.HostnameVerifier

class HttpClientManager(private val context: Context) {
    
    companion object {
        private const val TAG = "HttpClientManager"
        private const val DEBUG_MODE = true // Cambiar a false en producción
    }
    
    private val certificateManager = CertificateManager(context)
    private var sslContext: SSLContext? = null
    
    // TrustManager que acepta todos los certificados (solo para desarrollo)
    private val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
        override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
    })
    
    // HostnameVerifier que acepta todos los hostnames (solo para desarrollo)
    private val trustAllHosts = HostnameVerifier { _, _ -> true }
    
    init {
        // Inicializar SSLContext si hay certificado disponible
        updateSSLContext()
    }
    
    /**
     * Actualizar SSLContext con el certificado actual
     * Llamar cuando se instale o renueve un certificado
     */
    fun updateSSLContext() {
        sslContext = certificateManager.getSSLContext()
        if (sslContext != null) {
            Log.i(TAG, "✅ SSLContext actualizado con certificado mTLS")
        } else {
            Log.w(TAG, "⚠️ No hay certificado disponible, SSLContext no configurado")
        }
    }
    
    /**
     * Crear conexión HTTPS con mTLS si hay certificado disponible
     */
    fun createHttpsConnection(urlString: String): HttpsURLConnection? {
        return try {
            val url = URL(urlString)
            val connection = url.openConnection() as HttpsURLConnection
            
            // Aplicar SSLContext si existe (habilita mTLS)
            sslContext?.let {
                connection.sslSocketFactory = it.socketFactory
                Log.d(TAG, "🔐 Conexión HTTPS configurada con mTLS para: $urlString")
            } ?: run {
                Log.d(TAG, "📡 Conexión HTTPS sin mTLS para: $urlString")
            }
            
            // Configuración adicional
            connection.connectTimeout = 10000 // 10 segundos
            connection.readTimeout = 15000    // 15 segundos
            
            connection
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error creando conexión HTTPS: ${e.message}", e)
            null
        }
    }
    
    /**
     * Verificar si el certificado está instalado
     */
    fun hasCertificate(): Boolean {
        return certificateManager.hasCertificate()
    }
    
    /**
     * Obtener información del certificado
     */
    fun getCertificateInfo(): Map<String, String>? {
        return certificateManager.getCertificateInfo()
    }
    
    /**
     * Verificar si SSLContext está configurado
     */
    fun hasSSLContext(): Boolean {
        return sslContext != null
    }
    
    /**
     * Eliminar certificado (para testing o reset)
     */
    fun deleteCertificate(): Boolean {
        val deleted = certificateManager.deleteCertificate()
        if (deleted) {
            sslContext = null
            Log.i(TAG, "🗑️ Certificado eliminado y SSLContext limpiado")
        }
        return deleted
    }
    
    /**
     * Hacer petición HTTP/HTTPS con mTLS
     */
    fun makeRequest(
        urlString: String,
        method: String = "GET",
        headers: Map<String, String> = emptyMap(),
        body: String? = null
    ): Map<String, Any> {
        try {
            val url = URL(urlString)
            val connection = if (urlString.startsWith("https")) {
                (url.openConnection() as HttpsURLConnection).apply {
                    // En modo desarrollo, crear SSLContext que ignore certificados autofirmados
                    // pero mantenga el certificado de cliente para mTLS
                    if (DEBUG_MODE) {
                        val keyManagers = sslContext?.let {
                            // Extraer KeyManagers del SSLContext original (certificado de cliente)
                            val kmf = javax.net.ssl.KeyManagerFactory.getInstance(
                                javax.net.ssl.KeyManagerFactory.getDefaultAlgorithm()
                            )
                            // Usar los mismos KeyManagers que tiene el SSLContext con mTLS
                            certificateManager.getSSLContext()?.let { ctx ->
                                // Obtener KeyStore del certificado
                                val keyStore = certificateManager.loadKeyStore()
                                if (keyStore != null) {
                                    val password = certificateManager.getPassword()
                                    kmf.init(keyStore, password?.toCharArray())
                                    kmf.keyManagers
                                } else null
                            }
                        }
                        
                        val devContext = SSLContext.getInstance("TLS")
                        devContext.init(
                            keyManagers,      // Certificado de cliente para mTLS
                            trustAllCerts,    // Ignorar verificación del servidor
                            java.security.SecureRandom()
                        )
                        sslSocketFactory = devContext.socketFactory
                        hostnameVerifier = trustAllHosts
                        Log.d(TAG, "⚠️ Modo desarrollo: mTLS activo, ignorando certificados autofirmados del servidor")
                    } else if (sslContext != null) {
                        // Producción: usar SSLContext con validación completa
                        sslSocketFactory = sslContext!!.socketFactory
                        Log.d(TAG, "🔐 Usando mTLS en producción para: $urlString")
                    }
                }
            } else {
                url.openConnection() as java.net.HttpURLConnection
            }
            
            // Configurar método HTTP
            connection.requestMethod = method
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            connection.doInput = true
            
            // Agregar headers
            headers.forEach { (key, value) ->
                connection.setRequestProperty(key, value)
            }
            
            // Enviar body si existe (POST, PUT, etc.)
            if (body != null && (method == "POST" || method == "PUT" || method == "PATCH")) {
                connection.doOutput = true
                connection.outputStream.use { os ->
                    os.write(body.toByteArray(Charsets.UTF_8))
                    os.flush()
                }
            }
            
            // Conectar y obtener respuesta
            connection.connect()
            val statusCode = connection.responseCode
            
            // Leer respuesta
            val responseBody = try {
                if (statusCode in 200..299) {
                    connection.inputStream.bufferedReader().use { it.readText() }
                } else {
                    connection.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error leyendo response body: ${e.message}")
                ""
            }
            
            Log.i(TAG, "✅ Respuesta: $statusCode - ${responseBody.take(100)}")
            
            return mapOf(
                "statusCode" to statusCode,
                "body" to responseBody,
                "headers" to connection.headerFields.mapNotNull { (key, value) ->
                    key?.let { it to value.joinToString(", ") }
                }.toMap()
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error en makeRequest: ${e.message}", e)
            throw e
        }
    }
}
