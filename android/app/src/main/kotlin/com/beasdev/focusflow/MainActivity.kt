package com.beasdev.focusflow

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.beasdev.focusflow/alarm_screen"

    // Debe coincidir con el prefijo de payload que arma NotificacionesService
    // para las notificaciones de alarma (ver notificaciones_service.dart,
    // los `payload: 'alarma|...'` en _programarNotificacion/
    // programarAlertaRutina/posponerAlarma). Si ese prefijo cambia allá, hay
    // que replicarlo aquí.
    private val PREFIJO_PAYLOAD_ALARMA = "alarma|"
    private val ACTION_SELECT_NOTIFICATION = "SELECT_NOTIFICATION"
    private val EXTRA_PAYLOAD = "payload"

    // true mientras PantallaAlarma confirmó (vía MethodChannel) que sigue
    // montada. Evita que sincronizarLockscreenConIntent() apague el flag de
    // golpe si llega un Intent no-alarma (p. ej. se tocó un recordatorio)
    // mientras una alarma sigue legítimamente visible.
    private var pantallaAlarmaConfirmadaPorDart = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showOverLockscreen" -> {
                    pantallaAlarmaConfirmadaPorDart = true
                    setShowOverLockscreen(true)
                    result.success(null)
                }
                "hideOverLockscreen" -> {
                    pantallaAlarmaConfirmadaPorDart = false
                    setShowOverLockscreen(false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // En cold start (proceso muerto), Android crea esta Activity directamente
    // desde el fullScreenIntent de la notificación de alarma, antes de que
    // Flutter siquiera exista. Si esperáramos al roundtrip por MethodChannel
    // de showOverLockscreen (invocado recién en PantallaAlarma.initState), el
    // keyguard ya resolvió la visibilidad de la ventana. Por eso se revisa el
    // Intent aquí, de forma síncrona, apenas se crea la Activity.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sincronizarLockscreenConIntent(intent)
    }

    // launchMode="singleTop" (ver AndroidManifest.xml) reutiliza esta misma
    // instancia si ya existe en el stack; una segunda alarma mientras la
    // primera sigue viva llega por acá, no por onCreate().
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sincronizarLockscreenConIntent(intent)
    }

    private fun sincronizarLockscreenConIntent(intent: Intent?) {
        val esAlarma = intent?.action == ACTION_SELECT_NOTIFICATION &&
            intent?.getStringExtra(EXTRA_PAYLOAD)?.startsWith(PREFIJO_PAYLOAD_ALARMA) == true
        if (esAlarma) {
            setShowOverLockscreen(true)
        } else if (!pantallaAlarmaConfirmadaPorDart) {
            // Apagado defensivo: si el flag quedó en true por una alarma
            // anterior cuya PantallaAlarma nunca llegó a montarse (y por lo
            // tanto nunca llamó a hideOverLockscreen), este es el próximo
            // Intent no-alarma que recibe la Activity para autocorregirse.
            // No se toca si Dart ya confirmó que hay una alarma visible.
            setShowOverLockscreen(false)
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
