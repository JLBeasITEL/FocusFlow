package com.beasdev.focusflow

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import androidx.core.content.ContextCompat
import java.time.LocalDate

// Ámbar de estado "omitida", MISMO valor que colorOmitidaRutina (lib/core/
// colores_estado_rutina.dart) y que COLOR_OMITIDA en
// RutinasWidgetProviderBase.kt — si se cambia acá, cambiar en los otros dos
// para que "omitida" siga significando el mismo color en toda la app.
private val COLOR_OMITIDA_RAYAS = 0xFFF59E0B.toInt()

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
    // Cuántas de rutinasHechas son en realidad omitidas (pagadas con
    // moneda), no completadas de verdad — necesario para pintar ese tramo
    // distinto en el anillo/barra (ver dibujarAnilloProgreso/dibujarBarraProgreso).
    val rutinasOmitidas: Int,
) {
    val tareasPendientes: Int get() = (tareasTotal - tareasCompletadas).coerceAtLeast(0)
    val rutinasPendientes: Int get() = (rutinasTotal - rutinasHechas).coerceAtLeast(0)
    val tareasPorcentaje: Int get() = if (tareasTotal > 0) (tareasCompletadas * 100) / tareasTotal else 0
    val rutinasPorcentaje: Int get() = if (rutinasTotal > 0) (rutinasHechas * 100) / rutinasTotal else 0
    // Sub-tramo de rutinasPorcentaje que corresponde a omitidas, en vez de a
    // completadas reales — mismo denominador (rutinasTotal) que rutinasPorcentaje,
    // para que ambos sean directamente comparables como sweep/ancho de un mismo arco/barra.
    val rutinasOmitidoPorcentaje: Int get() = if (rutinasTotal > 0) (rutinasOmitidas * 100) / rutinasTotal else 0
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
        rutinasOmitidas = widgetData.getString("rutinas_widget_total_omitidas", null)?.toIntOrNull() ?: 0,
    )
}

// Dibuja un anillo de progreso (fondo gris claro + arco de color, empezando
// arriba y avanzando en sentido horario) como Bitmap: RemoteViews no tiene
// ninguna vista nativa para un donut/pie chart — un ProgressBar circular
// estándar es solo un spinner indeterminado, no admite porcentaje.
//
// progresoOmitidoPorcentaje (opcional, 0 por defecto): sub-tramo FINAL de
// progresoPorcentaje que en vez de pintarse sólido se pinta rayado en
// ámbar — mismo lenguaje visual que ProgresoRutinasBar (Dart, pantalla de
// Rutinas) para el tramo "omitida, pagada con moneda". El anillo de Tareas
// no tiene concepto de omitida, así que sigue llamando a esta función sin
// pasar este parámetro.
fun dibujarAnilloProgreso(
    context: Context,
    diametroDp: Int,
    grosorDp: Float,
    progresoPorcentaje: Int,
    colorProgreso: Int,
    colorFondo: Int = ContextCompat.getColor(context, R.color.widget_progress_vacio),
    progresoOmitidoPorcentaje: Int = 0,
    colorOmitido: Int = COLOR_OMITIDA_RAYAS,
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
    // El tramo omitido nunca puede superar al total (defensivo ante datos
    // inconsistentes que pudieran llegar del lado Dart).
    val omitidoClamp = progresoOmitidoPorcentaje.coerceIn(0, progresoClamp)
    if (progresoClamp > 0) {
        val sweepTotal = 360f * (progresoClamp / 100f)
        val sweepOmitido = 360f * (omitidoClamp / 100f)
        val sweepCompletado = sweepTotal - sweepOmitido
        // Empieza arriba (-90°) y avanza en sentido horario, como en los
        // mockups: primero el tramo sólido (completado real), luego —
        // inmediatamente después, sin hueco, igual que los Expanded en
        // ProgresoRutinasBar (Dart)— el tramo rayado (omitido).
        if (sweepCompletado > 0f) {
            paint.color = colorProgreso
            canvas.drawArc(rect, -90f, sweepCompletado, false, paint)
        }
        if (sweepOmitido > 0f) {
            dibujarArcoRayado(canvas, rect, grosorPx, -90f + sweepCompletado, sweepOmitido, colorOmitido, density)
        }
    }

    return bitmap
}

// Tramo rayado de un arco: RemoteViews/XML no admite un patrón de rayas
// declarativo (ver discusión en la auditoría — un <clip> solo pinta un
// color sólido), así que se pinta con Canvas usando una capa (saveLayer) +
// PorterDuff.SRC_IN: primero se dibuja el propio arco como "máscara" (relleno
// suave, alpha 0.35, igual que el fondo del segmento en Dart), y encima se
// dibujan líneas diagonales a 45° que SRC_IN recorta exactamente a la forma
// de esa máscara — el resultado es el mismo arco, pero con rayas en vez de
// sólido. Mismos parámetros que _RayasDiagonalesPainter (Dart): grosor 3dp,
// espaciado 7dp, alpha 0.35/0.9, escalados por densidad como el resto de
// este archivo.
private fun dibujarArcoRayado(
    canvas: Canvas,
    rect: RectF,
    grosorPx: Float,
    anguloInicio: Float,
    sweep: Float,
    colorBase: Int,
    densidad: Float,
) {
    val r = Color.red(colorBase)
    val g = Color.green(colorBase)
    val b = Color.blue(colorBase)

    val layerRect = RectF(rect.left - grosorPx, rect.top - grosorPx, rect.right + grosorPx, rect.bottom + grosorPx)
    val saveCount = canvas.saveLayer(layerRect, null)

    val paintMascara = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = grosorPx
        // BUTT (no ROUND): una punta redondeada invadiría visualmente el
        // tramo sólido vecino en el límite entre ambos.
        strokeCap = Paint.Cap.BUTT
        color = Color.argb(89, r, g, b) // 0.35 * 255 ≈ 89
    }
    canvas.drawArc(rect, anguloInicio, sweep, false, paintMascara)

    val paintRayas = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(230, r, g, b) // 0.9 * 255 ≈ 230
        strokeWidth = 3f * densidad
        xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
    }
    val espaciado = 7f * densidad
    val alto = layerRect.height()
    var x = layerRect.left - alto
    while (x < layerRect.right + alto) {
        canvas.drawLine(x, layerRect.bottom, x + alto, layerRect.top, paintRayas)
        x += espaciado
    }

    canvas.restoreToCount(saveCount)
}

