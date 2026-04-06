# JNA — keep Pointer.peer field required by native code; ignore AWT (not on Android)
-keep class com.sun.jna.** { *; }
-dontwarn java.awt.**
-dontwarn com.goterl.lazysodium.**
-keep class com.goterl.lazysodium.** { *; }

# JJWT — loaded via ServiceLoader reflection by ziti-android SDK
-keep class io.jsonwebtoken.** { *; }
-keepnames class io.jsonwebtoken.** { *; }
-dontwarn io.jsonwebtoken.**

# OpenZiti SDK — keep API and model classes for Retrofit reflection
-keep class org.openziti.api.** { *; }
-keep class org.openziti.impl.** { *; }
-keep class org.openziti.edge.** { *; }
-keep class org.openziti.ZitiContext$Status { *; }
-keep class org.openziti.ZitiContext$Status$* { *; }
-keepnames class org.openziti.** { *; }
-dontwarn org.openziti.**

# Retrofit — used by Ziti SDK for controller API calls
-keepattributes Signature
-keepattributes *Annotation*
-keep class retrofit2.** { *; }
-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-dontwarn retrofit2.**

# Retrofit Kotlin Coroutines Adapter — used by Ziti SDK
-keep class com.jakewharton.retrofit2.** { *; }
-keep class kotlinx.coroutines.Deferred { *; }
-keep class kotlinx.coroutines.CompletableDeferred { *; }

# Keep Ziti API interfaces intact (Retrofit creates proxies from them)
-keep interface org.openziti.api.API { *; }
