package com.beasdev.focusflow

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.FrameLayout
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// Widget 4x2: una tarjeta con anillo por métrica (Tareas y Rutinas), cada
// una con su propio porcentaje dentro del anillo y su fracción/pendientes al
// lado. Ambas tarjetas se muestran siempre, incluso con 0 completadas hoy
// (el anillo de Rutinas no debe desaparecer solo porque todavía no se
// completó nada — con 0% simplemente se ve gris, sin caso especial).
class ProgresoWidgetProviderGrande : HomeWidgetProvider() {
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
        val resumen = leerProgresoResumen(widgetData)
        // Layout fijo por instancia según minWidth (ancho en portrait): ver
        // esLayoutCompacto/UMBRAL_ANCHO_COMPACTO_GRANDE_DP en
        // ProgresoWidgetCommon.kt para la justificación del umbral y de por
        // qué se usa minWidth (no maxWidth) a propósito.
        val compacto = esLayoutCompacto(appWidgetManager, appWidgetId, UMBRAL_ANCHO_COMPACTO_GRANDE_DP)
        val layoutId = if (compacto) R.layout.widget_progreso_grande_compacto else R.layout.widget_progreso_grande
        val views = RemoteViews(context.packageName, layoutId)
        val diametroAnillo = if (compacto) 40 else 58
        val grosorAnillo = if (compacto) 5f else 7f

        views.setTextViewText(R.id.widget_progreso_dia_hoy, diaDeSemanaLegible())

        val colorTareas = ContextCompat.getColor(context, R.color.widget_progress_tareas)
        val colorRutinas = ContextCompat.getColor(context, R.color.widget_accent)

        views.setImageViewBitmap(
            R.id.widget_progreso_tareas_anillo,
            dibujarAnilloProgreso(context, diametroDp = diametroAnillo, grosorDp = grosorAnillo, progresoPorcentaje = resumen.tareasPorcentaje, colorProgreso = colorTareas),
        )
        views.setTextViewText(R.id.widget_progreso_tareas_porcentaje, "${resumen.tareasPorcentaje}%")
        views.setTextViewText(
            R.id.widget_progreso_tareas_fraccion,
            "${resumen.tareasCompletadas}/${resumen.tareasTotal}",
        )
        views.setTextViewText(
            R.id.widget_progreso_tareas_pendientes,
            textoPendientes(resumen.tareasPendientes, "tarea pendiente", "tareas pendientes", "Todas hechas"),
        )

        views.setImageViewBitmap(
            R.id.widget_progreso_rutinas_anillo,
            dibujarAnilloProgreso(
                context,
                diametroDp = diametroAnillo,
                grosorDp = grosorAnillo,
                progresoPorcentaje = resumen.rutinasPorcentaje,
                colorProgreso = colorRutinas,
                progresoOmitidoPorcentaje = resumen.rutinasOmitidoPorcentaje,
            ),
        )
        views.setTextViewText(R.id.widget_progreso_rutinas_porcentaje, "${resumen.rutinasPorcentaje}%")
        views.setTextViewText(
            R.id.widget_progreso_rutinas_fraccion,
            "${resumen.rutinasHechas}/${resumen.rutinasTotal}",
        )
        val rutinasPendientesTexto = textoPendientes(resumen.rutinasPendientes, "rutina pendiente", "rutinas pendientes", "Todas hechas")
        if (compacto) {
            // widget_progreso_grande_compacto.xml no tiene una línea propia
            // para la nota de omitidas (el texto secundario comparte una
            // sola línea a todo el ancho, alternativa (a) aprobada) — se
            // concatena acá en vez de llamar a aplicarNotaOmitidas.
            views.setTextViewText(R.id.widget_progreso_rutinas_pendientes, rutinasPendientesTexto + sufijoOmitidas(resumen.rutinasOmitidas))
        } else {
            // "(N omitida)" en su propia línea (no en el % de arriba: ese
            // texto vive dentro del anillo de 58dp, sin espacio de sobra) —
            // ver aplicarNotaOmitidas en ProgresoWidgetCommon.kt.
            aplicarNotaOmitidas(views, R.id.widget_progreso_rutinas_omitidas_nota, resumen.rutinasOmitidas)
            views.setTextViewText(R.id.widget_progreso_rutinas_pendientes, rutinasPendientesTexto)
        }

        val abrirPendingIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("homewidget://abrir_tareas"),
        )
        views.setOnClickPendingIntent(R.id.widget_progreso_root, abrirPendingIntent)

        // El refresco corre headless (mismo patrón que el toggle de Tareas):
        // vuelve a calcular los totales de Tareas y a pedir el repintado de
        // ambas variantes de Progreso sin abrir la app.
        val refrescarPendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("homewidget://refrescar_progreso"),
        )
        views.setOnClickPendingIntent(R.id.widget_progreso_refresh, refrescarPendingIntent)

        // La inflación real ocurre en el proceso del widget host: sin este
        // paso, una vista no soportada o un ID mal referenciado fallaría en
        // silencio ahí (mismo blindaje que Rutinas/Tareas/Notas).
        views.apply(context, FrameLayout(context))

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
