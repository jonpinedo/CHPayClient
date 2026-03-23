package com.example.chpayclient

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.openziti.Ziti
import org.openziti.ZitiContext
import org.openziti.android.Ziti as ZitiAndroid
import java.io.IOException
import java.security.KeyStore
import java.util.concurrent.TimeUnit

/**
 * Manages the OpenZiti SDK lifecycle: enrollment, identity loading, and HTTP requests through the overlay.
 * Uses ziti-android which stores identities in AndroidKeyStore.
 */
class ZitiManager(private val context: Context) {

    companion object {
        private const val TAG = "ZitiManager"
    }

    private var zitiContext: ZitiContext? = null
    private var httpClient: OkHttpClient? = null
    private var initialized = false

    /**
     * Check if a Ziti identity exists in the AndroidKeyStore.
     */
    fun hasIdentity(): Boolean {
        return try {
            val ks = KeyStore.getInstance("AndroidKeyStore")
            ks.load(null)
            ks.aliases().toList().any { it.startsWith("ziti://") }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking identity: ${e.message}", e)
            false
        }
    }

    /**
     * Enroll a new identity using the JWT string (e.g. scanned from QR).
     * The identity is stored in AndroidKeyStore by the SDK.
     * Returns true on success.
     */
    suspend fun enroll(jwt: String): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.i(TAG, "Starting Ziti enrollment...")

            // Ensure Ziti Android is initialized first
            if (!initialized) {
                ZitiAndroid.init(context, false)
                initialized = true
            }

            val ks = KeyStore.getInstance("AndroidKeyStore")
            ks.load(null)

            // Enroll — stores the identity in AndroidKeyStore
            val ctx = Ziti.enroll(ks, jwt.toByteArray(), "ziti-sdk")
            Log.i(TAG, "Enrollment succeeded — identity: ${ctx.name()}")

