// Verifica el otorgamiento de monedas de racha de las rutinas: cuántas
// monedas paga cada hito (1 por semana de 5-6 días, 2 por semana de 7 días),
// el multiplicador por semanas seguidas (x2 desde la 2ª semana, x3 desde el
// mes) y que un mismo hito nunca se cobre dos veces.
//
// La primera mitad ejercita calcularRecompensaRacha directamente (función
// pura, sin estado ni reloj) porque es la fuente única del cálculo, usada
// tanto por toggleCompletada como por el diálogo de felicitación. La segunda
// mitad corre el provider real (RutinaNotifier + MonedasNotifier) contra
// SharedPreferences en memoria, para comprobar que las monedas calculadas
// terminan de verdad acreditadas en el saldo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:app_tareas/models/rutina.dart';
import 'package:app_tareas/providers/monedas_provider.dart';
import 'package:app_tareas/providers/rutina_provider.dart';

// Rutina mínima para los tests de integración: sin colchón de
// notificaciones previo y con fechaCompletada nula a propósito, para que la
// revisión de "rachas perdidas" de _cargarRutinas no toque la racha sembrada
// (ver el chequeo de fechaCompletada != null en rutina_provider.dart).
Rutina _rutinaDePrueba({
  required String id,
  required Map<int, TimeOfDay> horarios,
  required int racha,
  int rachaPagadaHasta = 0,
}) {
  return Rutina(
    id: id,
    titulo: 'Rutina de prueba',
    horarios: horarios,
    iconoCode: 0xe000,
    racha: racha,
    rachaPagadaHasta: rachaPagadaHasta,
  );
}

// Mismo formato exacto que escribe _guardarRutinas en producción.
String _listaGuardadaCon(Rutina r) => jsonEncode([r.toJson()]);

// Mismo patrón que rutina_notificaciones_test.dart: sin temporizadores
// reales de por medio, esto alcanza de sobra para que drene la cadena de
// awaits de _cargarRutinas / toggleCompletada.
Future<void> _dejarQueTermineElTrabajoAsincrono() async {
  await Future<void>.delayed(const Duration(milliseconds: 200));
}

