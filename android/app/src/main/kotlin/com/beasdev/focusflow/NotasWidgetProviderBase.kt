package com.beasdev.focusflow

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.util.TypedValue
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

// Ids de una tarjeta de nota dentro del layout. Cada subclase concreta
// (NotasWidgetProviderChico/Grande) arma su propia lista con los ids que
// declara SU layout, mismo motivo que FilaRutinaIds en
// RutinasWidgetProviderBase.
data class NotaCardIds(
    val contenedor: Int,
    val titulo: Int,
    val cuerpo: Int,
    val tiempo: Int,
)

// Base compartida por NotasWidgetProviderChico y NotasWidgetProviderGrande.
// A diferencia de Rutinas, ambas variantes muestran EXACTAMENTE el mismo par
// de notas (WidgetNotasService.actualizar() publica una sola clave para las
// dos) — solo cambia cuánto texto entra por tarjeta según el layout.
// Tocar una tarjeta puntual abre esa nota directamente (ver 'abrir_nota' en
// main.dart); tocar el resto de la superficie lleva a la pantalla de Notas
// sin abrir ninguna en particular. El botón "+ Nueva nota" en cambio abre de
// una vez el formulario de creación de la app.
abstract class NotasWidgetProviderBase(
    private val layoutResId: Int,
    private val cardIds: List<NotaCardIds>,
) : HomeWidgetProvider() {
    private data class ItemNota(
        val id: String,
        val titulo: String,
        val texto: String,
        val tiempoRelativo: String,
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
            val items = parseNotas(widgetData.getString(WIDGET_DATA_KEY, null))
            val hayNotas = items.isNotEmpty()
            val itemsAMostrar = items.take(cardIds.size)
            // Chico solo declara 2 NotaCardIds en su layout, así que acá
            // arriba ya quedó recortado a como mucho 2 aunque el widget
            // Grande esté en modo "4 notas" y el JSON traiga 4 — no hace
            // falta que Chico sepa nada del modo de Grande. Grande sí puede
            // llegar a 3-4: en ese caso cada tarjeta usa menos texto/tamaño
            // de letra para que las 4 quepan sin desbordar su mitad de fila
            // (ver widget_notas_fila_inferior más abajo).
            val compacto = itemsAMostrar.size > 2

            val views = RemoteViews(context.packageName, layoutResId)

            for (i in cardIds.indices) {
                val card = cardIds[i]
                if (i >= itemsAMostrar.size) {
                    views.setViewVisibility(card.contenedor, View.GONE)
                    continue
                }
                // Try-catch por tarjeta: una nota puntual con datos corruptos
                // no debe tumbar a la otra (mismo blindaje que Rutinas).
                try {
                    val item = itemsAMostrar[i]
                    views.setViewVisibility(card.contenedor, View.VISIBLE)

                    // Si la nota no tiene título propio, el renglón de
                    // título se oculta por completo (en vez de rellenarlo
                    // con el texto) para que el cuerpo pueda usar TODO el
                    // alto de la tarjeta en vez de mostrar una sola línea
                    // truncada y esconder el resto de la nota.
                    val tieneTitulo = item.titulo.isNotEmpty()
                    views.setViewVisibility(card.titulo, if (tieneTitulo) View.VISIBLE else View.GONE)
                    if (tieneTitulo) {
                        views.setTextViewText(card.titulo, item.titulo)
                        views.setTextViewTextSize(
                            card.titulo,
                            TypedValue.COMPLEX_UNIT_SP,
                            if (compacto) 13f else 14f,
                        )
                    }
                    views.setViewVisibility(card.cuerpo, View.VISIBLE)
                    views.setTextViewText(card.cuerpo, item.texto)
                    views.setTextViewTextSize(
                        card.cuerpo,
                        TypedValue.COMPLEX_UNIT_SP,
                        if (compacto) 11f else 12f,
                    )
                    // Con 4 tarjetas cada una tiene la mitad del alto de
                    // cuando son 2 (misma cantidad de columnas, el doble de
                    // filas): 4 líneas en vez de 12 evita que el texto se
                    // desborde por debajo de su mitad de fila y se pise con
                    // la de abajo (RemoteViews no recorta hijos que piden
                    // más alto del que su padre les dio).
                    views.setInt(card.cuerpo, "setMaxLines", if (compacto) 4 else 12)

                    views.setViewVisibility(card.tiempo, if (item.tiempoRelativo.isEmpty()) View.GONE else View.VISIBLE)
                    views.setTextViewText(card.tiempo, item.tiempoRelativo)

                    // Propio de esta tarjeta (no de la raíz): abre la app
                    // directo en ESTA nota en vez de solo llevar a la
                    // pestaña Notas. Al tener su propio PendingIntent, el
                    // click ya no burbujea hacia widget_notas_root.
                    val abrirNotaPendingIntent = HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("homewidget://abrir_nota?id=${Uri.encode(item.id)}"),
                    )
                    views.setOnClickPendingIntent(card.contenedor, abrirNotaPendingIntent)
                } catch (e: Throwable) {
                    views.setViewVisibility(card.contenedor, View.GONE)
                }
            }

            views.setViewVisibility(R.id.widget_notas_contenido, if (hayNotas) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_notas_vacio, if (hayNotas) View.GONE else View.VISIBLE)
            // Solo existe en el layout Grande (fila3/fila4, modo "4
            // notas"); en Chico este id no está en el árbol y la visibilidad
            // simplemente no se aplica a nada.
            views.setViewVisibility(R.id.widget_notas_fila_inferior, if (compacto) View.VISIBLE else View.GONE)
            // Solo existe en el layout Grande (botón "+ Nueva nota" del
            // header); en Chico este id no está en el árbol de vistas y la
            // acción simplemente no hace nada al aplicarse.
            views.setViewVisibility(R.id.widget_notas_nueva_header, if (hayNotas) View.VISIBLE else View.GONE)

            val abrirNotasPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("homewidget://abrir_notas"),
            )
            views.setOnClickPendingIntent(R.id.widget_notas_root, abrirNotasPendingIntent)
            // Los distintos botones "+ Nueva nota" (uno fijo en Chico, uno en
            // el header y otro en el estado vacío de Grande) abren de una vez
            // el formulario de creación (ver 'nueva_nota' en main.dart), en
            // vez de solo llevar a la pantalla de Notas como el resto del
            // widget. Un id que no exista en el layout actual simplemente no
            // recibe nada.
            val nuevaNotaPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("homewidget://nueva_nota"),
            )
            views.setOnClickPendingIntent(R.id.widget_notas_nueva, nuevaNotaPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_notas_nueva_header, nuevaNotaPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_notas_nueva_vacio, nuevaNotaPendingIntent)

            // Botón de alternancia 2/4 notas (solo existe en el layout
            // Grande): a diferencia de "abrir la app", esto corre headless
            // vía HomeWidgetBackgroundIntent — mismo patrón que el toggle de
            // Tareas — y captura el click antes de que llegue a la raíz, así
            // que tocar el ícono cambia la cantidad sin abrir la app, y
            // tocar el resto del widget sigue abriendo Notas como siempre.
            val toggleCantidadPendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("homewidget://toggle_cantidad_notas"),
            )
            views.setOnClickPendingIntent(R.id.widget_notas_toggle_cantidad, toggleCantidadPendingIntent)

            // La inflación real ocurre en el proceso del widget host: sin
            // este paso, una vista no soportada o un ID mal referenciado
            // fallaría en silencio ahí (mismo blindaje que Rutinas/Tareas).
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
            for (card in cardIds) {
                views.setViewVisibility(card.contenedor, View.GONE)
            }
            views.setViewVisibility(R.id.widget_notas_contenido, View.GONE)
            views.setViewVisibility(R.id.widget_notas_fila_inferior, View.GONE)
            views.setViewVisibility(R.id.widget_notas_nueva_header, View.GONE)
            views.setViewVisibility(R.id.widget_notas_vacio, View.VISIBLE)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Throwable) {
            // Si el fallback también falla, no queda más blindaje posible acá.
        }
    }

    private fun parseNotas(json: String?): List<ItemNota> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                ItemNota(
                    id = item.optString("id", ""),
                    titulo = item.optString("titulo", ""),
                    texto = item.optString("texto", ""),
                    tiempoRelativo = item.optString("tiempoRelativo", ""),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    companion object {
        private const val WIDGET_DATA_KEY = "notas_widget_data"
    }
}
