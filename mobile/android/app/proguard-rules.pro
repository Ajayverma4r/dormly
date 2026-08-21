# ─────────────────────────────────────────────────────────────────────────────
# Flutter engine & embedding
# The FlutterActivity base class and embedding layer are loaded by the Android
# OS through the manifest — R8 cannot see the reference and will strip them
# unless explicitly kept.
# ─────────────────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keepclassmembers class io.flutter.embedding.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# GeneratedPluginRegistrant — auto-generated, referenced only by the engine
# ─────────────────────────────────────────────────────────────────────────────
-keep class **.GeneratedPluginRegistrant { *; }

# ─────────────────────────────────────────────────────────────────────────────
# JNI (dart:jni / package:jni) — Dart-to-native bridge
# Every plugin that calls native code (Razorpay, AdMob, SecureStorage) depends
# on this layer. R8 strips it because the entry point is via native dlopen(),
# invisible to the bytecode analyser. Without this rule the app crashes before
# the first frame is rendered on ARM physical devices.
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.github.dart_lang.jni.** { *; }
-keepclassmembers class com.github.dart_lang.jni.** { *; }
-dontwarn com.github.dart_lang.jni.**

# ─────────────────────────────────────────────────────────────────────────────
# WebView Flutter — Razorpay checkout sheet renders inside a Flutter WebView.
# Stripping this plugin makes the payment sheet fail to open.
# ─────────────────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.webviewflutter.** { *; }
-dontwarn io.flutter.plugins.webviewflutter.**

# ─────────────────────────────────────────────────────────────────────────────
# Google Mobile Ads — Flutter plugin wrapper (separate from the GMS SDK itself)
# ─────────────────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.googlemobileads.** { *; }
-dontwarn io.flutter.plugins.googlemobileads.**

# ─────────────────────────────────────────────────────────────────────────────
# Flutter Android Lifecycle plugin
# ─────────────────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.flutter_plugin_android_lifecycle.** { *; }
-dontwarn io.flutter.plugins.flutter_plugin_android_lifecycle.**

# ─────────────────────────────────────────────────────────────────────────────
# EncryptedSharedPreferences — required by flutter_secure_storage when
# AndroidOptions(encryptedSharedPreferences: true) is set.
# ─────────────────────────────────────────────────────────────────────────────
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# ─────────────────────────────────────────────────────────────────────────────
# Razorpay — has a native Java/JS bridge; stripping breaks payment flow
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.razorpay.** { *; }
-keepclassmembers class com.razorpay.** { *; }
-dontwarn com.razorpay.**
# Razorpay uses JS interface annotations
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
# ProGuard strips Serializable classes by default; Razorpay uses them internally
-keepnames class * implements java.io.Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ─────────────────────────────────────────────────────────────────────────────
# Google Mobile Ads (AdMob)
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# ─────────────────────────────────────────────────────────────────────────────
# Google Play Services (shared transport layer for GMS/AdMob)
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ─────────────────────────────────────────────────────────────────────────────
# flutter_secure_storage — uses Android Keystore JNI; stripping crashes storage
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ─────────────────────────────────────────────────────────────────────────────
# file_picker
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# ─────────────────────────────────────────────────────────────────────────────
# url_launcher
# ─────────────────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

# ─────────────────────────────────────────────────────────────────────────────
# Kotlin metadata / coroutines (used transitively by several plugins)
# ─────────────────────────────────────────────────────────────────────────────
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ─────────────────────────────────────────────────────────────────────────────
# OkHttp / Okio (used by Dio's Android HTTP client under the hood)
# ─────────────────────────────────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Play Core Split Install — referenced by Flutter's PlayStoreDeferredComponentManager
# but NOT used in this app (no dynamic feature modules). Suppress so R8 doesn't
# fail with "Missing class" errors during compilation.
# ─────────────────────────────────────────────────────────────────────────────
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ─────────────────────────────────────────────────────────────────────────────
# General safety net — keep all annotations and source signatures for reflection
# ─────────────────────────────────────────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
