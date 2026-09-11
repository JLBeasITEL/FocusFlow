// Cubre el segundo bug del temporizador de rutina: el reconciliador de
// arranque (reconciliador_temporizador_rutina.dart) solo corre una vez, al
// iniciar en frío -- si el temporizador vence con la app en primer plano, o
// en segundo plano pero VIVA (el usuario vuelve sin tocar la notificación),
// nadie ofrecía la confirmación. El fix agrega un listener en vivo sobre
// temporizadorRutinaProvider (ver temporizador_rutina_listener.dart) que
// reacciona al flanco "segundosRestantes llegó a 0", compartiendo un guard
// anti-duplicado por vencimiento concreto (rutinaId + venceEn) con el
// reconciliador de arranque y con tocar la notificación.
//
// Este archivo prueba dos cosas por separado:
//   1. El guard (NotificacionesService.marcarVencimientoTemporizadorSiNuevo/
//      liberarVencimientoTemporizadorEnPantalla) en aislamiento: identifica
//      el vencimiento concreto, no es un bool global, y se puede volver a
//      marcar tras liberar.
//   2. El listener de punta a punta: dispara PantallaAlarma cuando
//      iniciarTick() (la misma recalculación que corre al volver de segundo
//      plano, ver main.dart) descubre que ya venció, sin pasar por el
//      reconciliador de arranque; y que confirmar la deja lista para
//      ofrecerse de nuevo (el guard no queda pegado) y vuelve exactamente a
//      la pantalla donde estaba el usuario (no a un HomeScreen fresco).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:app_tareas/core/temporizador_rutina_listener.dart';
import 'package:app_tareas/models/rutina.dart';
import 'package:app_tareas/providers/rutina_provider.dart';
import 'package:app_tareas/providers/temporizador_rutina_provider.dart';
import 'package:app_tareas/services/notificaciones_service.dart';

// Mismo fake que pantalla_alarma_test.dart: evita que WakelockPlus.enable()/
// disable() (llamados por PantallaAlarma) crucen su canal pigeon real.
class _WakelockPlusFalso extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

// Reloj mutable para controlar "ahora" sin depender de timers reales:
// iniciarTick() recalcula segundosRestantes comparando venceEn contra este
// reloj de forma SÍNCRONA (ver TemporizadorRutinaNotifier._recalcularContraVenceEn),
// así que basta con adelantarlo y volver a llamar iniciarTick() para simular
// "la app estuvo en segundo plano y volvió después de que venciera".
class _RelojMutable {
  DateTime ahora;
  _RelojMutable(this.ahora);
  DateTime call() => ahora;
}

