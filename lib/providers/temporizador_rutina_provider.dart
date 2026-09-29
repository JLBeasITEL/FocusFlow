import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notificaciones_service.dart';
import 'rutina_provider.dart';

// ============================================================
// TemporizadorRutina — temporizador opcional por rutina
// ------------------------------------------------------------
// Un solo temporizador activo a la vez, global (nunca uno por rutina:
// por eso este provider es nullable y NO usa .family). Vive fuera del
// modelo Rutina y fuera del backup (ver _storageKey más abajo y
// backup_service.dart, que usa un allowlist explícito de claves —
// esta nunca se agrega ahí a propósito).
//
// Este provider es la VISTA EN MEMORIA de {rutinaId, venceEn}, no la
// fuente de verdad: la fuente real es la alarma nativa de Android
// programada aparte (zonedSchedule/AndroidScheduleMode.alarmClock,
// ver commits siguientes) más lo persistido en SharedPreferences. Si
// la app se cierra y se reabre, build() relee ese valor persistido y
// lo recalcula contra el reloj actual — la cuenta la lleva Android,
// no este Notifier.
// ============================================================
class TemporizadorRutina {
  final String rutinaId;
  final DateTime venceEn;
  final int segundosRestantes;

  // Duración total con la que arrancó, en segundos (calculada una sola vez
  // al iniciar, ver TemporizadorRutinaNotifier.iniciar). Necesaria para
  // fraccionCompletada -- segundosRestantes solo no alcanza para saber qué
  // proporción ya transcurrió sin saber también contra qué total.
  final int duracionTotalSegundos;

  const TemporizadorRutina({
    required this.rutinaId,
    required this.venceEn,
    required this.segundosRestantes,
    required this.duracionTotalSegundos,
  });

  TemporizadorRutina copyWith({int? segundosRestantes}) {
    return TemporizadorRutina(
      rutinaId: rutinaId,
      venceEn: venceEn,
      segundosRestantes: segundosRestantes ?? this.segundosRestantes,
      duracionTotalSegundos: duracionTotalSegundos,
    );
  }

  // 0.0 recién iniciado, 1.0 al vencer. Es el valor que pinta el anillo de
  // progreso de RutinaCard/RutinaLandscapeCard en el hueco del checkbox --
  // el tick en sí (ver _tick más abajo) nunca mira este getter, solo
  // segundosRestantes.
  double get fraccionCompletada {
    if (duracionTotalSegundos <= 0) return 1.0;
    final double fraccion = 1 - (segundosRestantes / duracionTotalSegundos);
    return fraccion.clamp(0.0, 1.0);
  }
}

// Formato para mostrar segundosRestantes en el lugar de la hora en
// RutinaCard/RutinaLandscapeCard. Vive acá, junto al tipo que formatea, para
// que ninguna de las dos tarjetas duplique el cálculo.
// mm:ss por debajo de una hora (igual que antes); a partir de una hora pasa
// a h:mm:ss (90 minutos → "1:30:00", no "90:00") — la duración del
// temporizador no tiene tope, así que sin esto un temporizador largo se
// leía como una cuenta de minutos de dos dígitos cada vez más confusa.
String formatoCuentaRegresiva(int segundos) {
  final int horas = segundos ~/ 3600;
  final int minutos = (segundos % 3600) ~/ 60;
  final int segs = segundos % 60;
  if (horas > 0) {
    return '$horas:${minutos.toString().padLeft(2, '0')}:${segs.toString().padLeft(2, '0')}';
  }
  return '${minutos.toString().padLeft(2, '0')}:${segs.toString().padLeft(2, '0')}';
}

class TemporizadorRutinaNotifier extends Notifier<TemporizadorRutina?> {
  static const String _storageKey = 'temporizador_rutina_activo';

  Timer? _ticker;

  DateTime get _ahora => ref.read(relojProvider)();

  @override
  TemporizadorRutina? build() {
    // Mismo patrón que RutinaNotifier.build(): build() debe devolver
    // sincrónico, así que la carga async se dispara sin esperar y el
    // estado se actualiza sola cuando termine.
    ref.onDispose(() => _ticker?.cancel());
    _cargarDesdeDisco();
    return null;
  }

  Future<void> _cargarDesdeDisco() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? crudo = prefs.getString(_storageKey);
      if (crudo == null) return;

      final Map<String, dynamic> mapa = jsonDecode(crudo) as Map<String, dynamic>;
      final String rutinaId = mapa['rutinaId'] as String;
      final DateTime? venceEn = DateTime.tryParse(mapa['venceEn'] as String);
      if (venceEn == null) {
        await prefs.remove(_storageKey);
        return;
      }
      final int segundosRestantes = _calcularSegundosRestantes(venceEn);
      // Respaldo defensivo si faltara (no debería, todo temporizador nuevo
      // lo persiste desde que existe este campo): sin el total real, se
      // asume "recién iniciado" (fraccionCompletada = 0) en vez de crashear.
      final int duracionTotalSegundos = (mapa['duracionTotalSegundos'] as int?) ?? segundosRestantes;