            zitiContext = ctx
            buildHttpClient()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Enrollment failed: ${e.message}", e)
            false
        }
    }

    /**
     * Initialize ZitiContext from the AndroidKeyStore.
     * Must be called before making HTTP requests.
     */
    suspend fun initialize(): Boolean = withContext(Dispatchers.IO) {
        try {
            if (!hasIdentity()) {
                Log.w(TAG, "No identity found in KeyStore — cannot initialize")
                return@withContext false
            }

            Log.i(TAG, "Initializing Ziti context...")

            // Initialize Ziti for Android (loads identities from AndroidKeyStore)
            ZitiAndroid.init(context, false)
            initialized = true

            // Wait briefly for contexts to load
            delay(2000)

            // Grab the first context
            val contexts = Ziti.getContexts()
            if (contexts.isEmpty()) {
                Log.e(TAG, "No ZitiContext available after init")
                return@withContext false
            }

            zitiContext = contexts.first()
            Log.i(TAG, "ZitiContext ready — identity: ${zitiContext?.name()}")
            Log.i(TAG, "ZitiContext status: ${zitiContext?.getStatus()}")
            Log.i(TAG, "ZitiContext controller: ${zitiContext?.controller()}")

            // Check for fatal statuses that require re-enrollment
            val initialStatus = zitiContext?.getStatus()?.toString() ?: ""
            if (initialStatus.contains("NotAuthorized", ignoreCase = true) ||
                initialStatus.contains("Disabled", ignoreCase = true)) {
                Log.e(TAG, "Identity rejected by controller (status=$initialStatus) — re-enrollment needed")
                return@withContext false
            }

            // Wait for services to be available (edge router connection)
            var retries = 0
            val maxRetries = 30
            while (retries < maxRetries) {
                val status = zitiContext?.getStatus()
                val statusStr = status?.toString() ?: ""

                // Abort early if identity becomes rejected
                if (statusStr.contains("NotAuthorized", ignoreCase = true) ||
                    statusStr.contains("Disabled", ignoreCase = true)) {
                    Log.e(TAG, "Identity rejected during wait (status=$statusStr) — re-enrollment needed")
                    return@withContext false
                }

                val resolved = Ziti.getDNSResolver().resolve("chpay-api.private")
                if (resolved != null) {
                    Log.i(TAG, "Service chpay-api.private resolved to $resolved after ${retries + 1} attempts")
                    break
                }
                retries++
                if (retries % 5 == 0) {
                    Log.i(TAG, "Waiting for services... attempt $retries/$maxRetries (status=$status)")
                } else {
                    Log.d(TAG, "Waiting for services... attempt $retries/$maxRetries (status=$status)")
                }
                delay(1000)
            }
            if (retries == maxRetries) {
                Log.w(TAG, "Services not yet available after $maxRetries seconds")
                return@withContext false
            }

            buildHttpClient()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Initialization failed: ${e.message}", e)
            false
        }
    }

    private fun buildHttpClient() {
        val zitiDns = Ziti.getDNSResolver()
        val okHttpDns = object : Dns {
            override fun lookup(hostname: String): List<java.net.InetAddress> {
                val resolved = zitiDns.resolve(hostname)
                return if (resolved != null) listOf(resolved) else Dns.SYSTEM.lookup(hostname)
            }
        }

        httpClient = OkHttpClient.Builder()
            .socketFactory(Ziti.getSocketFactory())
            .dns(okHttpDns)
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()

        Log.i(TAG, "OkHttpClient with Ziti socket factory ready")
    }

    /**
     * Check whether the Ziti context is connected to the overlay.
     */
    fun isConnected(): Boolean {
        return zitiContext != null && httpClient != null
    }

    /**
     * Perform an HTTP request through the Ziti overlay.
     */
    suspend fun httpRequest(
        method: String,
        url: String,
        headers: Map<String, String>,
        body: String?
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val client = httpClient
            ?: return@withContext mapOf(
                "statusCode" to -1,
                "body" to "Ziti not initialized",
                "headers" to emptyMap<String, String>()
            )

        try {
            val requestBuilder = Request.Builder().url(url)

            for ((key, value) in headers) {
                requestBuilder.addHeader(key, value)
            }

            val requestBody = body?.toRequestBody("application/json".toMediaTypeOrNull())
            when (method.uppercase()) {
                "GET" -> requestBuilder.get()
                "POST" -> requestBuilder.post(requestBody ?: "".toRequestBody(null))
                "PUT" -> requestBuilder.put(requestBody ?: "".toRequestBody(null))
                "DELETE" -> if (requestBody != null) requestBuilder.delete(requestBody) else requestBuilder.delete()
                "PATCH" -> requestBuilder.patch(requestBody ?: "".toRequestBody(null))
                else -> requestBuilder.method(method.uppercase(), requestBody)
            }

            val request = requestBuilder.build()
            Log.d(TAG, "HTTP $method $url")

            val response = client.newCall(request).execute()

            val responseHeaders = mutableMapOf<String, String>()
            for (name in response.headers.names()) {
                responseHeaders[name] = response.header(name) ?: ""
            }

            val result = mapOf(
                "statusCode" to response.code,
                "body" to (response.body?.string() ?: ""),
                "headers" to responseHeaders
            )

            Log.d(TAG, "HTTP $method $url → ${response.code}")
            result
        } catch (e: IOException) {
            Log.e(TAG, "HTTP request failed: ${e.message}", e)
            mapOf(
                "statusCode" to -1,
                "body" to "Connection error: ${e.message}",
                "headers" to emptyMap<String, String>()
            )
        }
    }

    /**
     * Get status info for reporting to Dart.
     */
    fun getStatus(): Map<String, Any?> {
        return mapOf(
            "hasIdentity" to hasIdentity(),
            "isConnected" to isConnected(),
            "identityName" to zitiContext?.name(),
        )
    }

    /**
     * Delete identity and reset state.
     */
    fun deleteIdentity(): Boolean {
        return try {
            zitiContext?.let { ctx ->
                ZitiAndroid.deleteIdentity(ctx)
            }
            zitiContext = null
            httpClient = null
            Log.i(TAG, "Identity deleted")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete identity: ${e.message}", e)
            false
        }
    }
}
