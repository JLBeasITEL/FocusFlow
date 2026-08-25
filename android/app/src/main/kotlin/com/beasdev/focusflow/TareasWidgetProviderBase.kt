package com.beasdev.focusflow

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import org.json.JSONArray

// Ids de una tarjeta de tarea dentro del layout. Cada subclase concreta
// (TareasWidgetProviderChico/Grande) arma su propia lista de estos con los
// ids que declara SU layout: aunque widget_tareas_chico.xml y
// widget_tareas_grande.xml reusan los mismos nombres de id para las primeras
// tarjetas (los ids de layout son globales a la app, no hay conflicto entre
// XMLs distintos que reusan el mismo nombre), Grande es quien primero declara
// fila3/fila4 — si la base los referenciara de forma fija antes de que ese
// layout exista, Chico no compilaría por sí solo.
data class FilaIds(
    val contenedor: Int,
    val titulo: Int,
    val fecha: Int,
    val prioridad: Int,
)

// Base compartida por TareasWidgetProviderChico y TareasWidgetProviderGrande.
// Ambas variantes son de tamaño FIJO (resizeMode="none", sin recalcular filas
// según el alto disponible como hacía el TareasWidgetProvider original):
// filaIds.size define cuántas tarjetas pre-construidas tiene el layout de
// cada una, y layoutResId cuál XML inflar. El resto del renderizado (parseo,
// formateo de fecha relativa, colores por urgencia) es idéntico entre ambas.
abstract class TareasWidgetProviderBase(
    private val layoutResId: Int,
    private val filaIds: List<FilaIds>,
    // Chico no tiene el badge de conteo total (solo el toggle en el
    // encabezado); Grande sí lo conserva.
    private val mostrarContador: Boolean = true,
    // Chico se comporta como acceso directo: tocar cualquier parte de la
    // tarjeta que no sea el ícono de alternancia abre la app en la pantalla
    // de tareas. Requiere que el layout declare @id/widget_tareas_root.
    private val abrirAppAlTocar: Boolean = false,
) : HomeWidgetProvider() {
    private data class ItemTarea(
        val titulo: String,
        val fechaIso: String,
        val urgencia: Int,
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
        val modo = widgetData.getString(WIDGET_MODO_KEY, MODO_PROXIMAS) ?: MODO_PROXIMAS
        val dataKey = if (modo == MODO_IMPORTANTES) WIDGET_DATA_IMPORTANTES_KEY else WIDGET_DATA_PROXIMAS_KEY
        val items = parseTareas(widgetData.getString(dataKey, null))
        // El total de pendientes es el mismo para ambos modos (mismo conjunto,
        // solo cambia el orden), así que el badge del encabezado no depende
        // de cuántos items mandó este modo puntual.
        val totalPendientes = widgetData.getString(WIDGET_TOTAL_KEY, null)?.toIntOrNull() ?: items.size

        val itemsAMostrar = items.take(filaIds.size)
        val restantes = (totalPendientes - itemsAMostrar.size).coerceAtLeast(0)

        val views = RemoteViews(context.packageName, layoutResId)

        views.setTextViewText(
            R.id.widget_tareas_titulo,
            if (modo == MODO_IMPORTANTES) "Más importantes" else "Próximas",
        )
        if (mostrarContador) {
            views.setTextViewText(R.id.widget_tareas_contador, totalPendientes.toString())
        }

        for (i in filaIds.indices) {
            val fila = filaIds[i]
            if (i < itemsAMostrar.size) {
                val item = itemsAMostrar[i]
                views.setViewVisibility(fila.contenedor, View.VISIBLE)
                views.setTextViewText(fila.titulo, item.titulo)

                val (textoFecha, esUrgente) = formatearFechaRelativa(item.fechaIso)
                views.setTextViewText(fila.fecha, textoFecha)
                views.setTextColor(
                    fila.fecha,
                    ContextCompat.getColor(
                        context,
                        if (esUrgente) R.color.widget_date_urgent else R.color.widget_text_secondary,
                    ),
                )

                views.setInt(fila.prioridad, "setBackgroundResource", pillFondoResId(item.urgencia))
                views.setTextViewText(fila.prioridad, etiquetaUrgencia(item.urgencia))
                views.setTextColor(fila.prioridad, colorUrgenciaTexto(item.urgencia))
            } else {
                views.setViewVisibility(fila.contenedor, View.GONE)
            }
        }

        views.setViewVisibility(R.id.widget_tareas_footer, if (restantes > 0) View.VISIBLE else View.GONE)
        if (restantes > 0) {
            val palabraTarea = if (restantes == 1) "tarea" else "tareas"
            views.setTextViewText(R.id.widget_tareas_footer, "+$restantes $palabraTarea más")
        }

        views.setViewVisibility(
            R.id.widget_tareas_vacio,
            if (itemsAMostrar.isEmpty()) View.VISIBLE else View.GONE,
        )

        val togglePendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("homewidget://toggle_modo_tareas"),
        )
        views.setOnClickPendingIntent(R.id.widget_tareas_toggle, togglePendingIntent)

        // El toggle tiene su propio PendingIntent (arriba) y captura el click
        // antes de que llegue a la raíz: tocar el ícono sigue alternando el
        // modo, tocar el resto de la tarjeta abre la app.
        if (abrirAppAlTocar) {
            val abrirAppPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("homewidget://abrir_tareas"),
            )
            views.setOnClickPendingIntent(R.id.widget_tareas_root, abrirAppPendingIntent)
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun parseTareas(json: String?): List<ItemTarea> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                ItemTarea(
                    titulo = item.optString("titulo", ""),
                    fechaIso = item.optString("fechaLimite", ""),
                    urgencia = item.optInt("urgencia", 1),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    // Misma convención posicional que el TareasWidgetProvider original usaba
    // para evitar depender de parseo estricto de ISO8601 (la longitud de los
    // microsegundos que emite DateTime.toIso8601String() en Dart varía): se
    // toman año/mes/día/hora por posición en vez de parsear el string entero.
    // Devuelve el texto a mostrar y si la fecha debe pintarse en rojo (vence
    // hoy o ya venció).
    private fun formatearFechaRelativa(iso: String): Pair<String, Boolean> {
        if (iso.length < 16) return Pair("", false)
        return try {
            val anio = iso.substring(0, 4).toInt()
            val mes = iso.substring(5, 7).toInt()
            val dia = iso.substring(8, 10).toInt()
            val hora = iso.substring(11, 16)
            val fecha = LocalDate.of(anio, mes, dia)
            val dias = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.now(), fecha)
            when {
                dias == 0L -> Pair("Hoy $hora", true)
                dias < 0L -> {
                    val dds = -dias
                    Pair("Venció hace $dds ${if (dds == 1L) "día" else "días"}", true)
                }
                dias == 1L -> Pair("Mañana", false)
                else -> Pair("En $dias días", false)
            }
        } catch (e: Exception) {
            Pair("", false)
        }
    }

    // Misma paleta que TemaApp.clasico usa para _getColorUrgencia en
    // home_screen.dart (teal/azul/naranja/rojo para 1-4).
    private fun colorUrgenciaTexto(urgencia: Int): Int = when (urgencia) {
        1 -> 0xFF009688.toInt() // Colors.teal
        2 -> 0xFF2196F3.toInt() // Colors.blue
        3 -> 0xFFFF9800.toInt() // Colors.orange
        4 -> 0xFFF44336.toInt() // Colors.red
        else -> 0xFF9E9E9E.toInt() // Colors.grey
    }

    private fun pillFondoResId(urgencia: Int): Int = when (urgencia) {
        1 -> R.drawable.widget_pill_bajo
        2 -> R.drawable.widget_pill_medio
        3 -> R.drawable.widget_pill_alto
        4 -> R.drawable.widget_pill_muyalto
        else -> R.drawable.widget_pill_bajo
    }

    private fun etiquetaUrgencia(urgencia: Int): String = when (urgencia) {
        1 -> "Bajo"
        2 -> "Medio"
        3 -> "Alto"
        4 -> "Muy alto"
        else -> "?"
    }

    companion object {
        private const val WIDGET_DATA_PROXIMAS_KEY = "tareas_widget_data_proximas"
        private const val WIDGET_DATA_IMPORTANTES_KEY = "tareas_widget_data_importantes"
        private const val WIDGET_MODO_KEY = "tareas_widget_modo"
        private const val WIDGET_TOTAL_KEY = "tareas_widget_total_pendientes"
        private const val MODO_IMPORTANTES = "importantes"
        private const val MODO_PROXIMAS = "proximas"
    }
}
