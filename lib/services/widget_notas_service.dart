import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nota.dart';

// Recalcula y publica los datos de los widgets de Notas (Chico y Grande).
// Ambas variantes leen la MISMA clave de datos: Chico solo tiene 2 tarjetas
// pre-construidas en su layout (ver NotasWidgetProviderChico.kt), así que
// aunque este servicio publique 4 notas (modo "4 notas" de Grande), Chico
// simplemente ignora las 2 de más — no hace falta una clave por variante.
// Esto funciona porque la selección es prefix-estable: las primeras 2 notas
// de una selección de 4 son EXACTAMENTE las mismas que la selección de 2
// (mismo orden: destacadas primero, luego recientes), ver _seleccionarNotas.
//
// Se llama desde nota_provider.dart tras cualquier cambio que afecte qué se
// debería mostrar (crear, borrar, deshacer, editar, destacar), desde el
// WidgetsBindingObserver de main.dart al pasar la app a segundo plano, y
// desde [notasWidgetBackgroundCallback] cuando se toca el botón de
// alternancia 2/4 del widget Grande (sin abrir la app).
class WidgetNotasService {
  static const String _notasStorageKey = 'lista_notas_postit_v2';
  static const String _widgetDataKey = 'notas_widget_data';
  static const String _widgetModoCantidadKey = 'notas_widget_modo_cantidad';
  static const int _cantidadPorDefecto = 2;
  static const List<String> _androidWidgetNames = [
    'NotasWidgetProviderChico',
    'NotasWidgetProviderGrande',
  ];

  // Recalcula y publica los datos usando la cantidad indicada (o, si no se
  // pasa ninguna, la que esté actualmente guardada como activa). Es lo que
  // dispara tanto la sincronización tras un cambio en las notas como el
  // click en el botón de alternancia 2/4.
  static Future<void> actualizar({int? nuevaCantidad}) async {
    try {
      final cantidad = nuevaCantidad ?? await _leerCantidadGuardada();

      // SharedPreferences.getInstance() cachea en memoria por isolate; sin
      // el reload() explícito este servicio podría ver una foto vieja de
      // las notas si corre en un isolate distinto al que hizo la última
      // escritura (mismo bug ya visto en WidgetRutinasService).
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final notasJson = prefs.getString(_notasStorageKey);

      final List<NotaPostIt> todasLasNotas;
      if (notasJson == null) {
        todasLasNotas = [];
      } else {
        final decodificado = jsonDecode(notasJson) as List;
        todasLasNotas = decodificado.map((item) => NotaPostIt.fromMap(item as Map<String, dynamic>)).toList();
      }

      final seleccionadas = _seleccionarNotas(todasLasNotas, cantidad);
      final items = seleccionadas
          .map((n) => {
                'id': n.id,
                'titulo': n.titulo,
                'texto': _construirPreview(n),
                'tiempoRelativo': _formatearTiempoRelativo(n.creadaEn),
              })
          .toList();

      await HomeWidget.saveWidgetData<String>(_widgetDataKey, jsonEncode(items));
      await HomeWidget.saveWidgetData<String>(_widgetModoCantidadKey, cantidad.toString());
      for (final nombre in _androidWidgetNames) {
        await HomeWidget.updateWidget(androidName: nombre);
      }
    } catch (e) {
      // No queremos que un fallo al sincronizar el widget rompa el flujo
      // normal de la app (crear/editar/destacar una nota).
      // ignore: avoid_print
      print('WidgetNotasService.actualizar: error al sincronizar -> $e');
    }
  }

  static Future<int> _leerCantidadGuardada() async {
    final guardada = await HomeWidget.getWidgetData<String>(
      _widgetModoCantidadKey,
      defaultValue: '$_cantidadPorDefecto',
    );
    final cantidad = int.tryParse(guardada ?? '') ?? _cantidadPorDefecto;
    // Único par de valores válidos que el botón de alternancia produce; ante
    // cualquier otro dato (corrupto o de una versión futura) se cae al
    // default en vez de mostrar una cantidad rara de tarjetas.
    return (cantidad == 2 || cantidad == 4) ? cantidad : _cantidadPorDefecto;
  }

  // Prioridad: notas destacadas (máximo 2, reforzado en
  // NotaNotifier.alternarDestacada), ordenadas por creadaEn. Si hay menos
  // destacadas que "cantidad", se completa con las notas más recientes (por
  // creadaEn, no por orden en el tablero, que el usuario puede reordenar
  // arrastrando) hasta llegar a "cantidad" o hasta quedarse sin notas.
  static List<NotaPostIt> _seleccionarNotas(List<NotaPostIt> todasLasNotas, int cantidad) {
    final destacadas = todasLasNotas.where((n) => n.destacada).toList()
      ..sort((a, b) => b.creadaEn.compareTo(a.creadaEn));

    final List<NotaPostIt> seleccionadas = destacadas.take(cantidad).toList();
    if (seleccionadas.length < cantidad) {
      final idsYaIncluidos = seleccionadas.map((n) => n.id).toSet();
      final recientes = [...todasLasNotas]..sort((a, b) => b.creadaEn.compareTo(a.creadaEn));
      for (final nota in recientes) {
        if (seleccionadas.length >= cantidad) break;
        if (idsYaIncluidos.contains(nota.id)) continue;
        seleccionadas.add(nota);
      }
    }
    return seleccionadas;
  }

  // Notas de lista no tienen texto libre (vive en elementosLista): se arma
  // una vista previa uniendo sus elementos para que el widget siempre
  // tenga algo que mostrar como cuerpo.
  static String _construirPreview(NotaPostIt nota) {
    if (nota.tipo == TipoNota.lista) {
      return nota.elementosLista.map((e) => e.texto).where((t) => t.trim().isNotEmpty).join(', ');
    }
    return nota.texto;
  }

  static String _formatearTiempoRelativo(int creadaEnMs) {
    if (creadaEnMs <= 0) return '';
    final diferencia = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(creadaEnMs));
    if (diferencia.inMinutes < 1) return 'ahora';
    if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
    if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
    if (diferencia.inDays == 1) return 'ayer';
    if (diferencia.inDays < 7) return 'hace ${diferencia.inDays} días';
    return 'hace ${(diferencia.inDays / 7).floor()} sem';
  }
}

// Entry point ejecutado en un isolate headless cuando se toca el botón de
// alternancia 2/4 del widget Notas · Grande. Debe ser una función de nivel
// superior (no un closure) para que PluginUtilities.getCallbackHandle pueda
// ubicarla (mismo patrón que tareasWidgetBackgroundCallback).
@pragma('vm:entry-point')
Future<void> notasWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'toggle_cantidad_notas') return;

  final cantidadActual = await WidgetNotasService._leerCantidadGuardada();
  final nuevaCantidad = cantidadActual == 2 ? 4 : 2;

  // ignore: avoid_print
  print('notasWidgetBackgroundCallback: cantidadActual=$cantidadActual -> nuevaCantidad=$nuevaCantidad');

  await WidgetNotasService.actualizar(nuevaCantidad: nuevaCantidad);
}
