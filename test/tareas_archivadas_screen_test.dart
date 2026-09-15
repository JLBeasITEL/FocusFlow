// Cubre la pantalla de consulta de tareas archivadas (C5): lista lo que hay
// en archivoTareasProvider, muestra el progreso neutro ("N de M" / "N
// completadas") y "Restaurar" dispara TareaNotifier.restaurarDesdeArchivo,
// devolviendo la tarea a la lista activa. No prueba la navegación desde
// Configuraciones (un simple Navigator.push de un ListTile, sin lógica
// propia que valga la pena aislar en un test).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:app_tareas/models/tarea.dart';
import 'package:app_tareas/presentation/screens/tareas_archivadas_screen.dart';
import 'package:app_tareas/providers/tarea_archivada_provider.dart';
import 'package:app_tareas/providers/tarea_provider.dart';

Tarea _tareaArchivada({
  String id = 'cuota-1',
  int ocurrenciasCompletadas = 4,
  ModoLimiteRecurrencia modo = ModoLimiteRecurrencia.repeticiones,
  int? repeticionesMaximas = 12,
}) {
  return Tarea(
    id: id,
    titulo: 'Cuota crédito',
    urgenciaBase: 1,
    grupo: 'Finanzas',
    fechaLimite: DateTime(2026, 5, 15),
    fechaLimiteAnterior: DateTime(2026, 4, 15),
    tipoRecurrencia: TipoRecurrencia.meses,
    intervalo: 1,
    diaAncla: 15,
    modoLimiteRecurrencia: modo,
    repeticionesMaximas: repeticionesMaximas,
    fechaLimiteRecurrencia: modo == ModoLimiteRecurrencia.fecha ? DateTime(2026, 12, 15) : null,
    ocurrenciasCompletadas: ocurrenciasCompletadas,
    // Como si la hubiera archivado toggleTarea al completar una ocurrencia
    // (no archivarDirectamente): el valor previo a esa completación.
    ocurrenciasCompletadasAnterior: ocurrenciasCompletadas - 1,
    esCompletada: true,
  );
}

Future<ProviderContainer> _pumpPantalla(WidgetTester tester, {Tarea? conArchivada}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (conArchivada != null) {
    await container.read(archivoTareasProvider.notifier).archivar(conArchivada);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TareasArchivadasScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  // "Restaurar" dispara restaurarDesdeArchivo, que reprograma la alarma de
  // la tarea (fire-and-forget, sin await, igual que el resto de
  // TareaNotifier). Sin este mock, esa llamada real al plugin de
  // notificaciones queda colgada indefinidamente en este entorno de test —
  // mismo canal y mismo criterio que tarea_limite_recurrencia_provider_test.dart.
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('sin tareas archivadas muestra el estado vacío', (tester) async {
    await _pumpPantalla(tester);

    expect(find.textContaining('Todavía no hay tareas archivadas'), findsOneWidget);
  });

  testWidgets('lista una tarea archivada con progreso "N de M" en modo repeticiones', (tester) async {
    await _pumpPantalla(tester, conArchivada: _tareaArchivada());

    expect(find.text('Cuota crédito'), findsOneWidget);
    expect(find.textContaining('Finanzas'), findsOneWidget);
    expect(find.textContaining('4 de 12'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Restaurar'), findsOneWidget);
  });

  testWidgets('modo fecha muestra progreso sin denominador ("N completadas")', (tester) async {
    await _pumpPantalla(
      tester,
      conArchivada: _tareaArchivada(modo: ModoLimiteRecurrencia.fecha, repeticionesMaximas: null, ocurrenciasCompletadas: 7),
    );

    expect(find.textContaining('7 completadas'), findsOneWidget);
    expect(find.textContaining('7 de'), findsNothing);
  });

  testWidgets('tocar "Restaurar" la saca del archivo y la devuelve a la lista activa', (tester) async {
    final container = await _pumpPantalla(tester, conArchivada: _tareaArchivada());

    // pump() (no un Future.delayed suelto) es lo que hace avanzar el reloj
    // falso de testWidgets: un await Future.delayed sin pump de por medio
    // se queda esperando para siempre en este binding, porque nada dispara
    // el timer fake asociado (a diferencia de un test sin widgets, donde
    // Future.delayed corre sobre el loop de eventos real).
    await tester.tap(find.widgetWithText(TextButton, 'Restaurar'));
    await tester.pumpAndSettle();

    expect(container.read(archivoTareasProvider), isEmpty);
    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.id, 'cuota-1');
    expect(activas.first.ocurrenciasCompletadas, 3); // 4 - 1, deshecho
    expect(activas.first.esCompletada, isFalse);
    // La UI se actualiza sola (ref.watch): la tarjeta desaparece de esta
    // pantalla apenas se restaura.
    expect(find.text('Cuota crédito'), findsNothing);
  });
}
