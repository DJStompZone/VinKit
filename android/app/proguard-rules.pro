# ONNX Runtime's native library (libonnxruntime4j_jni.so) looks up these Java
# classes, fields and methods by their original names via JNI (FindClass /
# GetMethodID). If R8 renames or strips them, the lookup returns null and ART
# aborts with "JNI DETECTED ERROR IN APPLICATION: java_class == null".
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