      state = TemporizadorRutina(
        rutinaId: rutinaId,
        venceEn: venceEn,
        segundosRestantes: segundosRestantes,
        duracionTotalSegundos: duracionTotalSegundos,
      );
      // El cold start de la app es, en los hechos, un "resumed": si había un
      // temporizador persistido, el tick debe estar corriendo ya, sin
      // esperar a que main.dart reciba una transición de ciclo de vida que
      // en un arranque en frío nunca llega.
      iniciarTick();
    } catch (_) {
      // JSON corrupto u otro dato inesperado: se descarta en vez de dejar
      // este provider crasheado para el resto de la sesión.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    }
  }

  int _calcularSegundosRestantes(DateTime venceEn) {
    final int restante = venceEn.difference(_ahora).inSeconds;
    return restante > 0 ? restante : 0;
  }

  // Persiste {rutinaId, venceEn} y publica el estado inicial. Sin pausa ni
  // reanudación (ver diseño acordado): de acá en más solo hay iniciar/
  // cancelar. `titulo`/`iconoCode` no se persisten (no forman parte de
  // {rutinaId, venceEn} acordado): solo rotulan la notificación ongoing y
  // la alarma de vencimiento en el instante en que arrancan -- ambas
  // sobreviven a un cierre de la app por su cuenta (la ongoing porque
  // Android la sigue mostrando, la alarma porque es la propia alarma
  // nativa la que dispara la navegación via payload), sin que Dart
  // necesite reconstruirlas.
  Future<void> iniciar({
    required String rutinaId,
    required DateTime venceEn,
    required String titulo,
    required int iconoCode,
  }) async {
    final int duracionTotalSegundos = venceEn.difference(_ahora).inSeconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'rutinaId': rutinaId,
        'venceEn': venceEn.toIso8601String(),
        'duracionTotalSegundos': duracionTotalSegundos,
      }),
    );
    state = TemporizadorRutina(
      rutinaId: rutinaId,
      venceEn: venceEn,
      segundosRestantes: _calcularSegundosRestantes(venceEn),
      duracionTotalSegundos: duracionTotalSegundos,
    );
    iniciarTick();
    // "En ejecución" no debe sonar la alarma normal de la rutina si su hora
    // llega mientras el temporizador sigue corriendo (ver
    // suspenderNotificacionesDeHoyPorTemporizador en rutina_provider.dart).
    await ref.read(rutinaProvider.notifier).suspenderNotificacionesDeHoyPorTemporizador(rutinaId);
    await NotificacionesService().mostrarNotificacionOngoingTemporizador(titulo: titulo, venceEn: venceEn);
    await NotificacionesService().programarAlarmaVencimientoTemporizador(
      rutinaId: rutinaId,
      rutinaTitulo: titulo,
      iconoCode: iconoCode,
      venceEn: venceEn,
    );
  }

  Future<void> cancelar() async {
    detenerTick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    state = null;
    await NotificacionesService().cancelarNotificacionOngoingTemporizador();
    await NotificacionesService().cancelarAlarmaVencimientoTemporizador();
  }

  // ============================================================
  // iniciarTick / detenerTick — enganchados al WidgetsBindingObserver de
  // main.dart (arranca en resumed, se detiene en paused/detached). Antes de
  // arrancar el Timer.periodic, SIEMPRE recalcula una vez contra venceEn
  // (nunca continúa desde segundosRestantes viejo): así, si la app estuvo
  // en segundo plano varios minutos, el primer valor que se muestra al
  // volver ya es el correcto, no el de cuando se pausó.
  // ============================================================
  void iniciarTick() {
    _ticker?.cancel();
    if (state == null) return;

    _recalcularContraVenceEn();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void detenerTick() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _recalcularContraVenceEn() {
    final actual = state;
    if (actual == null) return;
    final int nuevo = _calcularSegundosRestantes(actual.venceEn);
    if (nuevo != actual.segundosRestantes) {
      state = actual.copyWith(segundosRestantes: nuevo);
    }
  }

  // Solo emite estado nuevo cuando cambia el segundo entero mostrado, no en
  // cada disparo del timer (que corre cada 1s de todos modos, pero esto
  // deja la puerta cerrada a drift: si un tick llegara tarde o se saltara
  // uno, igual se compara siempre contra venceEn, nunca contra "restar 1").
  void _tick() {
    final actual = state;
    if (actual == null) {
      detenerTick();
      return;
    }
    final int nuevo = _calcularSegundosRestantes(actual.venceEn);
    if (nuevo != actual.segundosRestantes) {
      state = actual.copyWith(segundosRestantes: nuevo);
    }
    // Llegó a cero: el tick local no tiene nada más que mostrar. La
    // confirmación de vencimiento (pantalla de alarma) la dispara la alarma
    // nativa / el reconciliador de arranque (ver commits siguientes) — este
    // Notifier nunca completa la rutina por su cuenta.
    if (nuevo <= 0) {
      detenerTick();
    }
  }
}

final temporizadorRutinaProvider = NotifierProvider<TemporizadorRutinaNotifier, TemporizadorRutina?>(() {
  return TemporizadorRutinaNotifier();
});
