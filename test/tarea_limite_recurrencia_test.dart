// Cubre el modelo puro del límite de recurrencia (sin providers ni UI):
// serialización con retrocompatibilidad hacia backups/tareas guardadas antes
// de esta feature, y los dos getters que TareaNotifier usará para decidir
// cuándo archivar (completarAgotaLimite) y para detectar una edición que baja
// el tope por debajo de lo ya completado (yaAgotoLimite).
import 'package:flutter_test/flutter_test.dart';

import 'package:app_tareas/models/tarea.dart';

void main() {
  group('Tarea - serialización de límite de recurrencia', () {
    test('toJson/fromJson hacen round-trip con modo repeticiones', () {
      final original = Tarea(
        titulo: 'Cuota crédito',
        urgenciaBase: 1,
        fechaLimite: DateTime(2026, 1, 15),
        tipoRecurrencia: TipoRecurrencia.meses,
        intervalo: 1,
        diaAncla: 15,
        modoLimiteRecurrencia: ModoLimiteRecurrencia.repeticiones,
        repeticionesMaximas: 12,
        ocurrenciasCompletadas: 4,
      );

      final restaurada = Tarea.fromJson(original.toJson());

      expect(restaurada.modoLimiteRecurrencia, ModoLimiteRecurrencia.repeticiones);
      expect(restaurada.repeticionesMaximas, 12);
      expect(restaurada.ocurrenciasCompletadas, 4);
      expect(restaurada.fechaLimiteRecurrencia, isNull);
    });

    test('toJson/fromJson hacen round-trip con modo fecha', () {
      final original = Tarea(
        titulo: 'Suscripción',
        urgenciaBase: 1,
        fechaLimite: DateTime(2026, 1, 15),
        tipoRecurrencia: TipoRecurrencia.meses,
        intervalo: 1,
        diaAncla: 15,
        modoLimiteRecurrencia: ModoLimiteRecurrencia.fecha,
        fechaLimiteRecurrencia: DateTime(2026, 12, 15),
      );

      final restaurada = Tarea.fromJson(original.toJson());

      expect(restaurada.modoLimiteRecurrencia, ModoLimiteRecurrencia.fecha);
      expect(restaurada.fechaLimiteRecurrencia, DateTime(2026, 12, 15));
      expect(restaurada.repeticionesMaximas, isNull);
    });

    test('JSON sin estos campos (tarea/backup anterior a esta feature) cae en "sin límite"', () {
      final jsonViejo = {
        'id': 'abc',
        'titulo': 'Tarea vieja',
        'urgenciaBase': 1,
        'esCompletada': false,
        'grupo': 'General',
        'tipoRecurrencia': 'meses',
        'intervalo': 1,
      };

      final tarea = Tarea.fromJson(jsonViejo);

      expect(tarea.modoLimiteRecurrencia, ModoLimiteRecurrencia.ninguno);
      expect(tarea.repeticionesMaximas, isNull);
      expect(tarea.fechaLimiteRecurrencia, isNull);
      expect(tarea.ocurrenciasCompletadas, 0);
      expect(tarea.completarAgotaLimite, isFalse);
      expect(tarea.yaAgotoLimite, isFalse);
    });

    test('un modoLimiteRecurrencia corrupto/desconocido no rompe: cae en ninguno', () {
      final jsonCorrupto = {
        'id': 'abc',
        'titulo': 'Tarea',
        'urgenciaBase': 1,
        'esCompletada': false,
        'grupo': 'General',
        'tipoRecurrencia': 'ninguna',
        'modoLimiteRecurrencia': 'algo-que-no-existe',
      };

      final tarea = Tarea.fromJson(jsonCorrupto);

      expect(tarea.modoLimiteRecurrencia, ModoLimiteRecurrencia.ninguno);
    });
  });

  group('Tarea.completarAgotaLimite', () {
    Tarea construir({
      required ModoLimiteRecurrencia modo,
      int? repeticionesMaximas,
      DateTime? fechaLimiteRecurrencia,
      int ocurrenciasCompletadas = 0,
      DateTime? fechaLimite,
      int intervaloDias = 30,
    }) {
      return Tarea(
        titulo: 'x',
        urgenciaBase: 1,
        fechaLimite: fechaLimite ?? DateTime(2026, 1, 1),
        tipoRecurrencia: TipoRecurrencia.dias,
        intervalo: intervaloDias,
        modoLimiteRecurrencia: modo,
        repeticionesMaximas: repeticionesMaximas,
        fechaLimiteRecurrencia: fechaLimiteRecurrencia,
        ocurrenciasCompletadas: ocurrenciasCompletadas,
      );
    }

    test('sin recurrencia, siempre false sin importar el modo', () {
      final tarea = Tarea(
        titulo: 'x',
        urgenciaBase: 1,
        tipoRecurrencia: TipoRecurrencia.ninguna,
        modoLimiteRecurrencia: ModoLimiteRecurrencia.repeticiones,
        repeticionesMaximas: 1,
      );
      expect(tarea.completarAgotaLimite, isFalse);
    });

    test('modo ninguno: nunca agota (comportamiento infinito de siempre)', () {
      final tarea = construir(modo: ModoLimiteRecurrencia.ninguno, ocurrenciasCompletadas: 999);
      expect(tarea.completarAgotaLimite, isFalse);
    });

    test('repeticiones: false mientras falten completaciones', () {
      final tarea = construir(modo: ModoLimiteRecurrencia.repeticiones, repeticionesMaximas: 12, ocurrenciasCompletadas: 10);
      expect(tarea.completarAgotaLimite, isFalse); // 10+1=11 < 12
    });

    test('repeticiones: true al completar la penúltima antes del tope', () {
      final tarea = construir(modo: ModoLimiteRecurrencia.repeticiones, repeticionesMaximas: 12, ocurrenciasCompletadas: 11);
      expect(tarea.completarAgotaLimite, isTrue); // 11+1=12 >= 12
    });

    test('repeticiones sin repeticionesMaximas configurado: false (dato incompleto, no agota)', () {
      final tarea = construir(modo: ModoLimiteRecurrencia.repeticiones, repeticionesMaximas: null, ocurrenciasCompletadas: 50);
      expect(tarea.completarAgotaLimite, isFalse);
    });

    test('fecha: false si la próxima ocurrencia todavía cae dentro del límite', () {
      final tarea = construir(
        modo: ModoLimiteRecurrencia.fecha,
        fechaLimite: DateTime(2026, 1, 1),
        intervaloDias: 30,
        fechaLimiteRecurrencia: DateTime(2026, 3, 1),
      );
      expect(tarea.completarAgotaLimite, isFalse); // próxima: 31 ene, sigue antes del 1 mar
    });

    test('fecha: true si la próxima ocurrencia cae después del límite', () {
      final tarea = construir(
        modo: ModoLimiteRecurrencia.fecha,
        fechaLimite: DateTime(2026, 1, 1),
        intervaloDias: 30,
        fechaLimiteRecurrencia: DateTime(2026, 1, 15),
      );
      expect(tarea.completarAgotaLimite, isTrue); // próxima: 31 ene, después del 15 ene
    });

    test('fecha sin fechaLimiteRecurrencia configurada: false', () {
      final tarea = construir(modo: ModoLimiteRecurrencia.fecha, fechaLimiteRecurrencia: null);
      expect(tarea.completarAgotaLimite, isFalse);
    });
  });

  group('Tarea.yaAgotoLimite', () {
    test('repeticiones: true cuando lo ya completado alcanza o supera el nuevo tope', () {
      final tarea = Tarea(
        titulo: 'x',
        urgenciaBase: 1,
        tipoRecurrencia: TipoRecurrencia.dias,
        intervalo: 1,
        modoLimiteRecurrencia: ModoLimiteRecurrencia.repeticiones,
        repeticionesMaximas: 6,
        ocurrenciasCompletadas: 8, // bajaron el tope de 12 a 6 con 8 ya hechas
      );
      expect(tarea.yaAgotoLimite, isTrue);
    });

    test('repeticiones: false cuando todavía no se alcanza el tope', () {
      final tarea = Tarea(
        titulo: 'x',
        urgenciaBase: 1,
        tipoRecurrencia: TipoRecurrencia.dias,
        intervalo: 1,
        modoLimiteRecurrencia: ModoLimiteRecurrencia.repeticiones,
        repeticionesMaximas: 12,
        ocurrenciasCompletadas: 8,
      );
      expect(tarea.yaAgotoLimite, isFalse);
    });

    test('fecha: true cuando la fechaLimite vigente ya pasó la nueva fecha de corte', () {
      final tarea = Tarea(
        titulo: 'x',
        urgenciaBase: 1,
        fechaLimite: DateTime(2026, 5, 1),
        tipoRecurrencia: TipoRecurrencia.meses,
        intervalo: 1,
        modoLimiteRecurrencia: ModoLimiteRecurrencia.fecha,
        fechaLimiteRecurrencia: DateTime(2026, 3, 1), // adelantaron el corte a marzo
      );
      expect(tarea.yaAgotoLimite, isTrue);
    });

    test('fecha: false cuando la fechaLimite vigente sigue antes del corte', () {
      final tarea = Tarea(
        titulo: 'x',
        urgenciaBase: 1,
        fechaLimite: DateTime(2026, 2, 1),
        tipoRecurrencia: TipoRecurrencia.meses,
        intervalo: 1,
        modoLimiteRecurrencia: ModoLimiteRecurrencia.fecha,
        fechaLimiteRecurrencia: DateTime(2026, 3, 1),
      );
      expect(tarea.yaAgotoLimite, isFalse);
    });

    test('modo ninguno: siempre false', () {
      final tarea = Tarea(titulo: 'x', urgenciaBase: 1, tipoRecurrencia: TipoRecurrencia.dias, intervalo: 1);
      expect(tarea.yaAgotoLimite, isFalse);
    });
  });
}
