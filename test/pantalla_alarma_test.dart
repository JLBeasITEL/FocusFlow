// Cubre el bug reportado: al pulsar ATRÁS en PantallaAlarma con un
// temporizador de rutina vencido, el pop salía sin más -- sin cancelar el
// temporizador ni completar la rutina -- dejando el estado persistido
// {rutinaId, venceEn} intacto pero SIN confirmar, y sin ninguna vía que
// vuelva a ofrecer la confirmación hasta el próximo arranque de la app (ver
// reconciliador_temporizador_rutina.dart). El fix bloquea el atrás con
// PopScope SOLO cuando rutinaIdTemporizador != null; la rama sin
// temporizador (tareas, rutinas por horario) no tiene nada pendiente de
// confirmar y debe seguir dejando salir por atrás como siempre -- este
// archivo prueba ambos casos para que ninguno de los dos regresione.
//
// No usa dispositivo/emulador real: WakelockPlus (pigeon, sin MethodChannel
// que interceptar directamente) se reemplaza por un fake que no toca ningún
// canal de plataforma, ver wakelockPlusPlatformInstance, expuesto por el
// propio paquete @visibleForTesting; el canal de flutter_local_notifications
// se intercepta igual que en rutina_notificaciones_test.dart.
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

import 'package:app_tareas/models/rutina.dart';
import 'package:app_tareas/presentation/screens/pantalla_alarma.dart';
import 'package:app_tareas/providers/rutina_provider.dart';
import 'package:app_tareas/providers/temporizador_rutina_provider.dart';

// Sin este fake, WakelockPlus.enable()/disable() (llamados en
// initState/dispose de PantallaAlarma) intentarían cruzar el canal pigeon
// real del plugin y lanzarían una excepción en el entorno de test.
class _WakelockPlusFalso extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
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

  final List<int> idsCancelados = [];

  setUp(() async {
    idsCancelados.clear();
    wakelockPlusPlatformInstance = _WakelockPlusFalso();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canalNotificaciones,
      (MethodCall call) async {
        if (call.method == 'cancel') idsCancelados.add(call.arguments as int);
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canalAlarmaNativa,
      (MethodCall call) async => null,
    );

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canalNotificaciones, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canalAlarmaNativa, null);
  });

  testWidgets(
    'con rutinaIdTemporizador, el atrás NO cierra la pantalla ni toca el temporizador ni completa la rutina',
    (tester) async {
      const rutinaId = 'r-temporizador-1';
      final venceEn = DateTime.now().subtract(const Duration(seconds: 5));
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
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Dispara la carga de ambos providers (rutinas + temporizador) ANTES
      // de montar la pantalla, igual que hace el reconciliador de arranque
      // en producción (ver reconciliador_temporizador_rutina.dart). Va
      // dentro de runAsync porque _cargarRutinas() hace trabajo real (llega
      // a actualizar el widget de pantalla de inicio, ver logs de
      // WidgetRutinasService) que bajo el reloj falso de testWidgets se
      // queda esperando un tick que nunca llega si nada más pumpea el
      // reloj mientras tanto -- runAsync corre este bloque en una zona con
      // tiempo real, exactamente para este caso.
      await tester.runAsync(() async {
        container.read(rutinaProvider.notifier);
        await container.read(rutinaProvider.notifier).esperarCargaInicial();
        container.read(temporizadorRutinaProvider);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      expect(container.read(temporizadorRutinaProvider)?.rutinaId, equals(rutinaId),
          reason: 'precondición: el temporizador vencido debe cargarse desde disco antes de abrir la pantalla');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );

      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const PantallaAlarma(
            idAlarma: 999998,
            titulo: 'Temporizador terminado',
            cuerpo: 'Confirma que terminaste "Estirar"',
            iconoCode: 0xe000,
            rutinaIdTemporizador: rutinaId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TEMPORIZADOR TERMINADO'), findsOneWidget);

      // Intento de atrás: mismo mecanismo que dispara tanto el botón físico
      // de Android como cualquier pop programático. NOTA: maybePop() devuelve
      // true tanto si pop() ocurrió como si el PopScope lo bloqueó -- en
      // ambos casos "atendió" la solicitud, así que ese booleano no sirve
      // para distinguir los dos casos (ver Navigator.maybePop, caso
      // RoutePopDisposition.doNotPop). La señal real es si la pantalla
      // sigue montada.
      await navigatorKey.currentState!.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('TEMPORIZADOR TERMINADO'), findsOneWidget, reason: 'PopScope debe bloquear el pop: la pantalla debe seguir montada tras el intento de atrás');

      // El estado persistido sigue intacto -- SIN confirmar -- porque
      // cancelar() nunca se llamó (solo lo hace "Entendido").
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('temporizador_rutina_activo'), equals(crudoTemporizador),
          reason: 'el atrás no debe tocar el temporizador persistido sin pasar por "Entendido"');
      expect(container.read(temporizadorRutinaProvider)?.rutinaId, equals(rutinaId));

      // Tampoco se completó la rutina sola (diseño acordado: nunca se
      // completa sin pasar por toggleCompletada, que solo dispara "Entendido").
      final rutinaTrasElAtras = container.read(rutinaProvider).firstWhere((r) => r.id == rutinaId);
      expect(rutinaTrasElAtras.completada, isFalse);

      expect(idsCancelados, isEmpty, reason: 'sin "Entendido", la notificación de alarma tampoco debería cancelarse desde acá');
    },
  );

  testWidgets(
    'SIN rutinaIdTemporizador (tarea o rutina por horario), el atrás sigue cerrando la pantalla como siempre',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );

      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const PantallaAlarma(
            idAlarma: 1,
            titulo: 'Tarea pendiente',
            cuerpo: '',
            iconoCode: 0xe000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TAREA PENDIENTE'), findsOneWidget);

      await navigatorKey.currentState!.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('TAREA PENDIENTE'), findsNothing,
          reason: 'sin temporizador no hay nada pendiente de confirmar: el atrás no debe bloquearse');
      expect(find.text('Home'), findsOneWidget);
    },
  );
}
