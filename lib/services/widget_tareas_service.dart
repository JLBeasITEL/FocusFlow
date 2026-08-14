import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tarea.dart';

// Recalcula y publica los datos del widget de Tareas. Se llama tanto desde la
// app en primer plano (tras crear/editar/completar una tarea, o al pasar a
// segundo plano) como desde el isolate headless que atiende el click del
// ícono de alternancia (ver [tareasWidgetBackgroundCallback]) — por eso lee
// siempre desde SharedPreferences en lugar de depender del árbol de
// providers de Riverpod, que no existe en ese isolate.
//
// Los datos de cada modo se guardan bajo su propia clave
// (tareas_widget_data_proximas / tareas_widget_data_importantes) en vez de
// una única clave "activa", y CADA sincronización (sea por CRUD, por toggle
// o por la red de seguridad del ciclo de vida) recalcula y guarda los DOS
// modos. Esto es deliberado: si solo se recalculara el modo actualmente
// visible, el modo "inactivo" podía quedarse con datos viejos (de una sesión
// anterior) hasta la próxima vez que alguien tocara el ícono — y si ese
// toggle puntual llegaba a fallar, se mostraban esos datos viejos, que
// pueden tener cualquier orden sin relación con el bug real. Mantener ambos
// modos siempre frescos elimina esa ventana de datos obsoletos por completo.
class WidgetTareasService {
  static const String _tareasStorageKey = 'lista_tareas_v1';
  static const String _widgetModoKey = 'tareas_widget_modo';
  static const String _widgetDataProximasKey = 'tareas_widget_data_proximas';
  static const String _widgetDataImportantesKey = 'tareas_widget_data_importantes';
  static const String _widgetTotalPendientesKey = 'tareas_widget_total_pendientes';
  static const String modoProximas = 'proximas';
  static const String modoImportantes = 'importantes';
  // Dos widgets de tamaño fijo (ver TareasWidgetProviderBase.kt) en vez del
  // provider único redimensionable anterior: ambos se actualizan siempre
  // juntos, cada uno solo pinta las tarjetas que le caben (2 o 4).
  static const List<String> _androidWidgetNames = [
    'TareasWidgetProviderChico',
    'TareasWidgetProviderGrande',
  ];

  // Tope superior de tareas que se envían al widget. Cuál de las dos
  // variantes (Chico=2, Grande=4) está realmente colocada en la pantalla de
  // inicio no lo sabe este servicio, así que se manda un tope superior
  // razonable y cada TareasWidgetProviderChico/Grande recorta a lo suyo.
  static const int _maxItems = 6;

  // Recalcula AMBOS modos (ver nota de la clase) y deja el modo indicado (o,
  // si no se pasa ninguno, el que esté actualmente guardado como activo)
  // como el modo visible del widget. Es lo que dispara tanto la
  // sincronización tras crear/editar/completar una tarea como el click en el
  // ícono de alternancia.
  static Future<void> actualizar({String? nuevoModo}) async {
    try {
      String modo =
          nuevoModo ??
          await HomeWidget.getWidgetData<String>(
            _widgetModoKey,
            defaultValue: modoProximas,
          ) ??
          modoProximas;
      if (modo != modoImportantes) modo = modoProximas;

      final tareas = await _leerTareas();
      await _recalcularYGuardarAmbosModos(tareas);
      await HomeWidget.saveWidgetData<String>(_widgetModoKey, modo);
      await _actualizarWidgetsAndroid();

      // ignore: avoid_print
      print('WidgetTareasService.actualizar: modo activo=$modo (${tareas.length} tareas totales)');
    } catch (e) {
      // No queremos que un fallo al sincronizar el widget rompa el flujo
      // normal de la app (creación/edición/completado de tareas).
      // ignore: avoid_print
      print('WidgetTareasService.actualizar: error al sincronizar -> $e');
    }
  }

  // Red de seguridad adicional: recalcula y guarda AMBOS modos sin cambiar
  // cuál está actualmente visible en el widget. Pensado para llamarse cuando
  // la app pasa a segundo plano o se cierra, corriendo siempre en el isolate
  // principal (con acceso confirmado a los datos reales). Desde el fix de
  // arriba, [actualizar] ya hace este mismo trabajo en cada sync de CRUD, así
  // que esta función es sobre todo para el caso en que la app pase a segundo
  // plano sin que haya habido ninguna operación de CRUD de por medio.
  static Future<void> actualizarAmbosModos() async {
    try {
      final tareas = await _leerTareas();
      await _recalcularYGuardarAmbosModos(tareas);
      await _actualizarWidgetsAndroid();
    } catch (e) {
      // ignore: avoid_print
      print('WidgetTareasService.actualizarAmbosModos: error al sincronizar -> $e');
    }
  }

