// Cubre el diálogo de confirmación en el formulario (C6): editar el tope de
// una tarea recurrente por debajo de lo ya completado debe pedir
// confirmación antes de archivar, cancelar debe abortar el guardado
// completo (nada se persiste, el formulario sigue abierto), y confirmar debe archivar
// sin subir el contador histórico. Corre el widget real (AddTareaModal)
// contra providers reales y SharedPreferences en memoria, mismo criterio que
// plantillas_tarea_test.dart.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_tareas/core/app_messenger.dart';
import 'package:app_tareas/models/tarea.dart';
import 'package:app_tareas/presentation/widgets/add_tarea_modal.dart';
import 'package:app_tareas/providers/tarea_archivada_provider.dart';
import 'package:app_tareas/providers/tarea_provider.dart';

Tarea _tareaTope12Con8Completadas() {
  final fechaFutura = DateTime(2026, 12, 15, 23, 59);
  return Tarea(
    id: 'cuota-1',
    titulo: 'Cuota crédito',
    urgenciaBase: 1,
    fechaLimite: fechaFutura,
    tipoRecurrencia: TipoRecurrencia.meses,
    intervalo: 1,
    diaAncla: 15,
    modoLimiteRecurrencia: ModoLimiteRecurrencia.repeticiones,
    repeticionesMaximas: 12,
    ocurrenciasCompletadas: 8,
  );
}

Future<ProviderContainer> _abrirEdicion(WidgetTester tester, Tarea tarea) async {
  SharedPreferences.setMockInitialValues({
    'lista_tareas_v1': jsonEncode([tarea.toJson()]),
  });

  final container = ProviderContainer();
  addTearDown(container.dispose);

  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddTareaModal(tareaAEditar: tarea),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // updateTarea/archivarDirectamente llaman a NotificacionesService: sin
  // mockear este canal, la llamada real cuelga bajo testWidgets (ver
  // [[testing_widgettests_gotchas]] en memoria) en vez de fallar rápido.
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('bajar el tope por debajo de lo completado pide confirmación antes de guardar', (tester) async {
    await _abrirEdicion(tester, _tareaTope12Con8Completadas());

    expect(find.text('Veces'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Veces'), '6');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('¿Archivar esta tarea?'), findsOneWidget);
  });

  testWidgets('cancelar el diálogo aborta todo el guardado: nada se persiste, el formulario sigue abierto', (tester) async {
    final container = await _abrirEdicion(tester, _tareaTope12Con8Completadas());

    await tester.enterText(find.widgetWithText(TextField, 'Veces'), '6');
    await tester.pumpAndSettle();
    // Cambiamos también el título, para confirmar que ESE cambio tampoco se
    // guarda al cancelar (el guardado se aborta completo, no solo el tope).
    await tester.enterText(find.widgetWithText(TextField, '¿Qué hay que hacer?'), 'Cuota crédito (editado)');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar').last);
    await tester.pumpAndSettle();

    // El diálogo se cerró, pero el formulario (con el título editado)
    // sigue abierto: no hubo Navigator.pop del bottom sheet.
    expect(find.text('¿Archivar esta tarea?'), findsNothing);
    expect(find.widgetWithText(TextField, '¿Qué hay que hacer?'), findsOneWidget);

    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.titulo, 'Cuota crédito'); // sin editar
    expect(activas.first.repeticionesMaximas, 12); // sin editar
    expect(activas.first.ocurrenciasCompletadas, 8);
    expect(container.read(archivoTareasProvider), isEmpty);
  });

  testWidgets('confirmar archiva la tarea sin subir el contador histórico', (tester) async {
    final container = await _abrirEdicion(tester, _tareaTope12Con8Completadas());

    await tester.enterText(find.widgetWithText(TextField, 'Veces'), '6');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Archivar'));
    await tester.pumpAndSettle();

    // El formulario se cerró (guardado "exitoso", en el sentido de que se
    // procesó la edición, aunque el resultado sea un archivado).
    expect(find.text('¿Qué hay que hacer?'), findsNothing);

    // Se marca completada EN EL LUGAR (como cualquier tarea normal
    // completada) — no se archiva de inmediato, eso ocurre recién en la
    // limpieza diaria (ver tarea_limite_recurrencia_provider_test.dart).
    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.repeticionesMaximas, 6);
    expect(activas.first.ocurrenciasCompletadas, 8); // no incrementó
    expect(activas.first.esCompletada, isTrue);
    expect(container.read(archivoTareasProvider), isEmpty);
  });
}
