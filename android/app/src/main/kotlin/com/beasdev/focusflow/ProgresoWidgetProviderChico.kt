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
import java.time.LocalDate

// Widget 2x2: un anillo con la fracción de Tareas de hoy (X/Y) y, al lado,
// un resumen compacto de Rutinas (fracción + barra), siempre visible (con
// datos en 0 si hace falta, sin mensaje especial). El selector Día/Semana/Mes
// está comentado en el layout (sin historial de completado por fecha, ver
// WidgetProgresoService); en su lugar el header muestra la fecha de hoy.
class ProgresoWidgetProviderChico : HomeWidgetProvider() {
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
        // esLayoutCompacto/UMBRAL_ANCHO_COMPACTO_CHICO_DP en
        // ProgresoWidgetCommon.kt. El umbral de Chico es inferido (no
        // medido en la Huawei), a diferencia del de Grande.
        val compacto = esLayoutCompacto(appWidgetManager, appWidgetId, UMBRAL_ANCHO_COMPACTO_CHICO_DP)
        val layoutId = if (compacto) R.layout.widget_progreso_chico_compacto else R.layout.widget_progreso_chico
        val views = RemoteViews(context.packageName, layoutId)

        val anillo = dibujarAnilloProgreso(
            context = context,
            diametroDp = if (compacto) 56 else 84,
            grosorDp = if (compacto) 6f else 9f,
            progresoPorcentaje = resumen.tareasPorcentaje,
            colorProgreso = ContextCompat.getColor(context, R.color.widget_progress_tareas),
        )
        views.setImageViewBitmap(R.id.widget_progreso_anillo_tareas, anillo)
        views.setTextViewText(
            R.id.widget_progreso_tareas_fraccion,
            "${resumen.tareasCompletadas}/${resumen.tareasTotal}",
        )
        views.setTextViewText(R.id.widget_progreso_fecha_hoy, fechaHoyLegible())

        views.setTextViewText(
            R.id.widget_progreso_rutinas_fraccion,
            "${resumen.rutinasHechas}/${resumen.rutinasTotal}",
        )
        val rutinasPendientesTexto = textoPendientes(resumen.rutinasPendientes, "rutina pendiente", "rutinas pendientes", "Todas hechas")
        if (compacto) {
            // widget_progreso_chico_compacto.xml no tiene una línea propia
            // para la nota de omitidas — se concatena acá, mismo criterio
            // que ProgresoWidgetProviderGrande en su variante comprimida.
            views.setTextViewText(R.id.widget_progreso_rutinas_pendientes, rutinasPendientesTexto + sufijoOmitidas(resumen.rutinasOmitidas))
        } else {
            aplicarNotaOmitidas(views, R.id.widget_progreso_rutinas_omitidas_nota, resumen.rutinasOmitidas)
            views.setTextViewText(R.id.widget_progreso_rutinas_pendientes, rutinasPendientesTexto)
        }
        // Bitmap en vez de ProgressBar declarativo: necesario para pintar el
        // tramo omitido rayado (ver dibujarBarraProgreso en
        // ProgresoWidgetCommon.kt). anchoDp es una resolución interna de
        // diseño, no el ancho real del host — el ImageView usa
        // scaleType="fitXY" para estirarse al ancho real que le dé el launcher.
        views.setImageViewBitmap(
            R.id.widget_progreso_rutinas_bar,
            dibujarBarraProgreso(
                context = context,
                anchoDp = if (compacto) 100 else 140,
                altoDp = if (compacto) 5 else 6,
                progresoPorcentaje = resumen.rutinasPorcentaje,
                colorProgreso = ContextCompat.getColor(context, R.color.widget_accent),
                colorFondo = ContextCompat.getColor(context, R.color.widget_border),
                progresoOmitidoPorcentaje = resumen.rutinasOmitidoPorcentaje,
            ),
        )

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

    // Día de semana vía diaDeSemanaLegible() (ProgresoWidgetCommon.kt,
    // compartido con Grande); acá se le suma el día/mes porque Chico tiene
    // más ancho de header disponible que Grande.
    private fun fechaHoyLegible(): String {
        val hoy = LocalDate.now()
        val meses = listOf(
            "enero", "febrero", "marzo", "abril", "mayo", "junio",
            "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
        )
        return "${diaDeSemanaLegible()}, ${hoy.dayOfMonth} de ${meses[hoy.monthValue - 1]}"
    }
}
