// Ejercita TareaNotifier.toggleTarea/deshacerRecurrente/restaurarDesdeArchivo
// con el límite de recurrencia ya cableado: el tercer caso ("agotar el
// límite completa en el lugar, como cualquier tarea normal, y la limpieza
// diaria la archiva recién al otro día") y su undo, tanto mientras sigue
// activa como ya archivada. Corre los providers reales contra
// SharedPreferences en memoria, sin reimplementar su lógica en el test
// (mismo criterio que rutina_notificaciones_test.dart), e intercepta el
// MethodChannel de flutter_local_notifications para poder afirmar qué se
// programó/canceló sin depender de un dispositivo real.
//
// Diseño (pedido explícito del usuario, 2026-09-14): la última ocurrencia de
// una recurrente debe verse tachada en la lista, igual que una tarea normal
// completada, hasta el final del día — NO desaparecer/archivarse al toque.
// El archivado real ocurre en la limpieza diaria de _cargarTareasInterno
// (la misma que hoy borra las tareas normales completadas de ayer), no en
// toggleTarea/archivarDirectamente.
import 'dart:convert';

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

  test('completar la última ocurrencia la deja tachada en la lista activa (no se archiva de inmediato)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Deja terminar el _cargarTareas() inicial de build() (fire-and-forget)
    // ANTES de escribir datos nuevos: con un delay demasiado corto, ese
    // _cargarTareas() inicial puede resolver tarde -leyendo ya los datos que
    // este test recién escribió- y "limpiarlos" como si fueran de ayer
    // (nunca se seteó ultimo_dia_limpieza_tareas), vaciando el estado que el
    // test acababa de dejar. recargarDesdeDisco() es la misma operación,
    // pero awaited explícitamente; el segundo delay le da margen al
    // fire-and-forget original (que arrancó primero) para terminar también.
    await container.read(tareaProvider.notifier).recargarDesdeDisco();
    await Future<void>.delayed(Duration.zero);

    // Insertamos directo en el estado (equivalente a addTarea sin depender
    // del formulario): addTarea también dispararía solicitarPermisosEspeciales,
    // ruido innecesario para este test.
    container.read(tareaProvider.notifier).state = [tareaAlBordeDelLimite()];
    zonedScheduleCalls.clear(); // limpiar cualquier programación de la inserción de arriba

    container.read(tareaProvider.notifier).toggleTarea('cuota-1');
    await Future<void>.delayed(Duration.zero);

    // Sigue en la lista activa, tachada — igual que cualquier tarea normal
    // completada — no desaparece ni se archiva todavía.
    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.id, 'cuota-1');
    expect(activas.first.esCompletada, isTrue);
    expect(activas.first.ocurrenciasCompletadas, 2); // 1 -> 2, agotó el tope de 2
    expect(activas.first.fechaLimiteAnterior, isNotNull);
    expect(container.read(archivoTareasProvider), isEmpty);

    // Se canceló la alarma existente, pero NO se programó una nueva: no hay
    // próxima ocurrencia que la necesite.
    expect(cancelCalls, isNotEmpty);
    expect(zonedScheduleCalls, isEmpty);
  });

  test('completar una ocurrencia que NO agota el límite sigue reprogramando (comportamiento sin cambios)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(tareaProvider.notifier).recargarDesdeDisco(); // ver comentario en el primer test
    await Future<void>.delayed(Duration.zero);

    final tarea = tareaAlBordeDelLimite().copyWith(repeticionesMaximas: 12, ocurrenciasCompletadas: 3);
    container.read(tareaProvider.notifier).state = [tarea];
    zonedScheduleCalls.clear();

    container.read(tareaProvider.notifier).toggleTarea('cuota-1');
    await Future<void>.delayed(Duration.zero);

    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.esCompletada, isFalse);
    expect(activas.first.ocurrenciasCompletadas, 4); // histórico sube igual, aunque no sea la última
    expect(container.read(archivoTareasProvider), isEmpty);
    expect(zonedScheduleCalls, isNotEmpty); // sí reprograma: hay próxima ocurrencia
  });

  test('desmarcar (uncheck) la última ocurrencia ya tachada la restaura sin pasar por el archivo', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(tareaProvider.notifier).recargarDesdeDisco(); // ver comentario en el primer test
    await Future<void>.delayed(Duration.zero);

    container.read(tareaProvider.notifier).state = [tareaAlBordeDelLimite()];
    container.read(tareaProvider.notifier).toggleTarea('cuota-1'); // completa la última ocurrencia
    await Future<void>.delayed(Duration.zero);
    expect(container.read(tareaProvider).first.esCompletada, isTrue);
    zonedScheduleCalls.clear();

    // Mismo toggleTarea, ahora "desmarcando": un simple flip de esCompletada
    // dejaría fechaLimite/contador desalineados, así que debe reconstruir
    // igual que deshacerRecurrente (ver el 4to caso en toggleTarea).
    container.read(tareaProvider.notifier).toggleTarea('cuota-1');
    await Future<void>.delayed(Duration.zero);

    final restaurada = container.read(tareaProvider).first;
    expect(restaurada.esCompletada, isFalse);
    expect(restaurada.ocurrenciasCompletadas, 1); // vuelve al valor previo a agotar el límite
    expect(restaurada.fechaLimiteAnterior, isNull);
    expect(container.read(archivoTareasProvider), isEmpty);
    expect(zonedScheduleCalls, isNotEmpty); // vuelve a estar activa: se reprograma
  });

  test('deshacerRecurrente sobre una tarea que sigue activa (mitad de ciclo) baja el contador', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(tareaProvider.notifier).recargarDesdeDisco(); // ver comentario en el primer test
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

  test('la limpieza diaria archiva las recurrentes completadas y borra el resto', () async {
    // Una recurrente que ya agotó su límite (como la dejaría toggleTarea) y
    // una tarea normal completada: deben terminar en destinos distintos.
    final recurrenteCompletada = tareaAlBordeDelLimite().copyWith(
      esCompletada: true,
      ocurrenciasCompletadas: 2,
      ocurrenciasCompletadasAnterior: 1,
      fechaLimiteAnterior: tareaAlBordeDelLimite().fechaLimite,
    );
    final tareaNormalCompletada = Tarea(id: 'normal-1', titulo: 'Comprar pan', urgenciaBase: 1, esCompletada: true);
    final tareaPendiente = Tarea(id: 'pendiente-1', titulo: 'Lavar el auto', urgenciaBase: 1);

    // Sembrado ANTES de crear el container (no con prefs.setString después):
    // así la limpieza corre una única vez, en el build() inicial de
    // TareaNotifier, en vez de competir con una segunda invocación explícita
    // de _cargarTareasInterno sobre el mismo notifier (ambas tocando
    // ref.read(archivoTareasProvider.notifier) a la vez, lo que en la
    // práctica disparaba "Ref usado después de dispose" al terminar el test
    // con la del build() todavía en vuelo, o archivaba la misma tarea dos
    // veces). Sin 'ultimo_dia_limpieza_tareas' seteado, la limpieza corre en
    // esa única carga.
    SharedPreferences.setMockInitialValues({
      'lista_tareas_v1': jsonEncode([recurrenteCompletada.toJson(), tareaNormalCompletada.toJson(), tareaPendiente.toJson()]),
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Dispara el build() inicial (única invocación de _cargarTareasInterno
    // en este test) y espera a que la limpieza+archivado terminen. Un
    // número fijo de "ticks" es frágil (esa cadena tiene varios awaits
    // reales encadenados: getInstance, el guardado de tareas, y el guardado
    // del archivo) — se hace polling en vez de adivinar cuántos hacen falta.
    container.read(tareaProvider.notifier);
    for (var intentos = 0; intentos < 20 && container.read(archivoTareasProvider).isEmpty; intentos++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.id, 'pendiente-1'); // solo sobrevive la que no estaba completada

    final archivadas = container.read(archivoTareasProvider);
    expect(archivadas, hasLength(1));
    expect(archivadas.first.id, 'cuota-1'); // la normal se descarta, la recurrente se archiva
  });

  test('restaurarDesdeArchivo devuelve una tarea ya archivada a la lista activa con el contador correcto', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    final archivada = tareaAlBordeDelLimite().copyWith(
      esCompletada: true,
      ocurrenciasCompletadas: 2,
      ocurrenciasCompletadasAnterior: 1,
      fechaLimiteAnterior: tareaAlBordeDelLimite().fechaLimite,
    );
    await container.read(archivoTareasProvider.notifier).archivar(archivada);
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

  // --- Editar un tope ya superado archiva directamente ---

  test('archivarDirectamente marca la tarea completada en el lugar, sin tocar el contador ni archivar de inmediato', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Ver comentario largo en el primer test: hay que dejar que el
    // _cargarTareas() inicial de build() (disparado por el primer .notifier
    // de abajo) termine ANTES de escribir datos nuevos.
    await container.read(tareaProvider.notifier).recargarDesdeDisco();
    await Future<void>.delayed(Duration.zero);

    // Tenía tope 12 y lleva 8; el usuario la editó bajando el tope a 6 (ya
    // superado) — así llegaría desde add_tarea_modal.dart tras confirmar.
    final tareaEditada = tareaAlBordeDelLimite().copyWith(repeticionesMaximas: 6, ocurrenciasCompletadas: 8);
    container.read(tareaProvider.notifier).state = [tareaEditada];
    zonedScheduleCalls.clear();

    container.read(tareaProvider.notifier).archivarDirectamente(tareaEditada);
    await Future<void>.delayed(Duration.zero);

    final activas = container.read(tareaProvider);
    expect(activas, hasLength(1));
    expect(activas.first.esCompletada, isTrue);
    // El contador NO sube: nada se completó, solo se reconoció que ya
    // había terminado.
    expect(activas.first.ocurrenciasCompletadas, 8);
    expect(container.read(archivoTareasProvider), isEmpty); // todavía no se archiva
    expect(cancelCalls, isNotEmpty);
    expect(zonedScheduleCalls, isEmpty); // tampoco reprograma
  });

  test('archivarDirectamente + limpieza diaria + restaurar devuelve el contador intacto (no resta 1)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(tareaProvider.notifier).recargarDesdeDisco();
    await Future<void>.delayed(Duration.zero);

    final tareaEditada = tareaAlBordeDelLimite().copyWith(repeticionesMaximas: 6, ocurrenciasCompletadas: 8);
    container.read(tareaProvider.notifier).state = [tareaEditada];
    container.read(tareaProvider.notifier).archivarDirectamente(tareaEditada);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // Simula el cambio de día: la limpieza diaria la manda al archivo.
    await container.read(tareaProvider.notifier).recargarDesdeDisco();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(tareaProvider), isEmpty);
    expect(container.read(archivoTareasProvider), hasLength(1));

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
