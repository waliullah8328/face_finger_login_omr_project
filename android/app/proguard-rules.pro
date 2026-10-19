# Plugins reached from Flutter/native code only through reflection or JNI;
# R8 strips them from release builds otherwise.

# shared_preferences (Pigeon API called from Dart over JNI). Its suspend
# functions are looked up by signature, so the coroutine types keep their names.
-keep class io.flutter.plugins.** { *; }
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }

# ML Kit face detection: registrars are created by reflection.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face** { *; }
-dontwarn com.google.mlkit.**

# TensorFlow Lite (face embeddings).
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