Map<int, TimeOfDay> _horariosDe(int diasPorSemana) {
  return {
    for (var dia = 0; dia < diasPorSemana; dia++) dia: const TimeOfDay(hour: 8, minute: 0),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('calcularRecompensaRacha', () {
    test('7 días/semana: base 2, con x2 desde la 2ª semana y x3 desde el mes', () {
      RecompensaRacha? recompensa(int nuevaRacha) => calcularRecompensaRacha(
            diasPorSemana: 7,
            nuevaRacha: nuevaRacha,
            rachaPagadaHasta: 0,
          );

      expect(recompensa(7)!.monedas, equals(2), reason: '1ª semana: base 2 sin multiplicar');
      expect(recompensa(7)!.semanas, equals(1));
      expect(recompensa(14)!.monedas, equals(4), reason: '2ª semana: 2 x2');
      expect(recompensa(14)!.multiplicador, equals(2));
      expect(recompensa(21)!.monedas, equals(4), reason: '3ª semana: sigue x2, todavía no es un mes');
      expect(recompensa(28)!.monedas, equals(6), reason: '4ª semana (un mes): 2 x3');
      expect(recompensa(28)!.multiplicador, equals(3));
      expect(recompensa(70)!.monedas, equals(6), reason: 'x3 es el tope: no sigue creciendo');
    });

    test('5 y 6 días/semana: base 1, con la misma escala de multiplicadores', () {
      expect(calcularRecompensaRacha(diasPorSemana: 5, nuevaRacha: 5, rachaPagadaHasta: 0)!.monedas, equals(1));
      expect(calcularRecompensaRacha(diasPorSemana: 5, nuevaRacha: 10, rachaPagadaHasta: 0)!.monedas, equals(2));
      expect(calcularRecompensaRacha(diasPorSemana: 5, nuevaRacha: 15, rachaPagadaHasta: 0)!.monedas, equals(2));
      expect(calcularRecompensaRacha(diasPorSemana: 5, nuevaRacha: 20, rachaPagadaHasta: 0)!.monedas, equals(3));

      expect(calcularRecompensaRacha(diasPorSemana: 6, nuevaRacha: 6, rachaPagadaHasta: 0)!.monedas, equals(1));
      expect(calcularRecompensaRacha(diasPorSemana: 6, nuevaRacha: 12, rachaPagadaHasta: 0)!.monedas, equals(2));
      expect(calcularRecompensaRacha(diasPorSemana: 6, nuevaRacha: 24, rachaPagadaHasta: 0)!.monedas, equals(3));
    });

    test('una racha que no cierra la semana de la rutina no paga nada', () {
      for (final racha in [1, 2, 3, 4, 6, 8, 9]) {
        expect(calcularRecompensaRacha(diasPorSemana: 5, nuevaRacha: racha, rachaPagadaHasta: 0), isNull,
            reason: 'con 5 días/semana, $racha no cierra ninguna semana');
      }
      expect(calcularRecompensaRacha(diasPorSemana: 7, nuevaRacha: 0, rachaPagadaHasta: 0), isNull);
    });

    test('un hito ya cobrado no vuelve a pagar (desmarcar y volver a marcar)', () {
      expect(calcularRecompensaRacha(diasPorSemana: 5, nuevaRacha: 10, rachaPagadaHasta: 10), isNull);
      expect(calcularRecompensaRacha(diasPorSemana: 7, nuevaRacha: 14, rachaPagadaHasta: 14), isNull);
      // rachaPagadaHasta sembrado por migración con un valor que no es hito
      // (ver fromJson en rutina.dart): no debe adelantar ni atrasar el hito.
      expect(calcularRecompensaRacha(diasPorSemana: 7, nuevaRacha: 14, rachaPagadaHasta: 9)!.monedas, equals(4));
    });

    test('menos de 5 días/semana: hito histórico de 7 completadas, 1 moneda, sin multiplicador', () {
      // Con 1 día/semana el hito NO puede ser diasPorSemana (cada completada
      // sería un hito): se conserva el divisor fijo de 7.
      expect(calcularRecompensaRacha(diasPorSemana: 1, nuevaRacha: 1, rachaPagadaHasta: 0), isNull);
      expect(calcularRecompensaRacha(diasPorSemana: 1, nuevaRacha: 7, rachaPagadaHasta: 0)!.monedas, equals(1));

      expect(calcularRecompensaRacha(diasPorSemana: 3, nuevaRacha: 3, rachaPagadaHasta: 0), isNull);
      expect(calcularRecompensaRacha(diasPorSemana: 3, nuevaRacha: 7, rachaPagadaHasta: 0)!.monedas, equals(1));
      final hitoAlto = calcularRecompensaRacha(diasPorSemana: 4, nuevaRacha: 28, rachaPagadaHasta: 0)!;
      expect(hitoAlto.monedas, equals(1), reason: 'sin multiplicador en el esquema histórico');
      expect(hitoAlto.multiplicador, equals(1));
      expect(hitoAlto.semanas, equals(0), reason: 'el hito de 7 completadas no representa semanas');
    });
  });

  group('toggleCompletada acredita las monedas del hito', () {
    const MethodChannel canalNotificaciones = MethodChannel('dexterous.com/flutter/local_notifications');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canalNotificaciones, (MethodCall call) async => null);
      // toggleCompletada reprograma el colchon de la rutina, y programar pasa
      // por tz.local (notificaciones_service.dart): sin esto revienta con
      // LateInitializationError antes de llegar a acreditar las monedas.
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canalNotificaciones, null);
    });

    // Deja el saldo sembrado en 0 (clave presente) para que MonedasNotifier
    // no reparta el regalo de bienvenida y el saldo final sea exactamente lo
    // que otorgó este hito.
    Future<ProviderContainer> contenedorCon(Rutina rutina) async {
      SharedPreferences.setMockInitialValues({
        'lista_rutinas_v2': _listaGuardadaCon(rutina),
        'monedas_racha_v1': 0,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(rutinaProvider.notifier);
      container.read(monedasProvider.notifier);
      await _dejarQueTermineElTrabajoAsincrono();
      expect(container.read(monedasProvider), equals(0), reason: 'saldo inicial sembrado en 0');
      return container;
    }

    test('cerrar la 2ª semana de una rutina de 7 días/semana paga 4 monedas (2 x2)', () async {
      const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      final container = await contenedorCon(
        _rutinaDePrueba(id: id, horarios: _horariosDe(7), racha: 13, rachaPagadaHasta: 7),
      );

      await container.read(rutinaProvider.notifier).toggleCompletada(id);
      await _dejarQueTermineElTrabajoAsincrono();

      expect(container.read(monedasProvider), equals(4));
      final rutina = container.read(rutinaProvider).firstWhere((r) => r.id == id);
      expect(rutina.racha, equals(14));
      expect(rutina.rachaPagadaHasta, equals(14), reason: 'el hito queda registrado como cobrado');
    });

    test('cerrar la 1ª semana de una rutina de 5 días/semana paga 1 moneda', () async {
      const id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      final container = await contenedorCon(
        _rutinaDePrueba(id: id, horarios: _horariosDe(5), racha: 4),
      );

      await container.read(rutinaProvider.notifier).toggleCompletada(id);
      await _dejarQueTermineElTrabajoAsincrono();

      expect(container.read(monedasProvider), equals(1));
    });

    test('una completada que no cierra la semana no paga nada', () async {
      const id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
      final container = await contenedorCon(
        _rutinaDePrueba(id: id, horarios: _horariosDe(5), racha: 2),
      );

      await container.read(rutinaProvider.notifier).toggleCompletada(id);
      await _dejarQueTermineElTrabajoAsincrono();

      expect(container.read(monedasProvider), equals(0));
    });

    test('desmarcar y volver a marcar sobre el mismo hito no paga dos veces', () async {
      const id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
      final container = await contenedorCon(
        _rutinaDePrueba(id: id, horarios: _horariosDe(7), racha: 6),
      );
      final notifier = container.read(rutinaProvider.notifier);

      await notifier.toggleCompletada(id); // racha 7: primera semana, 2 monedas
      await _dejarQueTermineElTrabajoAsincrono();
      expect(container.read(monedasProvider), equals(2));

      await notifier.toggleCompletada(id); // desmarcar: racha 6
      await _dejarQueTermineElTrabajoAsincrono();
      await notifier.toggleCompletada(id); // volver a marcar: racha 7 otra vez
      await _dejarQueTermineElTrabajoAsincrono();

      expect(container.read(monedasProvider), equals(2),
          reason: 'el hito 7 ya estaba pagado (rachaPagadaHasta)');
    });
  });
}
