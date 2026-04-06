package com.example.chpayclient

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {

    companion object {
        private const val ZITI_CHANNEL = "com.chpayclient/ziti"
        private const val CERT_CHANNEL = "com.chpayclient/certificate"
        private const val UPDATE_CHANNEL = "com.chpayclient/update"
    }

    private lateinit var zitiManager: ZitiManager
    private lateinit var certificateManager: CertificateManager
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        zitiManager = ZitiManager(applicationContext)
        certificateManager = CertificateManager(applicationContext)

        // --- Ziti MethodChannel ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ZITI_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasIdentity" -> {
                        result.success(zitiManager.hasIdentity())
                    }

                    "enroll" -> {
                        val jwt = call.argument<String>("jwt")
                        if (jwt == null) {
                            result.error("INVALID_ARG", "jwt is required", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                val success = zitiManager.enroll(jwt)
                                result.success(success)
                            } catch (e: Exception) {
                                result.error("ENROLL_FAILED", e.message, null)
                            }
                        }
                    }

                    "initialize" -> {
                        scope.launch {
                            try {
                                val success = zitiManager.initialize()
                                result.success(success)
                            } catch (e: Exception) {
                                result.error("INIT_FAILED", e.message, null)
                            }
                        }
                    }

                    "isConnected" -> {
                        result.success(zitiManager.isConnected())
                    }

                    "getStatus" -> {
                        result.success(zitiManager.getStatus())
                    }

                    "httpRequest" -> {
                        val method = call.argument<String>("method") ?: "GET"
                        val url = call.argument<String>("url") ?: ""
                        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                        val body = call.argument<String>("body")

                        scope.launch {
                            try {
                                val response = zitiManager.httpRequest(method, url, headers, body)
                                result.success(response)
                            } catch (e: Exception) {
                                result.error("HTTP_FAILED", e.message, null)
                            }
                        }
                    }

                    "deleteIdentity" -> {
                        result.success(zitiManager.deleteIdentity())
                    }

                    else -> result.notImplemented()
                }
            }

        // --- Certificate MethodChannel (existing functionality) ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CERT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installCertificate" -> {
                        val p12Base64 = call.argument<String>("p12_base64")
                        val password = call.argument<String>("password")
                        if (p12Base64 == null || password == null) {
                            result.error("INVALID_ARG", "p12_base64 and password are required", null)
                            return@setMethodCallHandler
                        }
                        result.success(certificateManager.importCertificate(p12Base64, password))
                    }

                    "hasCertificate" -> {
                        result.success(certificateManager.hasCertificate())
                    }

                    "getCertificateInfo" -> {
                        result.success(certificateManager.getCertificateInfo())
                    }

                    else -> result.notImplemented()
                }
            }

        // --- Update MethodChannel ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "downloadApk" -> {
                        val url    = call.argument<String>("url")
                        val bearer = call.argument<String>("bearer")
                        if (url == null || bearer == null) {
                            result.error("INVALID_ARG", "url y bearer son requeridos", null)
                            return@setMethodCallHandler
                        }
                        val cacheDir = java.io.File(applicationContext.cacheDir, "apk_downloads")
                        scope.launch {
                            try {
                                val path = zitiManager.downloadApk(url, bearer, cacheDir) { progress ->
                                    android.util.Log.d("Update", "Descarga: $progress%")
                                }
                                result.success(mapOf("path" to path))
                            } catch (e: Exception) {
                                result.error("DOWNLOAD_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}

