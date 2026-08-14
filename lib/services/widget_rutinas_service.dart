import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rutina.dart';

// Recalcula y publica los datos del widget de Rutinas. A diferencia de
// WidgetTareasService no hay un modo alternable por el usuario: en cambio,
// cada variante fija tiene su propia vista siempre calculada — Grande
// (agenda completa de hoy, ordenada por hora) y Chico (solo pendientes,
// ordenadas por cercanía a la hora actual, ver más abajo). Se llama desde
// rutina_provider.dart (al cargar y al guardar) y desde el
// WidgetsBindingObserver de main.dart al pasar la app a segundo plano.
//
// Escrito a propósito en pasos separados (no chains de .where().map().take())
// con un log por etapa, para poder ver en Logcat exactamente en qué paso se
// pierde una rutina si el widget no muestra lo esperado.
class WidgetRutinasService {
  static const String _rutinasStorageKey = 'lista_rutinas_v2';
  // Grande muestra TODAS las rutinas de hoy (completadas incluidas, con
  // tachado + badge "HECHA") ordenadas por hora programada — sigue
  // publicándose bajo esta clave, sin cambios. Chico en cambio es una vista
  // de "qué hacer ahora": solo pendientes, ordenadas por cercanía a la hora
  // actual, bajo su propia clave.
  static const String _widgetDataKey = 'rutinas_widget_data';
  static const String _widgetDataChicoKey = 'rutinas_widget_data_chico';
  static const String _widgetTotalProgramadasKey = 'rutinas_widget_total_programadas';
  static const String _widgetTotalHechasKey = 'rutinas_widget_total_hechas';
  // Chico calcula su footer "+N rutinas más" contra este total (pendientes),
  // no contra totalProgramadas (que incluye las ya hechas, que Chico no
  // muestra).
  static const String _widgetTotalPendientesKey = 'rutinas_widget_total_pendientes';
  // Dos widgets de tamaño fijo (ver RutinasWidgetProviderBase.kt) en vez del
  // provider único redimensionable anterior, mismo patrón que ya tiene Tareas.
  static const List<String> _androidWidgetNames = [
    'RutinasWidgetProviderChico',
    'RutinasWidgetProviderGrande',
  ];
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

      // Sobre rutinasDeHoy COMPLETA (antes de recortar a _maxItems): el badge
      // "X/Y hechas" y los footers "+N rutinas más" necesitan el total real,
      // no el subconjunto que termina viajando a cada variante del widget.
      final totalProgramadas = rutinasDeHoy.length;
      final totalHechas = rutinasDeHoy.where((r) => r.completada && r.fechaCompletada == hoyStr).length;

      final List<Rutina> rutinasLimitadas = rutinasDeHoy.length > _maxItems
          ? rutinasDeHoy.sublist(0, _maxItems)
          : rutinasDeHoy;
      // ignore: avoid_print
      print(
        'WidgetRutinasService [3/4] (Grande) tras ordenar por hora y limitar a $_maxItems: '
        '${rutinasLimitadas.length} -> ${rutinasLimitadas.map((r) => r.titulo).toList()}',
      );
      final items = _construirItems(rutinasLimitadas, diaActual, hoyStr);

      // Chico: solo pendientes (ni completadas ni... omitidas SÍ se
      // conservan, "no estén marcadas como completas" no incluye omitidas),
      // ordenadas por cercanía al reloj actual en vez de por hora ascendente
      // — es una vista de "qué hacer ahora", no la agenda completa del día.
      final minutosAhora = DateTime.now().hour * 60 + DateTime.now().minute;
      int minutosProgramados(Rutina r) {
        final hora = r.horarios[diaActual]!;
        return hora.hour * 60 + hora.minute;
      }

      final List<Rutina> rutinasPendientesHoy = rutinasDeHoy
          .where((r) => !(r.completada && r.fechaCompletada == hoyStr))
          .toList()
        ..sort((a, b) {
          final diffA = (minutosProgramados(a) - minutosAhora).abs();
          final diffB = (minutosProgramados(b) - minutosAhora).abs();
          return diffA.compareTo(diffB);
        });
      final totalPendientes = rutinasPendientesHoy.length;
      final List<Rutina> rutinasPendientesLimitadas = rutinasPendientesHoy.length > _maxItems
          ? rutinasPendientesHoy.sublist(0, _maxItems)
          : rutinasPendientesHoy;
      // ignore: avoid_print
      print(
        'WidgetRutinasService [3/4] (Chico) pendientes ordenadas por cercanía a la hora, '
        'limitadas a $_maxItems: '
        '${rutinasPendientesLimitadas.length} -> ${rutinasPendientesLimitadas.map((r) => r.titulo).toList()}',
      );
      final itemsChico = _construirItems(rutinasPendientesLimitadas, diaActual, hoyStr);

      // ignore: avoid_print
      print(
        'WidgetRutinasService [4/4] items finales -> Grande: ${items.length}, Chico: ${itemsChico.length}. '
        'totalProgramadas=$totalProgramadas, totalHechas=$totalHechas, totalPendientes=$totalPendientes '
        '(cuántas de estas se terminan MOSTRANDO lo decide '
        'RutinasWidgetProviderChico/Grande según la variante, no este servicio)',
      );

      await HomeWidget.saveWidgetData<String>(_widgetDataKey, jsonEncode(items));
      await HomeWidget.saveWidgetData<String>(_widgetDataChicoKey, jsonEncode(itemsChico));
      await HomeWidget.saveWidgetData<String>(_widgetTotalProgramadasKey, totalProgramadas.toString());
      await HomeWidget.saveWidgetData<String>(_widgetTotalHechasKey, totalHechas.toString());
      await HomeWidget.saveWidgetData<String>(_widgetTotalPendientesKey, totalPendientes.toString());
      for (final nombre in _androidWidgetNames) {
        await HomeWidget.updateWidget(androidName: nombre);
      }
    } catch (e) {
      // No queremos que un fallo al sincronizar el widget rompa el flujo
      // normal de la app (crear/editar/completar una rutina).
      // ignore: avoid_print
      print('WidgetRutinasService.actualizar: error al sincronizar -> $e');
    }
  }

  static List<Map<String, Object?>> _construirItems(
    List<Rutina> rutinas,
    int diaActual,
    String hoyStr,
  ) {
    final List<Map<String, Object?>> items = [];
    for (final r in rutinas) {
      try {
        final hora = r.horarios[diaActual];
        if (hora == null) {
          // No debería pasar (ya se filtró por containsKey antes), pero si
          // pasara no queremos que un ! tumbe todo el ciclo.
          // ignore: avoid_print
          print(
            'WidgetRutinasService: "${r.titulo}" no tiene hora para diaActual=$diaActual '
            'pese a haber pasado el filtro -> se omite esta rutina puntual',
          );
          continue;
        }
        final completadaHoy = r.completada && r.fechaCompletada == hoyStr;
        final omitidaHoy = r.omitida && r.fechaOmitida == hoyStr;
        items.add({
          'id': r.id,
          'titulo': r.titulo,
          'horaHoy': _formatearHora(hora),
          'completada': completadaHoy,
          'omitida': omitidaHoy,
        });
      } catch (e) {
        // Una rutina con datos corruptos no debe tumbar a las demás.
        // ignore: avoid_print
        print('WidgetRutinasService: excepción armando el item de "${r.titulo}" -> $e');
      }
    }
    return items;
  }

  static String _formatearHora(TimeOfDay hora) {
    final h = hora.hour.toString().padLeft(2, '0');
    final m = hora.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
