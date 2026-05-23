# =============================================================================
# FLUTTER — core engine & plugin registry
# =============================================================================
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# =============================================================================
# KOTLIN — stdlib, reflection, coroutines, serialization
# =============================================================================
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Lazy { <methods>; }

-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Kotlin serialization — prevents stripping @Serializable class descriptors
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
-dontnote kotlinx.serialization.AnnotationsKt
-keep,includedescriptorclasses class **$$serializer { *; }
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class * {
    @kotlinx.serialization.Serializable <methods>;
    kotlinx.serialization.KSerializer serializer(...);
}

# =============================================================================
# YOUR DATA MODELS — JSON fromMap / toMap / fromJson / toJson
# Adapt the package path to match your own (com.hallaqak.app or wherever
# your generated/handwritten model classes live).
# =============================================================================
# Option A — keep every class in your models package by name:
# -keep class com.hallaqak.app.models.** { *; }

# Option B (safer for Flutter/Dart Supabase maps) — keep all public
# constructors and fields so R8 never renames/removes them:
-keepclassmembers class ** {
    public <init>(...);
    public <fields>;
}

# Always preserve @Keep-annotated classes (add @Keep to critical model classes)
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# =============================================================================
# SUPABASE + KTOR (HTTP engine) + OKHTTP / OKIO
# =============================================================================
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**

-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
# Ktor uses ServiceLoader — keep the META-INF entries
-keep class io.ktor.client.engine.** { *; }

-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okhttp3.internal.** { *; }
-keep interface okhttp3.** { *; }

-keep class okio.** { *; }
-dontwarn okio.**

# =============================================================================
# JSON — Gson / Moshi / kotlinx.serialization (common in Flutter plugin deps)
# =============================================================================
# Gson
-keepattributes Signature
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
# Prevent R8 from stripping generic type info used by Gson TypeToken
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Moshi
-keep class com.squareup.moshi.** { *; }
-dontwarn com.squareup.moshi.**

# Jackson
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**

# =============================================================================
# FIREBASE (keep even if not used — google-services may still link them)
# =============================================================================
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# =============================================================================
# FLUTTER PLUGINS
# =============================================================================
# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Google Fonts
-dontwarn com.google.fonts.**

# Google Play Core (deferred components)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# =============================================================================
# ANDROID / ANDROIDX — reflection, annotations, Parcelable
# =============================================================================
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes SourceFile, LineNumberTable   # preserves crash stack traces

# Parcelable (required for Android IPC)
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Enum — R8 strips values()/valueOf() which breaks switch statements
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Serializable
-keepclassmembers class * implements java.io.Serializable {
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
