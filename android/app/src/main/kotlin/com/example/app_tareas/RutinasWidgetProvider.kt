package com.example.app_tareas

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class RutinasWidgetProvider : HomeWidgetProvider() {
    private data class ItemRutina(
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

    // Mismo mecanismo que TareasWidgetProvider: home_widget no expone un
    // callback propio para el resize, así que se sobreescribe el método
    // estándar de AppWidgetProvider directamente.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        renderizarWidget(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    // Todo el cuerpo va envuelto en try-catch con logging detallado y una
    // validación previa (validarRemoteViews) que aplica el RemoteViews en el
    // propio proceso antes de enviarlo al widget host — el mismo blindaje que
    // ya usa TareasWidgetProvider, aplicado acá desde el primer intento tras
    // el incidente del <View> plano no soportado.
    private fun renderizarWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences,
    ) {
        try {
            // --- Etapa 1: dato crudo tal cual llega de SharedPreferences ---
            val json = widgetData.getString(WIDGET_DATA_KEY, null)
            Log.d(TAG, "[1/4] appWidgetId=$appWidgetId JSON crudo en '$WIDGET_DATA_KEY': $json")

            // --- Etapa 2: parseo del JSON a la lista completa de items ---
            val items = parseRutinas(json)
            Log.d(TAG, "[2/4] items parseados: ${items.size} -> ${items.map { it.titulo }}")

            // --- Etapa 3: cuántas filas caben según el tamaño actual del widget ---
            val opciones = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val altoDp = opciones.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, ALTO_MINIMO_POR_DEFECTO_DP)
            val filasQueCaben = calcularFilasVisibles(altoDp)
            Log.d(TAG, "[3/4] altoDp=$altoDp -> filasQueCaben=$filasQueCaben")

            // --- Etapa 4: recorte final a lo que realmente se va a mostrar ---
            val itemsAMostrar = items.take(filasQueCaben)
            Log.d(TAG, "[4/4] items a mostrar: ${itemsAMostrar.size} -> ${itemsAMostrar.map { it.titulo }}")

            val views = RemoteViews(context.packageName, R.layout.widget_rutinas)

            for (i in FILA_IDS.indices) {
                val fila = FILA_IDS[i]
                if (i >= itemsAMostrar.size) {
                    views.setViewVisibility(fila.contenedor, View.GONE)
                    continue
                }
                // Try-catch por fila: si una rutina puntual tiene un dato que
                // rompe el render, no debe tumbar a las demás filas.
                try {
                    val item = itemsAMostrar[i]
                    views.setViewVisibility(fila.contenedor, View.VISIBLE)
                    views.setTextViewText(fila.titulo, item.titulo)
                    views.setTextViewText(fila.hora, item.horaHoy)

                    val color = when {
                        item.completada -> COLOR_COMPLETADA
                        item.omitida -> COLOR_OMITIDA
                        else -> COLOR_PENDIENTE
                    }
                    val etiqueta = when {
                        item.completada -> "Hecha"
                        item.omitida -> "Omitida"
                        else -> "Pendiente"
                    }
                    views.setInt(fila.estadoDot, "setColorFilter", color)
                    views.setTextViewText(fila.estadoLabel, etiqueta)
                    views.setTextColor(fila.estadoLabel, color)
                } catch (e: Throwable) {
                    Log.e(TAG, "Error construyendo la fila $i (${itemsAMostrar.getOrNull(i)}): ${e.message}", e)
                    views.setViewVisibility(fila.contenedor, View.GONE)
                }
            }

            views.setViewVisibility(
                R.id.widget_rutinas_vacio,
                if (itemsAMostrar.isEmpty()) View.VISIBLE else View.GONE,
            )

            // La inflación real ocurre en el proceso del widget host: sin este
            // paso, una vista no soportada o un ID mal referenciado fallaría en
            // silencio ahí y el widget caería en el "Problema al cargar el
            // widget" genérico, sin nada útil en Logcat.
            validarRemoteViews(context, views)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Throwable) {
            Log.e(
                TAG,
                "Error al renderizar RutinasWidgetProvider (appWidgetId=$appWidgetId): ${e.message}",
                e,
            )
            renderizarFallbackSeguro(context, appWidgetManager, appWidgetId)
        }
    }

    private fun validarRemoteViews(context: Context, views: RemoteViews) {
        views.apply(context, FrameLayout(context))
    }

    private fun renderizarFallbackSeguro(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        try {
            val views = RemoteViews(context.packageName, R.layout.widget_rutinas)
            for (fila in FILA_IDS) {
                views.setViewVisibility(fila.contenedor, View.GONE)
            }
            views.setViewVisibility(R.id.widget_rutinas_vacio, View.VISIBLE)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Throwable) {
            Log.e(TAG, "El fallback seguro también falló (appWidgetId=$appWidgetId): ${e.message}", e)
        }
    }

    // Mismo criterio que TareasWidgetProvider.calcularFilasVisibles, ajustado
    // a un encabezado más bajo (acá no hay ícono de alternancia, solo el
    // título "Rutinas de hoy").
    private fun calcularFilasVisibles(altoDp: Int): Int {
        val altoParaFilas = altoDp - ALTO_ENCABEZADO_DP - ALTO_PADDING_CONTENEDOR_DP
        if (altoParaFilas <= 0) return MIN_FILAS_VISIBLES
        val filas = altoParaFilas / ALTO_FILA_DP
        return filas.coerceIn(MIN_FILAS_VISIBLES, MAX_ITEMS)
    }

    private fun parseRutinas(json: String?): List<ItemRutina> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                ItemRutina(
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

    private data class FilaIds(
        val contenedor: Int,
        val titulo: Int,
        val estadoDot: Int,
        val estadoLabel: Int,
        val hora: Int,
    )

    companion object {
        private const val TAG = "RutinasWidgetProvider"
        private const val WIDGET_DATA_KEY = "rutinas_widget_data"

        private const val MAX_ITEMS = 6
        private const val MIN_FILAS_VISIBLES = 1
        // +2dp vs. la versión anterior: el título ahora usa el color de
        // acento (mismo tamaño de texto), sin cambio real de alto.
        private const val ALTO_ENCABEZADO_DP = 20
        // El padding del contenedor subió de 6dp a 10dp por lado para la
        // tarjeta redondeada (widget_background) -> 20dp total en vez de 12dp.
        private const val ALTO_PADDING_CONTENEDOR_DP = 20
        // Filas de una sola línea (título + hora + estado): se mantienen
        // deliberadamente compactas (solo +1dp de marginTop vs. la versión
        // anterior) para no perder el "al menos 5 rutinas visibles" ya
        // logrado en un widget colocado de ~124dp de alto real.
        private const val ALTO_FILA_DP = 19
        private const val ALTO_MINIMO_POR_DEFECTO_DP = 110

        // Paleta propia para estado (completada/pendiente/omitida), distinta
        // de la de urgencia (rojo/ámbar/naranja/rojo) usada en
        // TareasWidgetProvider, para no mezclar significados entre widgets.
        // COLOR_OMITIDA usa el mismo tono ámbar que colorOmitidaRutina en el
        // lado Flutter (progreso_rutinas_bar.dart / rutina_card.dart), para
        // que "omitida" signifique lo mismo en toda la app.
        private val COLOR_COMPLETADA = 0xFF4CAF50.toInt() // verde
        private val COLOR_PENDIENTE = 0xFF9E9E9E.toInt() // gris
        private val COLOR_OMITIDA = 0xFFF59E0B.toInt() // ámbar

        private val FILA_IDS = listOf(
            FilaIds(
                R.id.widget_rutinas_fila1,
                R.id.widget_rutinas_titulo1,
                R.id.widget_rutinas_estado_dot1,
                R.id.widget_rutinas_estado_label1,
                R.id.widget_rutinas_hora1,
            ),
            FilaIds(
                R.id.widget_rutinas_fila2,
                R.id.widget_rutinas_titulo2,
                R.id.widget_rutinas_estado_dot2,
                R.id.widget_rutinas_estado_label2,
                R.id.widget_rutinas_hora2,
            ),
            FilaIds(
                R.id.widget_rutinas_fila3,
                R.id.widget_rutinas_titulo3,
                R.id.widget_rutinas_estado_dot3,
                R.id.widget_rutinas_estado_label3,
                R.id.widget_rutinas_hora3,
            ),
            FilaIds(
                R.id.widget_rutinas_fila4,
                R.id.widget_rutinas_titulo4,
                R.id.widget_rutinas_estado_dot4,
                R.id.widget_rutinas_estado_label4,
                R.id.widget_rutinas_hora4,
            ),
            FilaIds(
                R.id.widget_rutinas_fila5,
                R.id.widget_rutinas_titulo5,
                R.id.widget_rutinas_estado_dot5,
                R.id.widget_rutinas_estado_label5,
                R.id.widget_rutinas_hora5,
            ),
            FilaIds(
                R.id.widget_rutinas_fila6,
                R.id.widget_rutinas_titulo6,
                R.id.widget_rutinas_estado_dot6,
                R.id.widget_rutinas_estado_label6,
                R.id.widget_rutinas_hora6,
            ),
        )
    }
}
