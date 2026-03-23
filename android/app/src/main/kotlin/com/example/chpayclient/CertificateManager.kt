package com.example.chpayclient

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import java.io.ByteArrayInputStream
import java.io.File
import java.security.KeyStore
import java.security.cert.X509Certificate
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory

class CertificateManager(private val context: Context) {
    
    companion object {
        private const val TAG = "CertificateManager"
        private const val KEYSTORE_TYPE = "PKCS12"
        private const val CERT_FILENAME = "device.p12"
        private const val PREFS_NAME = "certificates"
        private const val KEY_PASSWORD = "device_p12_password"
    }
    
    /**
     * Importar certificado P12 (base64 decodificado) en almacenamiento del dispositivo
     */
    fun importCertificate(p12Base64: String, password: String): Boolean {
        return try {
            Log.i(TAG, "📦 Iniciando importación de certificado...")
            
            // Decodificar base64 a bytes
            val p12Bytes = Base64.decode(p12Base64, Base64.DEFAULT)
            Log.i(TAG, "✅ Base64 decodificado: ${p12Bytes.size} bytes")
            
            // Verificar que es un KeyStore PKCS12 válido
            val keyStore = KeyStore.getInstance(KEYSTORE_TYPE)
            keyStore.load(ByteArrayInputStream(p12Bytes), password.toCharArray())
            Log.i(TAG, "✅ KeyStore PKCS12 validado correctamente")
            
            // Guardar en almacenamiento del app
            val certificateFile = File(context.filesDir, CERT_FILENAME)
            certificateFile.writeBytes(p12Bytes)
            Log.i(TAG, "✅ Certificado guardado en: ${certificateFile.absolutePath}")
            
            // Guardar contraseña en SharedPreferences
            // NOTA: En producción, usar EncryptedSharedPreferences
            savePasswordSecurely(password)
            Log.i(TAG, "✅ Contraseña guardada")
            
            Log.i(TAG, "🎉 Certificado importado correctamente")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error al importar certificado: ${e.message}", e)
            false
        }
    }
    
    /**
     * Obtener SSLContext configurado con el certificado cliente
     */
    fun getSSLContext(): SSLContext? {
        return try {
            val certificateFile = File(context.filesDir, CERT_FILENAME)
            
            if (!certificateFile.exists()) {
                Log.w(TAG, "⚠️ Certificado no encontrado en ${certificateFile.absolutePath}")
                return null
            }
            
            // Recuperar contraseña
            val password = getPasswordSecurely()
            if (password == null) {
                Log.w(TAG, "⚠️ Contraseña del certificado no encontrada")
                return null
            }
            
            Log.i(TAG, "🔑 Cargando certificado desde archivo...")
            
            // Crear KeyStore desde el archivo P12
            val keyStore = KeyStore.getInstance(KEYSTORE_TYPE)
            keyStore.load(certificateFile.inputStream(), password.toCharArray())
            
            // Crear KeyManagerFactory para mTLS (certificado cliente)
            val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
            kmf.init(keyStore, password.toCharArray())
            
            // Crear TrustManagerFactory (aceptar certificados del servidor)
            // Usando el almacén del sistema para confiar en CAs conocidas
            val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
            tmf.init(null as KeyStore?)
            
            // Crear SSLContext
            val sslContext = SSLContext.getInstance("TLSv1.2")
            sslContext.init(
                kmf.keyManagers,
                tmf.trustManagers,
                java.security.SecureRandom()
            )
            
            Log.i(TAG, "✅ SSLContext configurado con mTLS")
            sslContext
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error al obtener SSLContext: ${e.message}", e)
            null
        }
    }
    
    /**
     * Verificar si hay certificado instalado
     */
    fun hasCertificate(): Boolean {
        val certificateFile = File(context.filesDir, CERT_FILENAME)
        val hasFile = certificateFile.exists()
        val hasPassword = getPasswordSecurely() != null
        
        Log.d(TAG, "Verificación certificado: archivo=$hasFile, password=$hasPassword")
        return hasFile && hasPassword
    }
    
