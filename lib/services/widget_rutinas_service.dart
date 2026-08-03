import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rutina.dart';

// Recalcula y publica los datos del widget de Rutinas. A diferencia de
// WidgetTareasService no hay modo alternable: una sola lista, ordenada por
// hora programada de hoy. Se llama desde rutina_provider.dart (al cargar y
// al guardar) y desde el WidgetsBindingObserver de main.dart al pasar la app
// a segundo plano.
//
// Escrito a propósito en pasos separados (no chains de .where().map().take())
// con un log por etapa, para poder ver en Logcat exactamente en qué paso se
// pierde una rutina si el widget no muestra lo esperado.
class WidgetRutinasService {
  static const String _rutinasStorageKey = 'lista_rutinas_v2';
  static const String _widgetDataKey = 'rutinas_widget_data';
  static const String _androidWidgetName = 'RutinasWidgetProvider';
  static const int _maxItems = 6;

  static Future<void> actualizar() async {
    try {
      // SharedPreferences.getInstance() cachea en memoria por isolate; sin
      // el reload() explícito, este servicio podría quedarse con una foto
      // vieja de las rutinas si corre en un isolate distinto al que hizo la
      // última escritura (mismo bug que ya mordió a WidgetTareasService).
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final rutinasJson = prefs.getString(_rutinasStorageKey);

      final List<Rutina> todasLasRutinas;
      if (rutinasJson == null) {
        todasLasRutinas = [];
      } else {
        final decodificado = jsonDecode(rutinasJson) as List;
        todasLasRutinas = decodificado.map((item) => Rutina.fromJson(item as Map<String, dynamic>)).toList();
      }
      // ignore: avoid_print
      print(
        'WidgetRutinasService [1/4] total en storage ($_rutinasStorageKey): '
        '${todasLasRutinas.length} -> ${todasLasRutinas.map((r) => r.titulo).toList()}',
      );

      // Mismo criterio que home_screen.dart (línea ~1127): horarios usa
      // índices 0-6 (0=lunes), NO el 1-7 de DateTime.weekday. El getter
      // progresoDiario de rutina_provider.dart tiene un bug de índice que
      // NO replicamos acá a propósito.
      final diaActual = DateTime.now().weekday - 1;
      final hoyStr = DateTime.now().toIso8601String().split('T')[0];

      final List<Rutina> rutinasDeHoy = [];
      for (final r in todasLasRutinas) {
        final programadaHoy = r.horarios.containsKey(diaActual);
        if (programadaHoy && r.activa) {
          rutinasDeHoy.add(r);
        } else {
          // ignore: avoid_print
          print(
            'WidgetRutinasService [filtro] "${r.titulo}" descartada -> '
            'programadaHoy=$programadaHoy, activa=${r.activa}, '
            'horarios.keys=${r.horarios.keys.toList()}, diaActual=$diaActual',
          );
        }
      }
      // ignore: avoid_print
      print(
        'WidgetRutinasService [2/4] tras filtro "es de hoy y activa": '
        '${rutinasDeHoy.length} -> ${rutinasDeHoy.map((r) => r.titulo).toList()}',
      );

      // El storage puede tener 'completada' arrastrado de ayer si la app no
      // se abrió hoy todavía (ese reseteo vive en _cargarRutinas() y solo
      // corre al abrir la app) — lo recalculamos acá de forma independiente
      // más abajo, al armar cada item.
      rutinasDeHoy.sort((a, b) {
        final horaA = a.horarios[diaActual]!;
        final horaB = b.horarios[diaActual]!;
        final minutosA = horaA.hour * 60 + horaA.minute;
        final minutosB = horaB.hour * 60 + horaB.minute;
        return minutosA.compareTo(minutosB);
      });

      final List<Rutina> rutinasLimitadas = rutinasDeHoy.length > _maxItems
          ? rutinasDeHoy.sublist(0, _maxItems)
          : rutinasDeHoy;
      // ignore: avoid_print
      print(
        'WidgetRutinasService [3/4] tras ordenar por hora y limitar a $_maxItems: '
        '${rutinasLimitadas.length} -> ${rutinasLimitadas.map((r) => r.titulo).toList()}',
      );

      final List<Map<String, Object?>> items = [];
      for (final r in rutinasLimitadas) {
        try {
          final hora = r.horarios[diaActual];
          if (hora == null) {
            // No debería pasar (ya filtramos por containsKey arriba), pero
            // si pasara no queremos que un ! tumbe todo el ciclo.
            // ignore: avoid_print
            print(
              'WidgetRutinasService: "${r.titulo}" no tiene hora para diaActual=$diaActual '
              'pese a haber pasado el filtro -> se omite esta rutina puntual',
            );
            continue;
          }
          final completadaHoy = r.completada && r.fechaCompletada == hoyStr;
          items.add({'titulo': r.titulo, 'horaHoy': _formatearHora(hora), 'completada': completadaHoy});
        } catch (e) {
          // Una rutina con datos corruptos no debe tumbar a las demás.
          // ignore: avoid_print
          print('WidgetRutinasService: excepción armando el item de "${r.titulo}" -> $e');
        }
      }
      // ignore: avoid_print
      print(
        'WidgetRutinasService [4/4] items finales enviados al widget: '
        '${items.length} -> ${items.map((i) => i['titulo']).toList()} '
        '(cuántos de estos se terminan MOSTRANDO lo decide RutinasWidgetProvider.kt '
        'según el tamaño real del widget, no este servicio)',
      );

      await HomeWidget.saveWidgetData<String>(_widgetDataKey, jsonEncode(items));
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (e) {
      // No queremos que un fallo al sincronizar el widget rompa el flujo
      // normal de la app (crear/editar/completar una rutina).
      // ignore: avoid_print
      print('WidgetRutinasService.actualizar: error al sincronizar -> $e');
    }
  }

  static String _formatearHora(TimeOfDay hora) {
    final h = hora.hour.toString().padLeft(2, '0');
    final m = hora.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
