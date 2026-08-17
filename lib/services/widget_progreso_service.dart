import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tarea.dart';
import 'widget_rutinas_service.dart';

// Recalcula y publica los totales de Tareas que necesita el widget de
// Progreso (Chico y Grande), restringidos a las tareas con fechaLimite de
// HOY — a diferencia del widget de Tareas (que muestra TODAS las
// pendientes, sin importar la fecha), acá "Tareas X/Y" solo debe reflejar
// lo que corresponde al día actual. Los totales de Rutinas NO se recalculan acá:
// WidgetRutinasService ya los publica bajo 'rutinas_widget_total_programadas'
// / 'rutinas_widget_total_hechas' cada vez que corre, y
// ProgresoWidgetProviderChico/Grande los lee directamente de ahí (ver
// ProgresoWidgetCommon.kt) — este servicio solo aporta la mitad de Tareas y
// dispara el repintado de ambas variantes, sea cual sea el dato que cambió.
//
// Se llama junto a WidgetTareasService.actualizar() (tras un cambio en
// tareas), junto a WidgetRutinasService.actualizar() (tras un cambio en
// rutinas, para que el anillo de Progreso recoja el nuevo total aunque
// Tareas no haya cambiado), desde el WidgetsBindingObserver de main.dart al
// pasar la app a segundo plano, y desde [progresoWidgetBackgroundCallback]
// cuando se toca el botón de refresco del widget.
class WidgetProgresoService {
  static const String _tareasStorageKey = 'lista_tareas_v1';
  static const String _widgetTareasTotalKey = 'progreso_widget_tareas_total';
  static const String _widgetTareasCompletadasKey = 'progreso_widget_tareas_completadas';
  static const List<String> _androidWidgetNames = [
    'ProgresoWidgetProviderChico',
    'ProgresoWidgetProviderGrande',
  ];

  static Future<void> actualizar() async {
    try {
      // Mismo motivo que en WidgetTareasService/WidgetRutinasService: sin
      // el reload() explícito este servicio podría ver una foto vieja de
      // las tareas si corre en un isolate distinto al que hizo la última
      // escritura (isolate headless del botón de refresco).
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final tareasJson = prefs.getString(_tareasStorageKey);

      final List<Tarea> tareas;
      if (tareasJson == null) {
        tareas = [];
      } else {
        final decodificado = jsonDecode(tareasJson) as List;
        tareas = decodificado.map((item) => Tarea.fromJson(item as Map<String, dynamic>)).toList();
      }

      // Solo cuentan las tareas con fecha límite de HOY (no "todas las
      // pendientes", que es lo que ya muestra el widget de Tareas): una
      // tarea sin fechaLimite, o con fechaLimite de otro día, no es "del día
      // actual" y no debe sumar ni al total ni a las completadas del anillo.
      final tareasDeHoy = tareas.where((t) => _esHoy(t.fechaLimite)).toList();
      // Una tarea recurrente completada HOY ya no tiene fechaLimite de hoy
      // (avanzó a la próxima ocurrencia vía TareaNotifier.toggleTarea, que
      // nunca la deja en esCompletada=true) — sin contarla aparte, el
      // anillo de Progreso bajaría en vez de subir al completarla.
      final recurrentesCompletadasHoy = tareas
          .where((t) => t.tipoRecurrencia != TipoRecurrencia.ninguna && _esHoy(t.fechaLimiteAnterior))
          .toList();
      final total = tareasDeHoy.length + recurrentesCompletadasHoy.length;
      final completadas = tareasDeHoy.where((t) => t.esCompletada).length + recurrentesCompletadasHoy.length;

      await HomeWidget.saveWidgetData<String>(_widgetTareasTotalKey, total.toString());
      await HomeWidget.saveWidgetData<String>(_widgetTareasCompletadasKey, completadas.toString());
      for (final nombre in _androidWidgetNames) {
        await HomeWidget.updateWidget(androidName: nombre);
      }

      // ignore: avoid_print
      print('WidgetProgresoService.actualizar: tareas=$completadas/$total');
    } catch (e) {
      // No queremos que un fallo al sincronizar el widget rompa el flujo
      // normal de la app.
      // ignore: avoid_print
      print('WidgetProgresoService.actualizar: error al sincronizar -> $e');
    }
  }

  static bool _esHoy(DateTime? fecha) {
    if (fecha == null) return false;
    final hoy = DateTime.now();
    return fecha.year == hoy.year && fecha.month == hoy.month && fecha.day == hoy.day;
  }
}

// Entry point ejecutado en un isolate headless cuando se toca el botón de
// refresco del widget de Progreso (Chico o Grande). Debe ser una función de
// nivel superior (no un closure) para que PluginUtilities.getCallbackHandle
// pueda ubicarla (mismo patrón que tareasWidgetBackgroundCallback). Refresca
// AMBAS mitades del resumen (no solo Tareas, que es lo único que este
// servicio recalcula) porque "refrescar" desde el widget debe traer los
// datos más al día posibles de las dos fuentes.
@pragma('vm:entry-point')
Future<void> progresoWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'refrescar_progreso') return;
  await WidgetRutinasService.actualizar();
  await WidgetProgresoService.actualizar();
}
