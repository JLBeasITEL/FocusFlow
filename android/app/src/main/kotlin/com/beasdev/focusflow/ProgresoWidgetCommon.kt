package com.beasdev.focusflow

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.content.ContextCompat
import java.time.LocalDate

// Datos y utilidades compartidas por ProgresoWidgetProviderChico/Grande. A
// diferencia de Rutinas/Tareas/Notas, acá no hace falta una clase base con
// herencia: Chico y Grande difieren en ESTRUCTURA (un anillo + fila compacta
// de Rutinas vs. dos tarjetas con anillo lado a lado), no solo en cuántas
// filas de una misma tarjeta entran. Compartir la lectura de datos y el
// dibujo del anillo alcanza.
data class ProgresoResumen(
    val tareasTotal: Int,
    val tareasCompletadas: Int,
    val rutinasTotal: Int,
    val rutinasHechas: Int,
) {
    val tareasPendientes: Int get() = (tareasTotal - tareasCompletadas).coerceAtLeast(0)
    val rutinasPendientes: Int get() = (rutinasTotal - rutinasHechas).coerceAtLeast(0)
    val tareasPorcentaje: Int get() = if (tareasTotal > 0) (tareasCompletadas * 100) / tareasTotal else 0
    val rutinasPorcentaje: Int get() = if (rutinasTotal > 0) (rutinasHechas * 100) / rutinasTotal else 0
}

fun leerProgresoResumen(widgetData: SharedPreferences): ProgresoResumen {
    return ProgresoResumen(
        // Publicados por WidgetProgresoService.actualizar() (lib/services/
        // widget_progreso_service.dart), la única mitad de datos que no
        // tenía ya un servicio propio.
        tareasTotal = widgetData.getString("progreso_widget_tareas_total", null)?.toIntOrNull() ?: 0,
        tareasCompletadas = widgetData.getString("progreso_widget_tareas_completadas", null)?.toIntOrNull() ?: 0,
        // Mismas claves que ya publica WidgetRutinasService.actualizar() para
        // RutinasWidgetProviderChico/Grande: se leen directamente en vez de
        // duplicarlas bajo un nombre propio (ver RutinasWidgetProviderBase).
        rutinasTotal = widgetData.getString("rutinas_widget_total_programadas", null)?.toIntOrNull() ?: 0,
        rutinasHechas = widgetData.getString("rutinas_widget_total_hechas", null)?.toIntOrNull() ?: 0,
    )
}

// Dibuja un anillo de progreso (fondo gris claro + arco de color, empezando
// arriba y avanzando en sentido horario) como Bitmap: RemoteViews no tiene
// ninguna vista nativa para un donut/pie chart — un ProgressBar circular
// estándar es solo un spinner indeterminado, no admite porcentaje.
fun dibujarAnilloProgreso(
    context: Context,
    diametroDp: Int,
    grosorDp: Float,
    progresoPorcentaje: Int,
    colorProgreso: Int,
    colorFondo: Int = ContextCompat.getColor(context, R.color.widget_progress_vacio),
): Bitmap {
    val density = context.resources.displayMetrics.density
    val diametroPx = (diametroDp * density).toInt().coerceAtLeast(1)
    val grosorPx = grosorDp * density

    val bitmap = Bitmap.createBitmap(diametroPx, diametroPx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = grosorPx
        strokeCap = Paint.Cap.ROUND
    }

    val inset = grosorPx / 2f
    val rect = RectF(inset, inset, diametroPx - inset, diametroPx - inset)

    paint.color = colorFondo
    canvas.drawArc(rect, 0f, 360f, false, paint)

    val progresoClamp = progresoPorcentaje.coerceIn(0, 100)
    if (progresoClamp > 0) {
        paint.color = colorProgreso
        val sweep = 360f * (progresoClamp / 100f)
        // Empieza arriba (-90°) y avanza en sentido horario, como en los mockups.
        canvas.drawArc(rect, -90f, sweep, false, paint)
    }

    return bitmap
}

// Texto "N rutina(s)/tarea(s) pendiente(s)" con pluralización, o un texto
// alternativo cuando no queda ninguna pendiente. Compartido por Chico y
// Grande para no repetir la misma lógica de plural en cada uno.
fun textoPendientes(cantidad: Int, singular: String, plural: String, sinPendientes: String): String {
    if (cantidad == 0) return sinPendientes
    return "$cantidad ${if (cantidad == 1) singular else plural}"
}

// Nombres en español a mano (no vía Locale.forLanguageTag/TextStyle) para no
// depender de qué datos de localización tenga cargados el host del widget —
// mismo criterio que WidgetRutinasService._formatearHora en el lado Dart,
// que tampoco delega en formateo dependiente de locale. Compartido por
// Chico (que además agrega día/mes) y Grande (que solo necesita el día).
private val NOMBRES_DIAS = listOf("Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo")

fun diaDeSemanaLegible(): String = NOMBRES_DIAS[LocalDate.now().dayOfWeek.value - 1]
