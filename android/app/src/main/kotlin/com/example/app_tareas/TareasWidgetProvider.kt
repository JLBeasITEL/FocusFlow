package com.example.app_tareas

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class TareasWidgetProvider : HomeWidgetProvider() {
    private data class ItemTarea(
        val titulo: String,
        val fechaCorta: String,
        val urgencia: Int,
        val grupo: String,
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

    // Se dispara cuando el usuario redimensiona el widget desde la pantalla de
    // inicio. home_widget no expone un callback propio para esto (solo cubre
    // onUpdate y los clicks interactivos), así que se sobreescribe el método
    // estándar de AppWidgetProvider directamente y se reusa el mismo
    // renderizado, obteniendo los datos guardados con el mismo helper que usa
    // HomeWidgetProvider internamente para su onUpdate.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        renderizarWidget(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
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

        val filasQueCaben = calcularFilasVisibles(appWidgetManager.getAppWidgetOptions(appWidgetId))
        val itemsAMostrar = items.take(filasQueCaben)

        val views = RemoteViews(context.packageName, R.layout.widget_tareas)

        views.setTextViewText(
            R.id.widget_tareas_titulo,
            if (modo == MODO_IMPORTANTES) "Más importantes" else "Próximas",
        )

        for (i in FILA_IDS.indices) {
            val fila = FILA_IDS[i]
            if (i < itemsAMostrar.size) {
                val item = itemsAMostrar[i]
                views.setViewVisibility(fila.contenedor, View.VISIBLE)
                views.setTextViewText(fila.titulo, item.titulo)
                views.setTextViewText(fila.fecha, item.fechaCorta)

                views.setInt(fila.urgenciaDot, "setColorFilter", colorUrgencia(item.urgencia))
                views.setTextViewText(fila.urgenciaLabel, etiquetaUrgencia(item.urgencia))

                views.setInt(fila.grupoDot, "setColorFilter", colorGrupo(item.grupo))
                views.setTextViewText(fila.grupoLabel, item.grupo)
            } else {
                views.setViewVisibility(fila.contenedor, View.GONE)
            }
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

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    // Estima cuántas de las MAX_ITEMS filas pre-construidas en el layout
    // caben en el alto actual del widget, dejando lugar para el encabezado
    // (título + ícono de alternancia) y el padding del contenedor. Cada fila
    // ahora ocupa 2 líneas (nombre+urgencia, fecha+categoría), así que su
    // alto aproximado subió respecto a la versión de una sola línea.
    private fun calcularFilasVisibles(opciones: Bundle): Int {
        val altoDp = opciones.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
            ALTO_MINIMO_POR_DEFECTO_DP,
        )
        val altoParaFilas = altoDp - ALTO_ENCABEZADO_DP - ALTO_PADDING_CONTENEDOR_DP
        if (altoParaFilas <= 0) return MIN_FILAS_VISIBLES
        val filas = altoParaFilas / ALTO_FILA_DP
        return filas.coerceIn(MIN_FILAS_VISIBLES, MAX_ITEMS)
    }

    private fun parseTareas(json: String?): List<ItemTarea> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                ItemTarea(
                    titulo = item.optString("titulo", ""),
                    fechaCorta = formatearFechaCorta(item.optString("fechaLimite", "")),
                    urgencia = item.optInt("urgencia", 1),
                    grupo = item.optString("grupo", "General"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    // Evita depender de parseo estricto de ISO8601 (la longitud de los
    // microsegundos que emite DateTime.toIso8601String() en Dart varía):
    // simplemente toma "yyyy-MM-dd" y "HH:mm" por posición.
    private fun formatearFechaCorta(iso: String): String {
        if (iso.length < 16) return ""
        val fecha = iso.substring(5, 10) // MM-dd
        val hora = iso.substring(11, 16) // HH:mm
        return "$fecha $hora"
    }

    // Misma paleta que TemaApp.clasico usa para _getColorUrgencia en
    // home_screen.dart (teal/azul/naranja/rojo para 1-4): se reutiliza la
    // convención ya existente en la app en vez de inventar una nueva.
    private fun colorUrgencia(urgencia: Int): Int = when (urgencia) {
        1 -> 0xFF009688.toInt() // Colors.teal
        2 -> 0xFF2196F3.toInt() // Colors.blue
        3 -> 0xFFFF9800.toInt() // Colors.orange
        4 -> 0xFFF44336.toInt() // Colors.red
        else -> 0xFF9E9E9E.toInt() // Colors.grey
    }

    private fun etiquetaUrgencia(urgencia: Int): String = when (urgencia) {
        1 -> "Bajo"
        2 -> "Medio"
        3 -> "Alto"
        4 -> "Muy alto"
        else -> "?"
    }

    // No existe ninguna paleta de color por grupo/categoría en el resto de la
    // app (Tarea.grupo es un string libre sin color asociado), así que se
    // deriva un color determinístico a partir del nombre del grupo: el mismo
    // grupo siempre cae en el mismo color, sin necesidad de persistir un
    // mapeo aparte.
    private fun colorGrupo(grupo: String): Int {
        val indice = (grupo.hashCode() and 0x7fffffff) % PALETA_GRUPOS.size
        return PALETA_GRUPOS[indice]
    }

    private data class FilaIds(
        val contenedor: Int,
        val titulo: Int,
        val urgenciaDot: Int,
        val urgenciaLabel: Int,
        val fecha: Int,
        val grupoDot: Int,
        val grupoLabel: Int,
    )

    companion object {
        private const val WIDGET_DATA_PROXIMAS_KEY = "tareas_widget_data_proximas"
        private const val WIDGET_DATA_IMPORTANTES_KEY = "tareas_widget_data_importantes"
        private const val WIDGET_MODO_KEY = "tareas_widget_modo"
        private const val MODO_IMPORTANTES = "importantes"
        private const val MODO_PROXIMAS = "proximas"

        private const val MAX_ITEMS = 6
        private const val MIN_FILAS_VISIBLES = 1
        private const val ALTO_ENCABEZADO_DP = 32
        private const val ALTO_PADDING_CONTENEDOR_DP = 24
        private const val ALTO_FILA_DP = 40
        private const val ALTO_MINIMO_POR_DEFECTO_DP = 110

        private val PALETA_GRUPOS = intArrayOf(
            0xFF8E24AA.toInt(), // purple
            0xFF3949AB.toInt(), // indigo
            0xFF43A047.toInt(), // green
            0xFFFBC02D.toInt(), // yellow
            0xFF6D4C41.toInt(), // brown
            0xFF546E7A.toInt(), // blue grey
            0xFFD81B60.toInt(), // pink
            0xFF00838F.toInt(), // cyan oscuro
        )

        private val FILA_IDS = listOf(
            FilaIds(
                R.id.widget_tareas_fila1,
                R.id.widget_tareas_titulo1,
                R.id.widget_tareas_urgencia_dot1,
                R.id.widget_tareas_urgencia_label1,
                R.id.widget_tareas_fecha1,
                R.id.widget_tareas_grupo_dot1,
                R.id.widget_tareas_grupo_label1,
            ),
            FilaIds(
                R.id.widget_tareas_fila2,
                R.id.widget_tareas_titulo2,
                R.id.widget_tareas_urgencia_dot2,
                R.id.widget_tareas_urgencia_label2,
                R.id.widget_tareas_fecha2,
                R.id.widget_tareas_grupo_dot2,
                R.id.widget_tareas_grupo_label2,
            ),
            FilaIds(
                R.id.widget_tareas_fila3,
                R.id.widget_tareas_titulo3,
                R.id.widget_tareas_urgencia_dot3,
                R.id.widget_tareas_urgencia_label3,
                R.id.widget_tareas_fecha3,
                R.id.widget_tareas_grupo_dot3,
                R.id.widget_tareas_grupo_label3,
            ),
            FilaIds(
                R.id.widget_tareas_fila4,
                R.id.widget_tareas_titulo4,
                R.id.widget_tareas_urgencia_dot4,
                R.id.widget_tareas_urgencia_label4,
                R.id.widget_tareas_fecha4,
                R.id.widget_tareas_grupo_dot4,
                R.id.widget_tareas_grupo_label4,
            ),
            FilaIds(
                R.id.widget_tareas_fila5,
                R.id.widget_tareas_titulo5,
                R.id.widget_tareas_urgencia_dot5,
                R.id.widget_tareas_urgencia_label5,
                R.id.widget_tareas_fecha5,
                R.id.widget_tareas_grupo_dot5,
                R.id.widget_tareas_grupo_label5,
            ),
            FilaIds(
                R.id.widget_tareas_fila6,
                R.id.widget_tareas_titulo6,
                R.id.widget_tareas_urgencia_dot6,
                R.id.widget_tareas_urgencia_label6,
                R.id.widget_tareas_fecha6,
                R.id.widget_tareas_grupo_dot6,
                R.id.widget_tareas_grupo_label6,
            ),
        )
    }
}