Rutina _rutinaDePrueba(String id) {
  return Rutina(
    id: id,
    titulo: 'Estirar',
    horarios: const {0: TimeOfDay(hour: 8, minute: 0)},
    iconoCode: 0xe000,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel canalNotificaciones = MethodChannel('dexterous.com/flutter/local_notifications');
  const MethodChannel canalAlarmaNativa = MethodChannel('com.beasdev.focusflow/alarm_screen');
  // toggleCompletada (llamado por "Entendido") termina en _guardarRutinas(),
  // que sincroniza el widget de pantalla de inicio vía este canal (ver
  // widget_rutinas_service.dart). Sin mock, la llamada sin implementación
  // nativa se comporta de forma inconsistente según la zona async en la que
  // se invoque (instantánea si el disparador corrió dentro de
  // tester.runAsync, colgada si corrió en la zona de reloj falso de
  // testWidgets -- exactamente el caso de tocar "Entendido" via
  // tester.tap()) -- mockearlo, igual que los demás canales de este
  // archivo, lo vuelve determinístico en cualquier zona.
  const MethodChannel canalWidgetInicio = MethodChannel('home_widget');

  setUp(() async {
    wakelockPlusPlatformInstance = _WakelockPlusFalso();
    NotificacionesService().liberarVencimientoTemporizadorEnPantalla();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canalNotificaciones,
      (MethodCall call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canalAlarmaNativa,
      (MethodCall call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canalWidgetInicio,
      (MethodCall call) async => null,
    );

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canalNotificaciones, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canalAlarmaNativa, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canalWidgetInicio, null);
    NotificacionesService().liberarVencimientoTemporizadorEnPantalla();
  });

  group('NotificacionesService: guard anti-duplicado por vencimiento concreto', () {
    test('el primer intento para un vencimiento gana la carrera', () {
      final venceEn = DateTime(2026, 1, 1, 10, 0);
      expect(NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r1', venceEn), isTrue);
    });

    test('un segundo intento para el MISMO vencimiento (misma rutina + mismo venceEn) queda bloqueado', () {
      final venceEn = DateTime(2026, 1, 1, 10, 0);
      expect(NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r1', venceEn), isTrue);
      expect(
        NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r1', venceEn),
        isFalse,
        reason: 'evita que la notificación tocada, el reconciliador y el listener apilen dos PantallaAlarma para el mismo vencimiento',
      );
    });

    test('un vencimiento DISTINTO (misma rutina, otro venceEn) no queda bloqueado por uno viejo sin liberar', () {
      final primerVenceEn = DateTime(2026, 1, 1, 10, 0);
      final segundoVenceEn = DateTime(2026, 1, 1, 11, 0);
      expect(NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r1', primerVenceEn), isTrue);
      // Simula el bug que la identidad {rutinaId, venceEn} evita: nadie
      // liberó el primero (dispose() nunca corrió).
      expect(
        NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r1', segundoVenceEn),
        isTrue,
        reason: 'un guard con identidad, no un bool global, no debe bloquear para siempre un vencimiento nuevo y distinto',
      );
    });

    test('otra rutina con el mismo venceEn tampoco queda bloqueada', () {
      final venceEn = DateTime(2026, 1, 1, 10, 0);
      expect(NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r1', venceEn), isTrue);
      expect(NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r2', venceEn), isTrue);
    });

    test('liberar() permite volver a ofrecer el MISMO vencimiento después', () {
      final venceEn = DateTime(2026, 1, 1, 10, 0);
      expect(NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r1', venceEn), isTrue);
      NotificacionesService().liberarVencimientoTemporizadorEnPantalla();
      expect(
        NotificacionesService().marcarVencimientoTemporizadorSiNuevo('r1', venceEn),
        isTrue,
        reason: 'tras liberar (dispose de PantallaAlarma), el mismo vencimiento debe poder ofrecerse de nuevo',
      );
    });
  });

  testWidgets(
    'el listener ofrece la confirmación al descubrir un vencimiento en vivo, sin pasar por el reconciliador de arranque, '
    'y confirmar vuelve exactamente a la pantalla donde estaba el usuario',
    (tester) async {
      const rutinaId = 'r-temporizador-listener';
      final ahoraBase = DateTime(2026, 3, 10, 9, 0);
      final relojMutable = _RelojMutable(ahoraBase);
      // Todavía no venció al cargar: el objetivo es que lo detecte el
      // listener EN VIVO (vía iniciarTick(), la misma recalculación que
      // corre al volver de segundo plano), no la carga inicial desde disco.
      final venceEn = ahoraBase.add(const Duration(seconds: 30));
      final crudoTemporizador = jsonEncode({
        'rutinaId': rutinaId,
        'venceEn': venceEn.toIso8601String(),
        'duracionTotalSegundos': 600,
      });

      SharedPreferences.setMockInitialValues({
        'temporizador_rutina_activo': crudoTemporizador,
        'lista_rutinas_v2': '[${jsonEncode(_rutinaDePrueba(rutinaId).toJson())}]',
      });

      final navigatorKey = GlobalKey<NavigatorState>();
      final container = ProviderContainer(overrides: [relojProvider.overrideWithValue(relojMutable.call)]);
      addTearDown(container.dispose);

      // Mismo motivo que en pantalla_alarma_test.dart: _cargarRutinas()
      // llega a tocar el widget de pantalla de inicio, lo que bajo el reloj
      // falso de testWidgets se cuelga si no corre en una zona con tiempo
      // real.
      await tester.runAsync(() async {
        container.read(rutinaProvider.notifier);
        await container.read(rutinaProvider.notifier).esperarCargaInicial();
        container.read(temporizadorRutinaProvider); // dispara _cargarDesdeDisco (todavía no vencido)
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      expect(container.read(temporizadorRutinaProvider)?.segundosRestantes, greaterThan(0),
          reason: 'precondición: el temporizador debe cargar como TODAVÍA activo, no ya vencido');

      iniciarListenerTemporizadorRutina(container: container, navigatorKey: navigatorKey);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );

      // Simula al usuario en OTRA pantalla de la app (formulario, ajustes,
      // otra pestaña) en el momento en que vence.
      navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Formulario de rutina'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Formulario de rutina'), findsOneWidget);

      // "La app vuelve de segundo plano": el reloj avanza más allá de
      // venceEn y se recalcula, exactamente como hace didChangeAppLifecycleState
      // (resumed) en main.dart. El listener que reacciona a ese cambio de
      // estado hace `await esperarCargaInicial()` antes de decidir nada
      // (ver temporizador_rutina_listener.dart) -- ese await necesita
      // drenar su cadena de microtasks ANTES de que pumpAndSettle note que
      // hay un frame pendiente, mismo gotcha que con RutinaNotifier en
      // pantalla_alarma_test.dart: runAsync corre esa cadena en tiempo
      // real para dejarla resuelta (incluido el addPostFrameCallback ya
      // REGISTRADO) antes de pedirle a pumpAndSettle que dispare el frame
      // que finalmente lo ejecuta.
      relojMutable.ahora = venceEn.add(const Duration(seconds: 1));
      await tester.runAsync(() async {
        container.read(temporizadorRutinaProvider.notifier).iniciarTick();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.text('TEMPORIZADOR TERMINADO'), findsOneWidget,
          reason: 'el listener debe ofrecer la confirmación al descubrir el vencimiento en vivo, sin arranque de por medio');

      // El guard queda tomado mientras la pantalla sigue montada.
      expect(NotificacionesService().marcarVencimientoTemporizadorSiNuevo(rutinaId, venceEn), isFalse);

      // ensureVisible antes del tap: PantallaAlarma envuelve todo en un
      // SingleChildScrollView (ver comentario ahí sobre layouts compactos de
      // landscape) -- sin esto, si el botón cae fuera del viewport inicial
      // bajo el tamaño de pantalla por defecto de flutter_test, el tap
      // podría no registrar nada silenciosamente.
      await tester.ensureVisible(find.text('Entendido'));
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();

      expect(find.text('TEMPORIZADOR TERMINADO'), findsNothing);
      expect(find.text('Formulario de rutina'), findsOneWidget,
          reason: 'confirmar debe volver exactamente a la pantalla donde estaba el usuario, no a un HomeScreen fresco (pop, no pushAndRemoveUntil)');

      // dispose() liberó el guard de forma incondicional: este vencimiento
      // (ya confirmado, en la práctica no volvería a ofrecerse porque el
      // temporizador ya se canceló) puede volver a marcarse -- prueba
      // directa de que no queda pegado tras confirmar.
      expect(NotificacionesService().marcarVencimientoTemporizadorSiNuevo(rutinaId, venceEn), isTrue);

      final rutinaTrasConfirmar = container.read(rutinaProvider).firstWhere((r) => r.id == rutinaId);
      expect(rutinaTrasConfirmar.completada, isTrue);
      expect(container.read(temporizadorRutinaProvider), isNull);
    },
  );
}
