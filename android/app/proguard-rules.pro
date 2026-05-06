# Mantener intactas las librerías de notificaciones y alarmas
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class dev.fluttercommunity.plus.android_alarm_manager_plus.** { *; }

# Mantener intacto a GSON para que pueda leer y guardar las alarmas en la memoria
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken