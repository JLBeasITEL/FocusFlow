// Verifica el sistema de "top-up incremental" de notificaciones de rutinas
// (ver README, sección "Sistema de rutinas y notificaciones"): en vez de
// cancelar y reprogramar TODO en cada apertura de la app, solo debe hacerse
// trabajo nativo (zonedSchedule/cancel) cuando el colchón de 4 semanas de
// una rutina realmente lo necesita.
//
// No usa un dispositivo/emulador real: intercepta el MethodChannel que usa
// flutter_local_notifications para registrar qué se programó/canceló, y
// corre el provider real (RutinaNotifier) contra SharedPreferences en
// memoria. Esto ejercita el código de producción tal cual, sin reimplementar
// su lógica en el test.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:app_tareas/models/rutina.dart';
import 'package:app_tareas/providers/rutina_provider.dart';

// Copia mínima de RutinaNotifier._generarIdNumerico (privado, no importable)
// para poder construir en el test IDs "ya programados" realistas, con el
// mismo esquema que usa el reset completo en producción.
int _generarIdNumerico(String id) {
  int hash = 0;
  for (int i = 0; i < id.length; i++) {
    hash = (31 * hash + id.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash % 100000;
}

// Copia mínima de RutinaNotifier._calcularProximaFecha (privado, no
// importable): necesaria para que las claves de idsPorOcurrencia de las
// rutinas de prueba (ver más abajo) caigan en las mismas fechas que
// producción calcularía — SIEMPRE a partir del reloj inyectado que recibe
// como parámetro, nunca de DateTime.now(), o se reintroduce exactamente el
// no-determinismo que este archivo existe para eliminar.
DateTime _calcularProximaFechaDePrueba(DateTime ahora, int diaSemana, TimeOfDay hora) {
  int targetWeekday = diaSemana + 1; // Dart: 1=Lunes, 7=Domingo
  DateTime fecha = DateTime(ahora.year, ahora.month, ahora.day, hora.hour, hora.minute);
  while (fecha.weekday != targetWeekday || fecha.isBefore(ahora)) {
    fecha = fecha.add(const Duration(days: 1));
  }
  return fecha;
}

// Mismo formato que RutinaNotifier._claveFecha (privado, no importable).
String _claveFechaDePrueba(DateTime fecha) => fecha.toIso8601String().split('T')[0];

Rutina _rutinaDePrueba({
  required String id,
  required String titulo,
  required Map<int, TimeOfDay> horarios,
  bool completada = false,
  List<int> notificacionesActivas = const [],
  Map<String, List<int>> idsPorOcurrencia = const {},
  DateTime? ultimaFechaProgramada,
  String? descripcion,
  int racha = 0,
  int rachaPagadaHasta = 0,
  int omisionesSeguidas = 0,
  List<String> historialOmisiones = const [],
}) {
  return Rutina(
    id: id,
    titulo: titulo,
    descripcion: descripcion,
    horarios: horarios,
    iconoCode: 0xe000,
    activa: true,
    completada: completada,
    notificacionesActivas: notificacionesActivas,
    idsPorOcurrencia: idsPorOcurrencia,
    ultimaFechaProgramada: ultimaFechaProgramada,
    racha: racha,
    rachaPagadaHasta: rachaPagadaHasta,
    omisionesSeguidas: omisionesSeguidas,
    historialOmisiones: historialOmisiones,
  );
}

Future<void> _dejarQueTermineElTrabajoAsincrono() async {
  // No hay temporizadores reales de por medio (SharedPreferences y el canal
  // de notificaciones están mockeados), así que esto le da tiempo de sobra
  // a la cadena de awaits de _cargarRutinas a drenar por completo.
  await Future<void>.delayed(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel canalNotificaciones = MethodChannel('dexterous.com/flutter/local_notifications');

  final List<int> idsProgramados = [];
  final List<int> idsCancelados = [];

  setUp(() async {
    idsProgramados.clear();
    idsCancelados.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canalNotificaciones,
      (MethodCall call) async {
        switch (call.method) {
          case 'zonedSchedule':
            final args = call.arguments as Map;
            idsProgramados.add(args['id'] as int);
            return null;
          case 'cancel':
            idsCancelados.add(call.arguments as int);
            return null;
          default:
            return null;
        }
      },
    );

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canalNotificaciones, null);
  });

  test(
    '4 rutinas de prueba: solo hacen trabajo nativo las que realmente lo necesitan, sin colisiones de ID',
    () async {
      const horaFija = TimeOfDay(hour: 8, minute: 0);
      final ahora = DateTime.now();
      final diaDeHoy = ahora.weekday - 1; // convención de la app: 0=lunes..6=domingo
      final diaEnTresDias = (diaDeHoy + 3) % 7;

      // IDs con forma de UUID real (como los que genera el paquete `uuid`
      // en producción, ver pubspec.yaml) en vez de strings cortas tipo
      // 'rutina-a'/'rutina-b': con ids casi-idénticos, sus hashes también
      // quedan casi-idénticos (_generarIdNumerico es esencialmente lineal),
      // lo que puede acercar tanto las bandas de 7 IDs (una por día) de dos
      // rutinas DISTINTAS que terminen solapándose — una limitación
      // preexistente del esquema baseId+díaDeLaSemana, ajena al top-up y
      // fuera del alcance de esta tarea (ver PASO 4 en la conversación).
      // Con UUIDs reales las bandas quedan separadas por miles de unidades
      // (verificado aparte), aislando así lo que este test sí debe probar:
      // colisiones entre lo ya programado y lo nuevo agregado por el
      // relleno, PARA UNA MISMA rutina.
      const idA = '3f2a9c1e-7b4d-4e6a-9c3b-8a1f2d5e7c90';
      const idB = 'a91b7e3d-2c5f-48a1-b6d9-4e7c1a3f9b02';
      const idC = '0c6d4f8a-9e2b-41c7-8f3a-5b9d2e6c1a74';
      const idD = 'e5b8271a-6f4c-49d3-a7e1-3c8b5f9d2e61';

      // --- Rutina A: "Ejercicio" (3 días/semana), nunca gestionada con el
      // sistema nuevo -> ultimaFechaProgramada null. Debe sembrar con reset
      // completo (rama a).
      final rutinaA = _rutinaDePrueba(
        id: idA,
        titulo: 'Ejercicio',
        horarios: {0: horaFija, 2: horaFija, 4: horaFija}, // lunes, miércoles, viernes
      );

      // --- Rutina B: "Meditar" (7 días/semana), colchón de sobra (20 días,
      // >= 2 semanas). No debe hacer NINGUNA llamada nativa (rama b).
      final notificacionesPreviasB = [111, 222, 333];
      // idsPorOcurrencia no vacío es lo que le dice a _rellenarColchonSiHaceFalta
      // que B ya está gestionada por el sistema nuevo (si no, la confunde con
      // una rutina legacy y dispara un reset completo — justo la rama que este
      // caso NO debe tomar). El agrupamiento exacto por fecha no importa para
      // lo que este caso prueba (nada inspecciona su contenido), solo que
      // exista; se anota bajo la fecha de hoy (según el reloj inyectado) por
      // simplicidad.
      final idsPorOcurrenciaB = {_claveFechaDePrueba(ahora): notificacionesPreviasB};
      final ultimaFechaB = ahora.add(const Duration(days: 20));
      final rutinaB = _rutinaDePrueba(
        id: idB,
        titulo: 'Meditar',
        horarios: {for (var d = 0; d < 7; d++) d: horaFija},
        notificacionesActivas: notificacionesPreviasB,
        idsPorOcurrencia: idsPorOcurrenciaB,
        ultimaFechaProgramada: ultimaFechaB,
      );

      // --- Rutina C: "Leer" (1 día/semana), colchón corto (5 días, < 2
      // semanas). Debe rellenar SOLO lo que falta (rama c), agregando IDs
      // sin tocar los 20 que ya representan un colchón de 4 semanas
      // realista (mismo esquema que un reset completo: semana 0..3).
      const diaLectura = 6; // domingo
      const horaLectura = TimeOfDay(hour: 21, minute: 0);
      final baseIdC = _generarIdNumerico(idC);
      final idExactoC = baseIdC + diaLectura;
      // Misma fecha que produciría _calcularProximaFecha en producción para
      // este día/hora, calculada con el reloj INYECTADO (ahora) — nunca con
      // DateTime.now() — para que las claves de idsPorOcurrenciaC coincidan
      // exactamente con lo que _rellenarColchonSiHaceFalta espera encontrar
      // ya cubierto al decidir la rama c (relleno parcial) en vez de la a
      // (reset completo).
      final primeraOcurrenciaC = _calcularProximaFechaDePrueba(ahora, diaLectura, horaLectura);
      final notificacionesPreviasC = <int>[
        for (var semana = 0; semana < 4; semana++) ...[
          idExactoC + semana * 100000,
          idExactoC + semana * 100000 + 1000,
          idExactoC + semana * 100000 + 10000,
          idExactoC + semana * 100000 + 20000,
          idExactoC + semana * 100000 + 30000,
        ],
      ];
      final idsPorOcurrenciaC = {
        for (var semana = 0; semana < 4; semana++)
          _claveFechaDePrueba(primeraOcurrenciaC.add(Duration(days: 7 * semana))): [
            idExactoC + semana * 100000,
            idExactoC + semana * 100000 + 1000,
            idExactoC + semana * 100000 + 10000,
            idExactoC + semana * 100000 + 20000,
            idExactoC + semana * 100000 + 30000,
          ],
      };
      final ultimaFechaC = ahora.add(const Duration(days: 5));
      final rutinaC = _rutinaDePrueba(
        id: idC,
        titulo: 'Leer',
        horarios: const {diaLectura: horaLectura},
        notificacionesActivas: notificacionesPreviasC,
        idsPorOcurrencia: idsPorOcurrenciaC,
        ultimaFechaProgramada: ultimaFechaC,
      );

      // --- Rutina D: "Estirar" (2 días con horarios distintos, esFlexible),
      // colchón YA AGOTADO (venció hace 10 días) y completada hoy. Simula
      // el caso extremo de una app que no se abrió en semanas: debe
      // recuperarse solo con relleno (rama c), sin necesitar un reset.
      final rutinaD = _rutinaDePrueba(
        id: idD,
        titulo: 'Estirar',
        horarios: {
          diaDeHoy: const TimeOfDay(hour: 23, minute: 59),
          diaEnTresDias: const TimeOfDay(hour: 7, minute: 30),
        },
        completada: true,
        ultimaFechaProgramada: ahora.subtract(const Duration(days: 10)),
      );

      final rutinasIniciales = [rutinaA, rutinaB, rutinaC, rutinaD];
      SharedPreferences.setMockInitialValues({
        'lista_rutinas_v2': '[${rutinasIniciales.map((r) => _jsonDeRutina(r)).join(',')}]',
      });

      // ============================================================
      // PASADA 1 — primera "apertura de la app" con el nuevo sistema.
      // ============================================================
      // Reloj fijo en el mismo instante que ya capturamos arriba en `ahora`:
      // sin esto, rutina_provider.dart vuelve a llamar DateTime.now() por su
      // cuenta en varios puntos (carga, reset completo, relleno de colchón,
      // cálculo de próxima fecha), y ese segundo "ahora" puede caer en un día
      // distinto al que usaron las rutinas de prueba si el test corre cerca
      // de medianoche o bajo carga — el origen real de la falla intermitente
      // documentada en el README antes de este fix.
      final container1 = ProviderContainer(overrides: [relojProvider.overrideWithValue(() => ahora)]);
      addTearDown(container1.dispose);
      container1.read(rutinaProvider.notifier); // dispara build() -> _cargarRutinas()
      await _dejarQueTermineElTrabajoAsincrono();

      final estado1 = container1.read(rutinaProvider);
      final a1 = estado1.firstWhere((r) => r.id == idA);
      final b1 = estado1.firstWhere((r) => r.id == idB);
      final c1 = estado1.firstWhere((r) => r.id == idC);
      final d1 = estado1.firstWhere((r) => r.id == idD);

      // A: se sembró con reset completo.
      expect(a1.ultimaFechaProgramada, isNotNull, reason: 'A debe sembrar ultimaFechaProgramada');
      expect(a1.notificacionesActivas, isNotEmpty, reason: 'A debe terminar con notificaciones programadas');

      // B: intacta, cero trabajo nativo atribuible a ella.
      expect(b1.notificacionesActivas, equals(notificacionesPreviasB), reason: 'B no debe tocarse: colchón de sobra');
      expect(b1.ultimaFechaProgramada, equals(ultimaFechaB));

      // C: relleno incremental — crece, conserva lo viejo, sin duplicados.
      expect(c1.notificacionesActivas.length, greaterThan(notificacionesPreviasC.length),
          reason: 'C debe agregar IDs nuevos');
      expect(c1.notificacionesActivas.toSet().containsAll(notificacionesPreviasC), isTrue,
          reason: 'C no debe perder ningún ID previo');
      expect(c1.notificacionesActivas.toSet().length, equals(c1.notificacionesActivas.length),
          reason: 'C no debe tener IDs duplicados tras el relleno');
      expect(c1.ultimaFechaProgramada!.isAfter(ultimaFechaC), isTrue);

      // D: colchón agotado -> se recupera solo con relleno (rama c). No
      // fijamos un número de semanas exacto acá a propósito: el objetivo de
      // colchón del relleno es un literal interno de _rellenarColchonSiHaceFalta
      // (hoy 2 semanas, ver README "Deuda técnica conocida" sobre las dos
      // constantes de colchón independientes en rutina_provider.dart), así que
      // un umbral tipo "20 días" quedaría desalineado la próxima vez que ese
      // literal cambie — como ya pasó una vez. En cambio, reusamos el mismo
      // umbral de 7 días que la propia rama b usa como frontera de "colchón
      // suficiente" (rutina_provider.dart, condición `diasDeColchon >= 7`):
      // cualquier relleno real, sin importar a cuántas semanas apunte
      // internamente, tiene que dejar el colchón por encima de esa frontera,
      // o la rama b lo habría considerado "suficiente" y no habría rellenado
      // nada en absoluto.
      expect(d1.notificacionesActivas, isNotEmpty);
      expect(d1.ultimaFechaProgramada!.isAfter(ahora.add(const Duration(days: 7))), isTrue,
          reason: 'D debe terminar con el colchón por encima del umbral de "colchón suficiente"');

      // Ningún ID se programó dos veces en toda la pasada (garantía central
      // del esquema anti-colisión, ver PASO 4).
      expect(idsProgramados.toSet().length, equals(idsProgramados.length),
          reason: 'Ningún ID de notificación debe programarse dos veces en la misma pasada');

      // El relleno (C y D) nunca cancela, y A cancela una lista vacía (nada
      // que cancelar la primera vez): cero cancelaciones en toda la pasada.
      expect(idsCancelados, isEmpty, reason: 'Ni el relleno ni el primer sembrado deben cancelar nada');

      // Recuento estilo PASO 5: de las 4 rutinas activas, B se saltó por
      // completo; las otras 3 hicieron trabajo real.
      final huboTrabajo = [a1, b1, c1, d1].where((r) {
        final previo = rutinasIniciales.firstWhere((r0) => r0.id == r.id);
        return !_mismaListaDeIds(previo.notificacionesActivas, r.notificacionesActivas);
      }).length;
      expect(huboTrabajo, 3, reason: 'Solo A, C y D debían requerir trabajo real; B debía saltarse');

      // ============================================================
      // PASADA 2 — segunda "apertura" inmediatamente después: con el
      // colchón ya recargado (~4 semanas) para las 4, esta es la corrida
      // que en la práctica ocurrirá casi siempre. Debe hacer CERO llamadas
      // nativas para las 4 rutinas.
      // ============================================================
      idsProgramados.clear();
      idsCancelados.clear();

      final container2 = ProviderContainer(overrides: [relojProvider.overrideWithValue(() => ahora)]);
      addTearDown(container2.dispose);
      container2.read(rutinaProvider.notifier);
      await _dejarQueTermineElTrabajoAsincrono();

      expect(idsProgramados, isEmpty, reason: 'Segunda apertura: no debería reprogramar nada');
      expect(idsCancelados, isEmpty, reason: 'Segunda apertura: no debería cancelar nada');

      final estado2 = container2.read(rutinaProvider);
      expect(
        estado2.firstWhere((r) => r.id == idA).notificacionesActivas,
        equals(a1.notificacionesActivas),
        reason: 'El estado de A no debe cambiar en una apertura donde se salta el trabajo',
      );
    },
  );

  // ============================================================
  // Regresión: rutina_form_screen.dart reconstruía una Rutina nueva desde
  // cero al editar, en vez de derivarla de la existente. Campos que ese
  // formulario no conoce (rachaPagadaHasta, omisionesSeguidas,
  // historialOmisiones, descripcion) volvían a su valor por defecto en
  // cada edición — explotable para cobrar de más una moneda de racha ya
  // pagada, o para abaratar el costo de la próxima omisión con solo
  // cambiar el ícono o el título. El fix deriva la edición con copyWith
  // sobre la rutina existente; estos tests fijan ese comportamiento.
  // ============================================================
  test(
    'editarRutina (derivada con copyWith, como ahora hace el formulario) preserva '
    'racha, rachaPagadaHasta, omisionesSeguidas e historialOmisiones al editar solo el ícono',
    () async {
      const idRutina = '11111111-1111-1111-1111-111111111111';
      const horaFija = TimeOfDay(hour: 8, minute: 0);
      final horarios = {0: horaFija};

      final rutinaOriginal = _rutinaDePrueba(
        id: idRutina,
        titulo: 'Meditar',
        horarios: horarios,
        racha: 7,
        rachaPagadaHasta: 7,
        omisionesSeguidas: 5,
        historialOmisiones: const ['2024-01-01'],
      );

      SharedPreferences.setMockInitialValues({
        'lista_rutinas_v2': '[${_jsonDeRutina(rutinaOriginal)}]',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(rutinaProvider.notifier);
      await _dejarQueTermineElTrabajoAsincrono();

      final rutinaAntes = container.read(rutinaProvider).firstWhere((r) => r.id == idRutina);

      // Mismo patrón que ahora usa rutina_form_screen.dart al editar: derivar
      // con copyWith desde la rutina existente, cambiando solo el ícono.
      const nuevoIcono = 0xe001;
      final rutinaEditada = rutinaAntes.copyWith(
        titulo: rutinaAntes.titulo,
        horarios: rutinaAntes.horarios,
        esFlexible: rutinaAntes.esFlexible,
        iconoCode: nuevoIcono,
      );

      await notifier.editarRutina(rutinaEditada);
      await _dejarQueTermineElTrabajoAsincrono();

      final rutinaDespues = container.read(rutinaProvider).firstWhere((r) => r.id == idRutina);

      expect(rutinaDespues.iconoCode, equals(nuevoIcono));
      expect(rutinaDespues.racha, equals(7), reason: 'la racha no debe alterarse al editar');
      expect(rutinaDespues.rachaPagadaHasta, equals(7),
          reason: 'rachaPagadaHasta no debe resetearse al editar (evita cobrar la moneda de nuevo)');
      expect(rutinaDespues.omisionesSeguidas, equals(5),
          reason: 'omisionesSeguidas no debe resetearse al editar (evita abaratar el costo de omitir)');
      expect(rutinaDespues.historialOmisiones, equals(const ['2024-01-01']));
    },
  );

  test('editar una rutina borrando la descripción la deja en null', () async {
    const idRutina = '22222222-2222-2222-2222-222222222222';
    const horaFija = TimeOfDay(hour: 9, minute: 0);
    final horarios = {1: horaFija};

    final rutinaOriginal = _rutinaDePrueba(
      id: idRutina,
      titulo: 'Leer',
      horarios: horarios,
      descripcion: 'Diez páginas antes de dormir',
    );

    SharedPreferences.setMockInitialValues({
      'lista_rutinas_v2': '[${_jsonDeRutina(rutinaOriginal)}]',
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(rutinaProvider.notifier);
    await _dejarQueTermineElTrabajoAsincrono();

    final rutinaAntes = container.read(rutinaProvider).firstWhere((r) => r.id == idRutina);

    // Mismo patrón que rutina_form_screen.dart cuando el usuario deja el
    // campo de descripción vacío: limpiarDescripcion:true.
    final rutinaEditada = rutinaAntes.copyWith(
      titulo: rutinaAntes.titulo,
      horarios: rutinaAntes.horarios,
      esFlexible: rutinaAntes.esFlexible,
      iconoCode: rutinaAntes.iconoCode,
      descripcion: null,
      limpiarDescripcion: true,
    );

    await notifier.editarRutina(rutinaEditada);
    await _dejarQueTermineElTrabajoAsincrono();

    final rutinaDespues = container.read(rutinaProvider).firstWhere((r) => r.id == idRutina);
    expect(rutinaDespues.descripcion, isNull);
  });

  test('editar una rutina sin tocar la descripción la conserva', () async {
    const idRutina = '33333333-3333-3333-3333-333333333333';
    const horaFija = TimeOfDay(hour: 10, minute: 0);
    final horarios = {2: horaFija};

    final rutinaOriginal = _rutinaDePrueba(
      id: idRutina,
      titulo: 'Estirar',
      horarios: horarios,
      descripcion: 'Rutina de 10 minutos',
    );

    SharedPreferences.setMockInitialValues({
      'lista_rutinas_v2': '[${_jsonDeRutina(rutinaOriginal)}]',
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(rutinaProvider.notifier);
    await _dejarQueTermineElTrabajoAsincrono();

    final rutinaAntes = container.read(rutinaProvider).firstWhere((r) => r.id == idRutina);

    // El formulario precarga el controller con la descripción existente; si
    // el usuario no la toca, se reenvía el mismo texto con
    // limpiarDescripcion:false.
    final rutinaEditada = rutinaAntes.copyWith(
      titulo: 'Estirar (editado)',
      horarios: rutinaAntes.horarios,
      esFlexible: rutinaAntes.esFlexible,
      iconoCode: rutinaAntes.iconoCode,
      descripcion: rutinaAntes.descripcion,
      limpiarDescripcion: false,
    );

    await notifier.editarRutina(rutinaEditada);
    await _dejarQueTermineElTrabajoAsincrono();

    final rutinaDespues = container.read(rutinaProvider).firstWhere((r) => r.id == idRutina);
    expect(rutinaDespues.descripcion, equals('Rutina de 10 minutos'));
    expect(rutinaDespues.titulo, equals('Estirar (editado)'));
  });
}

bool _mismaListaDeIds(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _jsonDeRutina(Rutina r) {
  final json = r.toJson();
  final buffer = StringBuffer('{');
  var primero = true;
  json.forEach((key, value) {
    if (!primero) buffer.write(',');
    primero = false;
    buffer.write('"$key":');
    buffer.write(_jsonValor(value));
  });
  buffer.write('}');
  return buffer.toString();
}

String _jsonValor(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return '$value';
  if (value is String) return '"${value.replaceAll('"', '\\"')}"';
  if (value is List) return '[${value.map(_jsonValor).join(',')}]';
  if (value is Map) {
    final buffer = StringBuffer('{');
    var primero = true;
    value.forEach((k, v) {
      if (!primero) buffer.write(',');
      primero = false;
      buffer.write('"$k":${_jsonValor(v)}');
    });
    buffer.write('}');
    return buffer.toString();
  }
  throw ArgumentError('Tipo no soportado en _jsonValor: ${value.runtimeType}');
}
