package com.beasdev.focusflow

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Paint
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

// Ids de una tarjeta de rutina dentro del layout. Cada subclase concreta
// (RutinasWidgetProviderChico/Grande) arma su propia lista con los ids que
// declara SU layout, mismo motivo que FilaIds en TareasWidgetProviderBase:
// Grande es quien primero declara fila3/fila4, así que la base no puede
// referenciarlos de forma fija sin romper la compilación de Chico solo.
data class FilaRutinaIds(
    val contenedor: Int,
    val titulo: Int,
    val hora: Int,
    val badge: Int,
    val check: Int,
)

// Base compartida por RutinasWidgetProviderChico y RutinasWidgetProviderGrande.
// Ambas variantes son de tamaño FIJO (resizeMode="none"), mismo criterio que
// TareasWidgetProviderBase. Conserva el blindaje defensivo del
// RutinasWidgetProvider viejo (try/catch por fila, validarRemoteViews,
// fallback seguro) porque ya demostró ser necesario.
abstract class RutinasWidgetProviderBase(
    private val layoutResId: Int,
    private val filaIds: List<FilaRutinaIds>,
    // Chico solo muestra el contador en texto ("X/Y hechas"); Grande agrega
    // la barra de progreso visual al lado. Se pasa el id en vez de un boolean
    // porque, igual que con fila3/fila4 en FilaRutinaIds, Chico no puede
    // referenciar un id que solo declara el layout de Grande.
    private val progresoBarId: Int?,
    // Grande muestra la agenda completa de hoy ordenada por hora
    // (rutinas_widget_data); Chico muestra la misma agenda completa (nada
    // desaparece al completarse) pero ordenada por cercanía a la hora
    // actual (rutinas_widget_data_chico) — cada uno lee su propia clave,
    // calculada por WidgetRutinasService.actualizar().
    private val dataKey: String,
    // El footer "+N rutinas más" de ambas variantes cuenta contra el mismo
    // total programado hoy (Grande y Chico muestran la misma agenda, solo
    // cambia el orden y cuántas filas entran).
    private val totalParaFooterKey: String,
    // Grande muestra el badge "HECHA" además del tachado + check relleno;
    // Chico (más apretado de espacio) omite ese badge porque el tachado y
    // el check ya alcanzan para comunicar "completada" sin el texto extra.
    // El badge "OMITIDA" no tiene otro indicador visual (no hay tachado ni
    // check para ese estado), así que se muestra en ambas variantes.
    private val mostrarBadgeHecha: Boolean = true,
) : HomeWidgetProvider() {
    private data class ItemRutina(
        val id: String,
        val titulo: String,
        val horaHoy: String,
        val completada: Boolean,
        val omitida: Boolean,
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (appWidgetId in appWidgetIds) {
            renderizarWidget(context, appWidgetManager, appWidgetId, widgetData)
        }
    }

    private fun renderizarWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences,
    ) {
        try {
            val items = parseRutinas(widgetData.getString(dataKey, null))
            val totalProgramadas = widgetData.getString(WIDGET_TOTAL_PROGRAMADAS_KEY, null)?.toIntOrNull()
                ?: items.size
            val totalHechas = widgetData.getString(WIDGET_TOTAL_HECHAS_KEY, null)?.toIntOrNull() ?: 0
            val totalParaFooter = widgetData.getString(totalParaFooterKey, null)?.toIntOrNull() ?: items.size
            val hayRutinasHoy = totalProgramadas > 0

            val itemsAMostrar = items.take(filaIds.size)
            val restantes = (totalParaFooter - itemsAMostrar.size).coerceAtLeast(0)

            val views = RemoteViews(context.packageName, layoutResId)

            views.setViewVisibility(R.id.widget_rutinas_contador_row, if (hayRutinasHoy) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_rutinas_hechas_num, totalHechas.toString())
            views.setTextViewText(R.id.widget_rutinas_contador_resto, "/$totalProgramadas hechas")
            if (progresoBarId != null) {
                val progreso = if (totalProgramadas > 0) (totalHechas * 100) / totalProgramadas else 0
                views.setProgressBar(progresoBarId, 100, progreso, false)
            }

            for (i in filaIds.indices) {
                val fila = filaIds[i]
                if (i >= itemsAMostrar.size) {
                    views.setViewVisibility(fila.contenedor, View.GONE)
                    continue
                }
                // Try-catch por fila: si una rutina puntual tiene un dato que
                // rompe el render, no debe tumbar a las demás filas (mismo
                // blindaje que ya tenía RutinasWidgetProvider).
                try {
                    val item = itemsAMostrar[i]
                    views.setViewVisibility(fila.contenedor, View.VISIBLE)
                    views.setTextViewText(fila.titulo, item.titulo)
                    views.setInt(
                        fila.titulo,
                        "setPaintFlags",
                        if (item.completada) Paint.STRIKE_THRU_TEXT_FLAG else 0,
                    )

                    views.setTextViewText(fila.hora, item.horaHoy)
                    val deEnfatizada = item.completada || item.omitida
                    views.setInt(
                        fila.hora,
                        "setBackgroundResource",
                        if (deEnfatizada) R.drawable.widget_pill_hora_hecha else R.drawable.widget_pill_hora_pendiente,
                    )
                    views.setTextColor(
                        fila.hora,
                        ContextCompat.getColor(
                            context,
                            if (deEnfatizada) R.color.widget_text_secondary else R.color.widget_accent,
                        ),
                    )

                    when {
                        item.completada -> if (mostrarBadgeHecha) {
                            views.setViewVisibility(fila.badge, View.VISIBLE)
                            views.setTextViewText(fila.badge, "HECHA")
                            views.setInt(fila.badge, "setBackgroundResource", R.drawable.widget_pill_hecha)
                            views.setTextColor(fila.badge, COLOR_COMPLETADA)
                        } else {
                            views.setViewVisibility(fila.badge, View.GONE)
                        }
                        item.omitida -> {
                            views.setViewVisibility(fila.badge, View.VISIBLE)
                            views.setTextViewText(fila.badge, "OMITIDA")
                            views.setInt(fila.badge, "setBackgroundResource", R.drawable.widget_pill_omitida)
                            views.setTextColor(fila.badge, COLOR_OMITIDA)
                        }
                        else -> views.setViewVisibility(fila.badge, View.GONE)
                    }

                    views.setImageViewResource(
                        fila.check,
                        if (item.completada) R.drawable.ic_widget_check_filled else R.drawable.ic_widget_check_empty,
                    )
                    // El check es puramente informativo (solo refleja completada/no
                    // completada): sin PendingIntent propio, un toque ahí cae al
                    // click de la raíz igual que el resto de la tarjeta (abre la
                    // app). Antes completaba/descompletaba la rutina sin abrir la
                    // app, pero eso hacía que la rutina desapareciera de Chico
                    // (que solo mostraba pendientes) sin ninguna señal visual de
                    // qué pasó — ver WidgetRutinasService.actualizar().
                } catch (e: Throwable) {
                    views.setViewVisibility(fila.contenedor, View.GONE)
                }
            }

            views.setViewVisibility(R.id.widget_rutinas_footer, if (restantes > 0) View.VISIBLE else View.GONE)
            if (restantes > 0) {
                val palabra = if (restantes == 1) "rutina" else "rutinas"
                views.setTextViewText(R.id.widget_rutinas_footer, "+$restantes $palabra más")
            }

            views.setViewVisibility(R.id.widget_rutinas_vacio, if (hayRutinasHoy) View.GONE else View.VISIBLE)

            // El botón "Programar rutina" tiene su propio PendingIntent (abajo)
            // y lo captura antes de que llegue acá: tocar cualquier otro punto
            // del widget (incluido el check, que ya no tiene intent propio)
            // abre la app en la pantalla de Rutinas.
            val abrirRutinasPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("homewidget://abrir_rutinas"),
            )
            views.setOnClickPendingIntent(R.id.widget_rutinas_root, abrirRutinasPendingIntent)

            val programarRutinaPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("homewidget://programar_rutina"),
            )
            views.setOnClickPendingIntent(R.id.widget_rutinas_programar, programarRutinaPendingIntent)

            // La inflación real ocurre en el proceso del widget host: sin este
            // paso, una vista no soportada o un ID mal referenciado fallaría
            // en silencio ahí, mismo blindaje que ya tenía RutinasWidgetProvider.
            views.apply(context, FrameLayout(context))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Throwable) {
            renderizarFallbackSeguro(context, appWidgetManager, appWidgetId)
        }
    }

    private fun renderizarFallbackSeguro(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        try {
            val views = RemoteViews(context.packageName, layoutResId)
            for (fila in filaIds) {
                views.setViewVisibility(fila.contenedor, View.GONE)
            }
            views.setViewVisibility(R.id.widget_rutinas_contador_row, View.GONE)
            views.setViewVisibility(R.id.widget_rutinas_footer, View.GONE)
            views.setViewVisibility(R.id.widget_rutinas_vacio, View.VISIBLE)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Throwable) {
            // Si el fallback también falla, no queda más blindaje posible acá.
        }
    }

    private fun parseRutinas(json: String?): List<ItemRutina> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                ItemRutina(
                    id = item.optString("id", ""),
                    titulo = item.optString("titulo", ""),
                    horaHoy = item.optString("horaHoy", ""),
                    completada = item.optBoolean("completada", false),
                    omitida = item.optBoolean("omitida", false),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    companion object {
        private const val WIDGET_TOTAL_PROGRAMADAS_KEY = "rutinas_widget_total_programadas"
        private const val WIDGET_TOTAL_HECHAS_KEY = "rutinas_widget_total_hechas"

        // Misma paleta que ya usaba RutinasWidgetProvider para estado
        // (completada/omitida), distinta de la de urgencia de Tareas.
        private val COLOR_COMPLETADA = 0xFF4CAF50.toInt() // verde
        private val COLOR_OMITIDA = 0xFFF59E0B.toInt() // ámbar
    }
}
