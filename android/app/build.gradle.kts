import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// 1. Load the key.properties file
val keystoreProperties = Properties()
val keystorePropertiesFile = project.rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.hallaqak.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        // Updated syntax to avoid the 'jvmTarget' deprecation warning
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.hallaqak.app"
        minSdk = flutter.minSdkVersion                   // explicit — matches old APK's minSdk
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        // Cover ALL ABIs that the old fat APK supported so current users
        // can update. The AAB will generate one split APK per ABI.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
        }
    }

    signingConfigs {
        create("release") {
            // Using getProperty() is safer than the [] syntax
            val alias = keystoreProperties.getProperty("keyAlias")
            val keyPass = keystoreProperties.getProperty("keyPassword")
            val storePass = keystoreProperties.getProperty("storePassword")
            val sFile = keystoreProperties.getProperty("storeFile")

            if (alias != null && keyPass != null && storePass != null && sFile != null) {
                keyAlias = alias
                keyPassword = keyPass
                storePassword = storePass
                storeFile = file(sFile)
            } else {
                throw GradleException("One or more key signing properties are missing in key.properties! (Alias: $alias, storeFile: $sFile)")
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            // Flutter compiles Dart to native ARM code — R8/ProGuard only
            // touches the thin Java/Kotlin plugin wrappers. Enabling shrinking
            // strips classes that plugins discover via reflection, which works
            // locally (debug APK skips R8) but breaks Play Store AAB processing.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