// Equivalente lineal de dibujarAnilloProgreso: una barra horizontal con
// esquinas redondeadas (fondo + tramo completado sólido + tramo omitido
// rayado), como Bitmap. Necesaria porque las barras de Rutinas (widget de
// Progreso Chico y widget de Rutinas Grande) son ProgressBar de ancho
// variable (match_parent / 0dp+weight, según el host), no un contenedor de
// tamaño fijo en dp como el FrameLayout del anillo — por eso el ImageView
// que la reemplaza usa scaleType="fitXY": este Bitmap se genera a una
// resolución interna fija (anchoDp) y Android lo estira horizontalmente
// para llenar el ancho real que le dé el launcher. Con una barra tan chata
// (6dp de alto) el estiramiento horizontal no es perceptible en la práctica.
fun dibujarBarraProgreso(
    context: Context,
    anchoDp: Int,
    altoDp: Int,
    progresoPorcentaje: Int,
    colorProgreso: Int,
    colorFondo: Int,
    progresoOmitidoPorcentaje: Int = 0,
    colorOmitido: Int = COLOR_OMITIDA_RAYAS,
): Bitmap {
    val density = context.resources.displayMetrics.density
    val anchoPx = (anchoDp * density).toInt().coerceAtLeast(1)
    val altoPx = (altoDp * density).toInt().coerceAtLeast(1)
    val radioPx = altoPx / 2f

    val bitmap = Bitmap.createBitmap(anchoPx, altoPx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    val paintFondo = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = colorFondo }
    canvas.drawRoundRect(RectF(0f, 0f, anchoPx.toFloat(), altoPx.toFloat()), radioPx, radioPx, paintFondo)

    val progresoClamp = progresoPorcentaje.coerceIn(0, 100)
    val omitidoClamp = progresoOmitidoPorcentaje.coerceIn(0, progresoClamp)
    if (progresoClamp <= 0) return bitmap

    val anchoTotalPx = anchoPx * (progresoClamp / 100f)
    val anchoOmitidoPx = anchoPx * (omitidoClamp / 100f)
    val anchoCompletadoPx = anchoTotalPx - anchoOmitidoPx

    // Recorte al rectángulo redondeado del progreso completo (no del
    // bitmap entero): mismo motivo que el ClipRRect exterior en
    // ProgresoRutinasBar (Dart) — sin esto, el tramo completado (un
    // rectángulo recto) sobresaldría con esquinas cuadradas por fuera del
    // fondo redondeado en el extremo izquierdo.
    val saveCount = canvas.save()
    val clipPath = Path().apply {
        addRoundRect(RectF(0f, 0f, anchoTotalPx, altoPx.toFloat()), radioPx, radioPx, Path.Direction.CW)
    }
    canvas.clipPath(clipPath)

    if (anchoCompletadoPx > 0f) {
        canvas.drawRect(0f, 0f, anchoCompletadoPx, altoPx.toFloat(), Paint(Paint.ANTI_ALIAS_FLAG).apply { color = colorProgreso })
    }
    if (anchoOmitidoPx > 0f) {
        dibujarSegmentoRayado(canvas, anchoCompletadoPx, altoPx.toFloat(), anchoTotalPx, colorOmitido, density)
    }
    canvas.restoreToCount(saveCount)

    return bitmap
}

// Tramo rayado de una barra recta: a diferencia del arco, el segmento YA es
// un rectángulo, así que alcanza con un clipRect (sin la capa SRC_IN que
// necesita el arco) — mismos parámetros que _RayasDiagonalesPainter (Dart).
private fun dibujarSegmentoRayado(
    canvas: Canvas,
    inicioPx: Float,
    altoPx: Float,
    finPx: Float,
    colorBase: Int,
    densidad: Float,
) {
    val r = Color.red(colorBase)
    val g = Color.green(colorBase)
    val b = Color.blue(colorBase)

    val saveCount = canvas.save()
    canvas.clipRect(inicioPx, 0f, finPx, altoPx)

    canvas.drawRect(inicioPx, 0f, finPx, altoPx, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(89, r, g, b) })

    val paintRayas = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(230, r, g, b)
        strokeWidth = 3f * densidad
    }
    val espaciado = 7f * densidad
    var x = inicioPx - altoPx
    while (x < finPx + altoPx) {
        canvas.drawLine(x, altoPx, x + altoPx, 0f, paintRayas)
        x += espaciado
    }

    canvas.restoreToCount(saveCount)
}

// "(N omitida)"/"(N omitidas)", o cadena vacía si no hay ninguna — mismo
// texto que el "(N omitida)" junto al porcentaje en ProgresoRutinasBar
// (Dart). Se agrega como sufijo a la fracción "X/Y" en vez de al texto de
// porcentaje dentro del anillo: ese texto vive en un círculo de 58dp con
// letra de 13sp, sin espacio para un sufijo sin desbordarse.
fun sufijoOmitidas(omitidas: Int): String {
    if (omitidas <= 0) return ""
    return " ($omitidas omitida${if (omitidas == 1) "" else "s"})"
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
