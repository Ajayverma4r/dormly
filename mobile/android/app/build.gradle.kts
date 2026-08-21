import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.dormly"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            // Values are read from local.properties so the keystore password
            // is never committed to Git. See instructions below.
            val props = Properties()
            val localPropsFile = rootProject.file("local.properties")
            if (localPropsFile.exists()) props.load(localPropsFile.inputStream())

            storeFile     = file(props.getProperty("KEY_STORE_FILE", "app/dormly-release.jks"))
            storePassword = props.getProperty("KEY_STORE_PASSWORD", "")
            keyAlias      = props.getProperty("KEY_ALIAS", "dormly")
            keyPassword   = props.getProperty("KEY_PASSWORD", "")
        }
    }

    defaultConfig {
        applicationId = "com.example.dormly"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // Explicitly include both ARM ABIs for physical Android devices.
            // arm64-v8a  → all phones since 2015 (64-bit)
            // armeabi-v7a → older 32-bit phones (fallback)
            // x86/x86_64 are emulator-only and add ~15MB to the APK for no benefit.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    buildTypes {
        release {
            // Using debug key for now — fine for sideloading & external testing.
            // Switch to signingConfigs.getByName("release") before Play Store upload.
            signingConfig = signingConfigs.getByName("debug")
            // Minification disabled — R8 was stripping JNI/plugin classes at runtime
            // causing "Can't open" on physical devices. Re-enable only after confirming
            // a working ProGuard rule set. APK size ~10MB larger but 100% stable.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