  static Future<void> _actualizarWidgetsAndroid() async {
    for (final nombre in _androidWidgetNames) {
      await HomeWidget.updateWidget(androidName: nombre);
    }
  }

  static Future<void> _recalcularYGuardarAmbosModos(List<Tarea> tareas) async {
    final itemsProximas = _calcularItems(tareas, modoProximas);
    final itemsImportantes = _calcularItems(tareas, modoImportantes);
    final totalPendientes = tareas.where((t) => !t.esCompletada).length;

    await HomeWidget.saveWidgetData<String>(_widgetDataProximasKey, jsonEncode(itemsProximas));
    await HomeWidget.saveWidgetData<String>(
      _widgetDataImportantesKey,
      jsonEncode(itemsImportantes),
    );
    await HomeWidget.saveWidgetData<String>(
      _widgetTotalPendientesKey,
      totalPendientes.toString(),
    );

    // ignore: avoid_print
    print(
      'WidgetTareasService: recalculado -> '
      'proximas=${itemsProximas.map((t) => t['titulo']).toList()}, '
      'importantes=${itemsImportantes.map((t) => t['titulo']).toList()}, '
      'totalPendientes=$totalPendientes',
    );
  }

  static Future<List<Tarea>> _leerTareas() async {
    final prefs = await SharedPreferences.getInstance();
    // Fuerza una relectura desde la plataforma en vez de confiar en el caché
    // en memoria de esta instancia: este servicio corre tanto en el isolate
    // principal como en el isolate headless que home_widget reutiliza entre
    // clicks del ícono de alternancia, y ese isolate no ve por sí solo los
    // cambios guardados desde el isolate principal (ni viceversa).
    await prefs.reload();
    final tareasJson = prefs.getString(_tareasStorageKey);
    if (tareasJson == null) return [];
    return (jsonDecode(tareasJson) as List)
        .map((item) => Tarea.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static List<Map<String, dynamic>> _calcularItems(List<Tarea> tareas, String modo) {
    final pendientes = tareas.where((t) => !t.esCompletada).toList();
    if (modo == modoImportantes) {
      pendientes.sort((a, b) => b.urgencia.compareTo(a.urgencia));
    } else {
      pendientes.sort(_compararPorFecha);
    }

    // ignore: avoid_print
    print(
      'WidgetTareasService._calcularItems: modo=$modo -> orden resultante='
      '${pendientes.map((t) => '${t.titulo}(fecha=${t.fechaLimite}, urgencia=${t.urgencia})').toList()}',
    );

    // El límite real de cuántas de estas se terminan mostrando lo decide
    // TareasWidgetProviderChico/Grande (2 o 4); acá solo se manda un tope
    // superior razonable (_maxItems). El diseño actual de las tarjetas no
    // muestra grupo/categoría, así que ya no se envía ese campo.
    return pendientes
        .take(_maxItems)
        .map(
          (t) => {
            'titulo': t.titulo,
            'fechaLimite': t.fechaLimite?.toIso8601String(),
            'urgencia': t.urgencia,
          },
        )
        .toList();
  }

  // Mismo criterio de orden que TipoOrden.fecha en home_screen.dart: ascendente
  // por fechaLimite, con las tareas sin fecha al final.
  static int _compararPorFecha(Tarea a, Tarea b) {
    if (a.fechaLimite == null && b.fechaLimite == null) return 0;
    if (a.fechaLimite == null) return 1;
    if (b.fechaLimite == null) return -1;
    return a.fechaLimite!.compareTo(b.fechaLimite!);
  }
}

// Entry point ejecutado en un isolate headless cuando se toca el ícono de
// alternancia del widget de Tareas. Debe ser una función de nivel superior
// (no un closure) para que PluginUtilities.getCallbackHandle pueda ubicarla.
@pragma('vm:entry-point')
Future<void> tareasWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'toggle_modo_tareas') return;

  final modoActual =
      await HomeWidget.getWidgetData<String>(
        WidgetTareasService._widgetModoKey,
        defaultValue: WidgetTareasService.modoProximas,
      ) ??
      WidgetTareasService.modoProximas;

  final nuevoModo = modoActual == WidgetTareasService.modoProximas
      ? WidgetTareasService.modoImportantes
      : WidgetTareasService.modoProximas;

  // ignore: avoid_print
  print('tareasWidgetBackgroundCallback: modoActual=$modoActual -> nuevoModo=$nuevoModo');

  await WidgetTareasService.actualizar(nuevoModo: nuevoModo);
}
