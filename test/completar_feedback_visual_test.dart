// Cubre el diseño pedido por el usuario (2026-09-14): completar la ÚLTIMA
// ocurrencia de una tarea recurrente con límite debe MOSTRARSE como
// completada (checkbox marcado, tachado) y quedarse así en la lista activa
// — igual que cualquier tarea normal completada — en vez de desaparecer al
// toque o tras un retraso cosmético. El archivado real de verdad ocurre
// recién en la limpieza diaria (ver TareaNotifier._cargarTareasInterno y
// tarea_limite_recurrencia_provider_test.dart), no al completar. Prueba
// ambas tarjetas (TareaCard en home_screen.dart y TareaLandscapeCard), que
// no necesitan ninguna lógica propia para esto: alcanza con que
// TareaNotifier.toggleTarea deje esCompletada=true en el lugar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:app_tareas/models/tarea.dart';
import 'package:app_tareas/presentation/screens/home_screen.dart' show TareaCard;
import 'package:app_tareas/presentation/widgets/tarea_card_landscape.dart';
import 'package:app_tareas/providers/tarea_archivada_provider.dart';
import 'package:app_tareas/providers/tarea_provider.dart';
import 'package:app_tareas/providers/tema_provider.dart';

Tarea _tareaUltimaOcurrencia() {
  final fechaFutura = DateTime.now().add(const Duration(days: 5));
  return Tarea(
    id: 'cuota-1',
    titulo: 'Cuota crédito',
    urgenciaBase: 1,
    fechaLimite: fechaFutura,
    tipoRecurrencia: TipoRecurrencia.meses,
    intervalo: 1,
    diaAncla: fechaFutura.day,
    modoLimiteRecurrencia: ModoLimiteRecurrencia.repeticiones,
    repeticionesMaximas: 2,
    ocurrenciasCompletadas: 1, // completar ahora agota el límite (1+1 >= 2)
  );
}

Future<ProviderContainer> _pumpConTarea(WidgetTester tester, Widget Function(Tarea) construirTarjeta, {required double ancho}) async {
  final tarea = _tareaUltimaOcurrencia();
  final container = ProviderContainer();
  addTearDown(container.dispose);
  // Dispara y deja asentar el build() inicial (fire-and-forget) de
  // TareaNotifier ANTES de fijar el estado a mano: sin este respiro, ese
  // _cargarTareas() inicial puede resolver más tarde y pisar el estado que
  // este test recién dejó (mismo cuidado que en
  // tarea_limite_recurrencia_provider_test.dart).
  container.read(tareaProvider.notifier);
  await tester.pump();
  container.read(tareaProvider.notifier).state = [tarea];

  // TareaCard/TareaLandscapeCard reciben `tarea` como prop fija: no observan
  // tareaProvider por su cuenta (eso lo hace su padre real, home_screen.dart,
  // que sí usa ref.watch). Sin este Consumer envolvente, el checkbox nunca
  // reflejaría el cambio tras togglear, porque widget.tarea se quedaría
  // congelado en la instancia de antes del tap.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: ancho,
            child: Consumer(
              builder: (context, ref, _) {
                final actual = ref.watch(tareaProvider).firstWhere((t) => t.id == tarea.id);
                return construirTarjeta(actual);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
    await initializeDateFormatting('es');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  void ejercitarTarjeta(String nombre, Widget Function(Tarea) construirTarjeta, {required double ancho}) {
    testWidgets('$nombre: completar la última ocurrencia la tacha y la deja en la lista, sin archivarla', (tester) async {
      final container = await _pumpConTarea(tester, construirTarjeta, ancho: ancho);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      // Checkbox marcado y tachado de inmediato — sin ningún retraso que
      // esperar, porque ahora es el dato real, no una simulación visual.
      expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);

      // Sigue en la lista activa (no desaparece ni se archiva): el
      // archivado real ocurre recién en la limpieza diaria.
      final activas = container.read(tareaProvider);
      expect(activas, hasLength(1));
      expect(activas.first.esCompletada, isTrue);
      expect(activas.first.ocurrenciasCompletadas, 2);
      expect(container.read(archivoTareasProvider), isEmpty);
    });
  }

  // TareaCard está pensada para el ancho completo de la lista portrait (ver
  // memoria "testing_widgettests_gotchas": darle un ancho angosto tipo
  // landscape le desborda el Row de fecha/urgencia).
  ejercitarTarjeta('TareaCard (portrait)', (t) => TareaCard(tarea: t, tema: TemaApp.clasico), ancho: 360);
  ejercitarTarjeta('TareaLandscapeCard', (t) => TareaLandscapeCard(tarea: t, tema: TemaApp.clasico), ancho: 260);
}
