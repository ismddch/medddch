# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Core (used by Flutter deferred components — not bundled in APK)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Supabase / Ktor / OkHttp
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**

# Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class ** {
    @kotlinx.serialization.Serializable <methods>;
}

# Google Fonts
-keep class com.google.fonts.** { *; }

# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Firebase / FCM
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Shared Preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Flutter Local Notifications
-keep class com.dexterous.** { *; }

# Keep all model classes (used with JSON serialisation)
-keepclassmembers class ** {
    public <init>(...);
}

# Prevent stripping R8 rules for reflection
-keepattributes Signature
-keepattributes *Annotation*
