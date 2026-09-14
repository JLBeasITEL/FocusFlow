// Cubre el fix pedido por el usuario: completar la ÚLTIMA ocurrencia de una
// tarea recurrente con límite debe MOSTRARSE como completada (checkbox
// marcado, tachado) por un instante antes de archivarse — antes de este fix,
// TareaNotifier.toggleTarea archivaba en el mismo frame, sacando la tarjeta
// de la lista sin que el usuario llegara a ver ningún feedback ("desaparece
// sin más"). Ver _completarConFeedbackVisual en TareaCard (home_screen.dart)
// y TareaLandscapeCard (tarea_card_landscape.dart).
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
  container.read(tareaProvider.notifier).state = [tarea];

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: SizedBox(width: ancho, child: construirTarjeta(tarea)))),
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
    group(nombre, () {
      testWidgets('muestra tachado de inmediato y archiva recién después del retraso', (tester) async {
        final container = await _pumpConTarea(tester, construirTarjeta, ancho: ancho);

        await tester.tap(find.byType(Checkbox).first);
        await tester.pump(); // un solo frame: debe verse YA como completada

        expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
        // Todavía no se archivó de verdad: el dato real sigue sin tocar.
        expect(container.read(tareaProvider), hasLength(1));
        expect(container.read(tareaProvider).first.esCompletada, isFalse);
        expect(container.read(archivoTareasProvider), isEmpty);

        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        expect(container.read(tareaProvider), isEmpty);
        expect(container.read(archivoTareasProvider), hasLength(1));
      });

      testWidgets('tocar el checkbox dos veces seguidas durante el retraso no dispara el archivado dos veces', (tester) async {
        final container = await _pumpConTarea(tester, construirTarjeta, ancho: ancho);

        await tester.tap(find.byType(Checkbox).first);
        await tester.pump();
        await tester.tap(find.byType(Checkbox).first);
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        expect(container.read(archivoTareasProvider), hasLength(1));
      });
    });
  }

  // TareaCard está pensada para el ancho completo de la lista portrait (ver
  // memoria "testing_widgettests_gotchas": darle un ancho angosto tipo
  // landscape le desborda el Row de fecha/urgencia).
  ejercitarTarjeta('TareaCard (portrait)', (t) => TareaCard(tarea: t, tema: TemaApp.clasico), ancho: 360);
  ejercitarTarjeta('TareaLandscapeCard', (t) => TareaLandscapeCard(tarea: t, tema: TemaApp.clasico), ancho: 260);
}
