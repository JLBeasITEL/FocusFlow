// Cubre el almacén de tareas archivadas (ArchivoTareasNotifier) y su
// inclusión en BackupService: infraestructura pura de este commit, todavía
// sin ningún caller real (nada archiva nada todavía; eso llega en
// TareaNotifier.toggleTarea/restaurarDesdeArchivo, en un commit posterior).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_tareas/models/tarea.dart';
import 'package:app_tareas/providers/tarea_archivada_provider.dart';
import 'package:app_tareas/services/backup_service.dart';

// getTemporaryDirectory (usado por BackupService.exportarBackup) no tiene
// implementación en el entorno de test sin este fake mínimo.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

Tarea _tareaDePrueba({String id = 'abc', int ocurrenciasCompletadas = 4}) {
  return Tarea(
    id: id,
    titulo: 'Cuota crédito',
    urgenciaBase: 1,
    fechaLimite: DateTime(2026, 4, 15),
    fechaLimiteAnterior: DateTime(2026, 3, 15),
    tipoRecurrencia: TipoRecurrencia.meses,
    intervalo: 1,
    diaAncla: 15,
    modoLimiteRecurrencia: ModoLimiteRecurrencia.repeticiones,
    repeticionesMaximas: 12,
    ocurrenciasCompletadas: ocurrenciasCompletadas,
    esCompletada: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ArchivoTareasNotifier', () {
    test('archivar persiste y un contenedor nuevo la recupera de disco', () async {
      final container1 = ProviderContainer();
      await container1.read(archivoTareasProvider.notifier).archivar(_tareaDePrueba());
      expect(container1.read(archivoTareasProvider), hasLength(1));
      container1.dispose();

      // Simula reabrir la app: un contenedor nuevo debe leer lo mismo desde
      // SharedPreferences, no depender de estado en memoria.
      final container2 = ProviderContainer();
      // build() dispara la carga async; forzamos que termine antes de leer.
      await container2.read(archivoTareasProvider.notifier).recargarDesdeDisco();
      final archivadas = container2.read(archivoTareasProvider);
      expect(archivadas, hasLength(1));
      expect(archivadas.first.id, 'abc');
      expect(archivadas.first.ocurrenciasCompletadas, 4);
      expect(archivadas.first.repeticionesMaximas, 12);
      container2.dispose();
    });

    test('restaurar saca la tarea del archivo y la devuelve', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(archivoTareasProvider.notifier);
      await notifier.archivar(_tareaDePrueba());

      final restaurada = await notifier.restaurar('abc');

      expect(restaurada, isNotNull);
      expect(restaurada!.id, 'abc');
      expect(container.read(archivoTareasProvider), isEmpty);
    });

    test('restaurar con un id que no existe devuelve null y no toca el estado', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(archivoTareasProvider.notifier);
      await notifier.archivar(_tareaDePrueba());

      final restaurada = await notifier.restaurar('no-existe');

      expect(restaurada, isNull);
      expect(container.read(archivoTareasProvider), hasLength(1));
    });
  });

  // NOTA DE ALCANCE: no se prueba BackupService.importarBackup end-to-end
  // acá. Ese método, al final de su cadena de recargas, también dispara
  // RutinaNotifier.resincronizarTodasLasAlarmas (ver backup_service.dart),
  // que llama al plugin nativo de notificaciones y CUELGA en este entorno de
  // test sin un mock de ese MethodChannel (comprobado: timeout de 10 min).
  // Mockear ese canal completo es trabajo de otro commit/otra suite (ver
  // rutina_notificaciones_test.dart, que sí lo hace para lo suyo) y no es
  // algo que este commit — solo agrega una clave nueva de passthrough —
  // necesite tocar. Se prueba en su lugar solo lo que este commit cambia de
  // verdad: que exportarBackup incluye la clave nueva, con y sin datos.
  group('BackupService.exportarBackup - tareas archivadas', () {
    test('incluye la clave del archivo, vacía, cuando nunca se archivó nada', () async {
      final archivo = await BackupService().exportarBackup();
      addTearDown(() async { try { await archivo.delete(); } catch (_) {} });

      final backup = jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;

      expect(backup.containsKey('lista_tareas_archivadas_v1'), isTrue);
      expect(backup['lista_tareas_archivadas_v1'], isEmpty);
    });

    test('incluye las tareas ya archivadas, con sus campos de límite y contador', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(archivoTareasProvider.notifier).archivar(_tareaDePrueba(id: 'origen'));

      final archivo = await BackupService().exportarBackup();
      addTearDown(() async { try { await archivo.delete(); } catch (_) {} });

      final backup = jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;
      final archivadas = backup['lista_tareas_archivadas_v1'] as List;

      expect(archivadas, hasLength(1));
      expect(archivadas.first['id'], 'origen');
      expect(archivadas.first['repeticionesMaximas'], 12);
      expect(archivadas.first['ocurrenciasCompletadas'], 4);
    });
  });
}
