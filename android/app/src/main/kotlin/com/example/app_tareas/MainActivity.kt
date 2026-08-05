package com.example.app_tareas

import android.os.Build
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.app_tareas/alarm_screen"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showOverLockscreen" -> {
                    setShowOverLockscreen(true)
                    result.success(null)
                }
                "hideOverLockscreen" -> {
                    setShowOverLockscreen(false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Muestra (o deja de mostrar) esta Activity sobre la pantalla de bloqueo.
    // Solo debe activarse mientras se ve la pantalla de alarma (PantallaAlarma);
    // si queda encendido de forma permanente, la app tapa el bloqueo del dispositivo.
    private fun setShowOverLockscreen(enable: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enable)
            setTurnScreenOn(enable)
        } else {
            @Suppress("DEPRECATION")
            if (enable) {
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            } else {
                window.clearFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }
        }
    }
}
