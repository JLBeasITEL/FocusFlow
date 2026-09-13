// Ejercita TareaNotifier.toggleTarea/deshacerRecurrente/restaurarDesdeArchivo
// con el límite de recurrencia ya cableado (C4): el tercer caso ("agotar el
// límite archiva en vez de reprogramar") y su undo desde el archivo. Corre
// los providers reales contra SharedPreferences en memoria, sin reimplementar
// su lógica en el test (mismo criterio que rutina_notificaciones_test.dart),
// e intercepta el MethodChannel de flutter_local_notifications para poder
// afirmar qué se programó/canceló sin depender de un dispositivo real.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:app_tareas/models/tarea.dart';
import 'package:app_tareas/providers/tarea_archivada_provider.dart';
import 'package:app_tareas/providers/tarea_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  // Cuenta llamadas a zonedSchedule/cancel del plugin real de
  // flutter_local_notifications sin tocar ningún canal nativo de verdad:
  // NotificacionesService no expone un fake de más alto nivel, así que
  // interceptar el MethodChannel es la forma establecida en este repo (ver
  // rutina_notificaciones_test.dart) de probar su lógica de producción tal
  // cual, sin reimplementarla en el test.
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final zonedScheduleCalls = <int>[];
  final cancelCalls = <int>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    zonedScheduleCalls.clear();
    cancelCalls.clear();
    tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'zonedSchedule':
          final args = call.arguments as Map;
          zonedScheduleCalls.add(args['id'] as int);
          return null;
        case 'cancel':
          // Distinta forma según la versión resuelta del plugin: a veces un
          // int directo, a veces {'id': ...}. rutina_notificaciones_test.dart
          // asume el primero; en este entorno resultó ser el segundo.
          final argsCancel = call.arguments;
          cancelCalls.add(argsCancel is Map ? argsCancel['id'] as int : argsCancel as int);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  // Tarea recurrente mensual con fechaLimite en el futuro (para que
  // programarAlertaDefinitiva realmente encole algo), modo repeticiones con
  // tope 2 y ya con 1 completada: la próxima completación agota el límite.
  Tarea tareaAlBordeDelLimite() {
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
      ocurrenciasCompletadas: 1,
    );
  }

  test('completar la última ocurrencia archiva la tarea y no reprograma alarma', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(tareaProvider.notifier);
    await Future<void>.delayed(Duration.zero); // deja terminar build()/_cargarTareas()

    // Insertamos directo en el estado (equivalente a addTarea sin depender
    // del formulario): addTarea también dispararía solicitarPermisosEspeciales,
    // ruido innecesario para este test.
    container.read(tareaProvider.notifier).state = [tareaAlBordeDelLimite()];
    zonedScheduleCalls.clear(); // limpiar cualquier programación de la inserción de arriba

    notifier.toggleTarea('cuota-1');
    await Future<void>.delayed(Duration.zero);

    // Ya no está en la lista activa.
    expect(container.read(tareaProvider), isEmpty);

    // Se movió al archivo con el contador incrementado (1 -> 2) y el
    // respaldo para poder deshacer.
    final archivadas = container.read(archivoTareasProvider);
    expect(archivadas, hasLength(1));
    expect(archivadas.first.id, 'cuota-1');
    expect(archivadas.first.ocurrenciasCompletadas, 2);
    expect(archivadas.first.esCompletada, isTrue);
    expect(archivadas.first.fechaLimiteAnterior, isNotNull);

    // Se canceló la alarma existente, pero NO se programó una nueva: el
    // tercer caso de toggleTarea (ver comentario ahí) es justamente no
    // reprogramar cuando no hay próxima ocurrencia.
    expect(cancelCalls, isNotEmpty);
    expect(zonedScheduleCalls, isEmpty);
  });

  test('completar una ocurrencia que NO agota el límite sigue reprogramando (comportamiento sin cambios)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    final tarea = tareaAlBordeDelLimite().copyWith(repeticionesMaximas: 12, ocurrenciasCompletadas: 3);
    container.read(tareaProvider.notifier).state = [tarea];
    zonedScheduleCalls.clear();

    container.read(tareaProvider.notifier).toggleTarea('cuota-1');
    await Future<void>.delayed(Duration.zero);

    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.esCompletada, isFalse);
    expect(activas.first.ocurrenciasCompletadas, 4); // histórico sube igual, aunque no archive
    expect(container.read(archivoTareasProvider), isEmpty);
    expect(zonedScheduleCalls, isNotEmpty); // sí reprograma: hay próxima ocurrencia
  });

  test('deshacerRecurrente sobre una tarea que sigue activa baja el contador (no toca el archivo)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    final tarea = tareaAlBordeDelLimite().copyWith(repeticionesMaximas: 12, ocurrenciasCompletadas: 3);
    container.read(tareaProvider.notifier).state = [tarea];
    container.read(tareaProvider.notifier).toggleTarea('cuota-1');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(tareaProvider).first.ocurrenciasCompletadas, 4);

    container.read(tareaProvider.notifier).deshacerRecurrente('cuota-1');
    await Future<void>.delayed(Duration.zero);

    final restaurada = container.read(tareaProvider).first;
    expect(restaurada.ocurrenciasCompletadas, 3);
    expect(restaurada.fechaLimiteAnterior, isNull);
    expect(container.read(archivoTareasProvider), isEmpty);
  });

  test('restaurarDesdeArchivo devuelve la tarea archivada a la lista activa con el contador correcto', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    container.read(tareaProvider.notifier).state = [tareaAlBordeDelLimite()];
    container.read(tareaProvider.notifier).toggleTarea('cuota-1');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(tareaProvider), isEmpty);
    expect(container.read(archivoTareasProvider), hasLength(1));
    zonedScheduleCalls.clear();

    await container.read(tareaProvider.notifier).restaurarDesdeArchivo('cuota-1');
    // restaurarDesdeArchivo no espera a programarAlertaDefinitiva (fire-and-
    // forget, igual que el resto de TareaNotifier): sin este respiro, la
    // aserción de zonedScheduleCalls de abajo corre antes de que el mock
    // del canal reciba la llamada.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(archivoTareasProvider), isEmpty);
    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.ocurrenciasCompletadas, 1); // vuelve a como estaba antes de agotar el límite
    expect(activas.first.esCompletada, isFalse);
    expect(activas.first.fechaLimiteAnterior, isNull);
    expect(zonedScheduleCalls, isNotEmpty); // se reprograma al volver a estar activa
  });

  test('restaurarDesdeArchivo con un id que no existe en el archivo no hace nada', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    await container.read(tareaProvider.notifier).restaurarDesdeArchivo('no-existe');

    expect(container.read(tareaProvider), isEmpty);
    expect(container.read(archivoTareasProvider), isEmpty);
  });

  // --- C6: editar un tope ya superado archiva directamente ---

  test('archivarDirectamente mueve la tarea al archivo sin tocar el contador', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    // Tenía tope 12 y lleva 8; el usuario la editó bajando el tope a 6 (ya
    // superado) — así llegaría desde add_tarea_modal.dart tras confirmar.
    final tareaEditada = tareaAlBordeDelLimite().copyWith(repeticionesMaximas: 6, ocurrenciasCompletadas: 8);
    container.read(tareaProvider.notifier).state = [tareaEditada];
    zonedScheduleCalls.clear();

    container.read(tareaProvider.notifier).archivarDirectamente(tareaEditada);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(tareaProvider), isEmpty);
    final archivadas = container.read(archivoTareasProvider);
    expect(archivadas, hasLength(1));
    // El contador NO sube: nada se completó, solo se reconoció que ya
    // había terminado.
    expect(archivadas.first.ocurrenciasCompletadas, 8);
    expect(archivadas.first.esCompletada, isTrue);
    expect(cancelCalls, isNotEmpty);
    expect(zonedScheduleCalls, isEmpty); // tampoco reprograma, igual que _archivarPorLimiteAgotado
  });

  test('restaurar una tarea archivada por archivarDirectamente devuelve el contador intacto (no resta 1)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    final tareaEditada = tareaAlBordeDelLimite().copyWith(repeticionesMaximas: 6, ocurrenciasCompletadas: 8);
    container.read(tareaProvider.notifier).state = [tareaEditada];
    container.read(tareaProvider.notifier).archivarDirectamente(tareaEditada);
    await Future<void>.delayed(Duration.zero);

    await container.read(tareaProvider.notifier).restaurarDesdeArchivo('cuota-1');
    await Future<void>.delayed(Duration.zero);

    final restaurada = container.read(tareaProvider).first;
    // Antes del fix de ocurrenciasCompletadasAnterior, _reconstruirTrasDeshacer
    // restaba 1 sin importar el origen del archivado, lo que habría dejado
    // esto en 7 (incorrecto: acá no hubo ninguna completación que deshacer).
    expect(restaurada.ocurrenciasCompletadas, 8);
    expect(restaurada.esCompletada, isFalse);
  });
}