    /**
     * Cargar KeyStore desde el archivo P12
     */
    fun loadKeyStore(): KeyStore? {
        return try {
            val certificateFile = File(context.filesDir, CERT_FILENAME)
            
            if (!certificateFile.exists()) {
                Log.w(TAG, "⚠️ Certificado no encontrado")
                return null
            }
            
            val password = getPasswordSecurely()
            if (password == null) {
                Log.w(TAG, "⚠️ Contraseña no encontrada")
                return null
            }
            
            val keyStore = KeyStore.getInstance(KEYSTORE_TYPE)
            keyStore.load(certificateFile.inputStream(), password.toCharArray())
            keyStore
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error al cargar KeyStore: ${e.message}", e)
            null
        }
    }
    
    /**
     * Obtener contraseña del certificado
     */
    fun getPassword(): String? {
        return getPasswordSecurely()
    }
    
    /**
     * Obtener información del certificado (CN, serial, fechas)
     */
    fun getCertificateInfo(): Map<String, String>? {
        return try {
            val certificateFile = File(context.filesDir, CERT_FILENAME)
            if (!certificateFile.exists()) {
                Log.w(TAG, "⚠️ No hay certificado para obtener información")
                return null
            }
            
            val password = getPasswordSecurely() ?: return null
            
            val keyStore = KeyStore.getInstance(KEYSTORE_TYPE)
            keyStore.load(certificateFile.inputStream(), password.toCharArray())
            
            // Obtener el primer alias
            val aliases = keyStore.aliases()
            if (!aliases.hasMoreElements()) {
                Log.w(TAG, "⚠️ KeyStore no contiene aliases")
                return null
            }
            
            val alias = aliases.nextElement() as String
            val cert = keyStore.getCertificate(alias) as? X509Certificate
            
            if (cert == null) {
                Log.w(TAG, "⚠️ No se pudo obtener certificado X509")
                return null
            }
            
            // Extraer CN del Subject DN
            val subjectDN = cert.subjectDN.toString()
            val cn = subjectDN.split("CN=").getOrNull(1)?.split(",")?.get(0) ?: "Unknown"
            
            val info = mapOf(
                "CN" to cn,
                "Serial" to cert.serialNumber.toString(),
                "Subject" to cert.subjectDN.toString(),
                "Issuer" to cert.issuerDN.toString(),
                "NotBefore" to cert.notBefore.toString(),
                "NotAfter" to cert.notAfter.toString(),
            )
            
            Log.i(TAG, "📋 Información del certificado: CN=$cn, Serial=${cert.serialNumber}")
            info
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error al obtener información del certificado: ${e.message}", e)
            null
        }
    }
    
    /**
     * Eliminar certificado almacenado
     */
    fun deleteCertificate(): Boolean {
        return try {
            val certificateFile = File(context.filesDir, CERT_FILENAME)
            
            if (certificateFile.exists()) {
                certificateFile.delete()
                Log.i(TAG, "🗑️ Archivo de certificado eliminado")
            }
            
            clearPasswordSecurely()
            Log.i(TAG, "✅ Certificado eliminado completamente")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error al eliminar certificado: ${e.message}", e)
            false
        }
    }
    
    // --- PRIVATE METHODS ---
    
    private fun getPreferences(): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    
    private fun savePasswordSecurely(password: String) {
        try {
            val prefs = getPreferences()
            // TODO: En producción, usar EncryptedSharedPreferences de androidx.security
            prefs.edit().putString(KEY_PASSWORD, password).apply()
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error guardando contraseña: ${e.message}", e)
        }
    }
    
    private fun getPasswordSecurely(): String? {
        return try {
            val prefs = getPreferences()
            prefs.getString(KEY_PASSWORD, null)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error recuperando contraseña: ${e.message}", e)
            null
        }
    }
    
    private fun clearPasswordSecurely() {
        try {
            val prefs = getPreferences()
            prefs.edit().remove(KEY_PASSWORD).apply()
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error al limpiar contraseña: ${e.message}", e)
        }
    }
}
