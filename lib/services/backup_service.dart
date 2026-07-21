import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/configuracion_provider.dart';
import '../providers/nota_provider.dart';
import '../providers/rutina_provider.dart';
import '../providers/tarea_provider.dart';
import '../providers/tema_provider.dart';

/// Excepción con un mensaje ya listo para mostrarle al usuario
/// (nunca un stacktrace crudo).
class BackupException implements Exception {
  final String mensaje;
  BackupException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Versión actual del formato de respaldo. Súbela solo si cambias la forma
/// en la que se serializan las claves de abajo, y añade la lógica de
/// migración correspondiente en [_validarVersion].
const int _versionBackupActual = 1;

const String _claveRutinas = 'lista_rutinas_v2';
const String _claveTareas = 'lista_tareas_v1';
const String _claveGrupos = 'lista_grupos_v1';
const String _claveNotas = 'lista_notas_postit_v2';
const String _claveTema = 'tema_seleccionado';
const String _claveSonidoNotificacion = 'sonido_notificacion';
const String _claveSonidoAlarma = 'sonido_alarma';

class BackupService {
  /// Lee todas las claves relevantes de SharedPreferences, las combina en
  /// un único JSON y lo escribe a un archivo temporal, que devuelve.
  Future<File> exportarBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final backup = <String, dynamic>{
        'version': _versionBackupActual,
        'fecha_exportacion': DateTime.now().toIso8601String(),
        _claveRutinas: _decodificarListaSinNotificaciones(prefs.getString(_claveRutinas)),
        _claveTareas: _decodificarLista(prefs.getString(_claveTareas)),
        _claveGrupos: _decodificarLista(prefs.getString(_claveGrupos)),
        _claveNotas: _decodificarLista(prefs.getString(_claveNotas)),
        _claveTema: prefs.getInt(_claveTema),
        _claveSonidoNotificacion: prefs.getString(_claveSonidoNotificacion),
        _claveSonidoAlarma: prefs.getString(_claveSonidoAlarma),
      };

      final String contenidoJson = jsonEncode(backup);

      final directorio = await getTemporaryDirectory();
      final fechaArchivo = DateTime.now().toIso8601String().split('T')[0];
      final archivo = File('${directorio.path}/focusflow_backup_$fechaArchivo.json');

      return await archivo.writeAsString(contenidoJson);
    } on BackupException {
      rethrow;
    } on FileSystemException {
      throw BackupException(
        'No se pudo crear el archivo de respaldo. Verifica que tengas espacio '
        'de almacenamiento disponible y los permisos necesarios.',
      );
    } catch (e) {
      throw BackupException('Ocurrió un error inesperado al generar el respaldo.');
    }
  }

  /// Genera el archivo de respaldo y abre la hoja de compartir del sistema
  /// para que el usuario lo guarde donde quiera (Drive, correo, almacenamiento
  /// local, etc.).
  Future<void> exportarYCompartirBackup() async {
    final archivo = await exportarBackup();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(archivo.path)],
        subject: 'Respaldo de FocusFlow',
        text: 'Respaldo de datos de FocusFlow.',
      ),
    );
  }

  /// Lee y valida un archivo de respaldo, y SOBRESCRIBE por completo los
  /// datos actuales en SharedPreferences con los del archivo. Luego fuerza
  /// la recarga de todos los providers relevantes y reprograma las
  /// notificaciones de rutinas desde cero en este dispositivo.
  Future<void> importarBackup(File archivo, WidgetRef ref) async {
    late final Map<String, dynamic> backup;

    try {
      final String contenido = await archivo.readAsString();
      final dynamic decodificado = jsonDecode(contenido);

      if (decodificado is! Map<String, dynamic>) {
        throw BackupException('El archivo seleccionado no tiene el formato de un respaldo de FocusFlow.');
      }
      backup = decodificado;
    } on FormatException {
      throw BackupException('El archivo seleccionado está dañado o no es un JSON válido.');
    } on FileSystemException {
      throw BackupException('No se pudo leer el archivo seleccionado. Verifica los permisos de acceso.');
    }

    _validarVersion(backup);

    try {
      final prefs = await SharedPreferences.getInstance();

      await _restaurarLista(prefs, _claveRutinas, backup[_claveRutinas]);
      await _restaurarLista(prefs, _claveTareas, backup[_claveTareas]);
      await _restaurarLista(prefs, _claveGrupos, backup[_claveGrupos]);
      await _restaurarLista(prefs, _claveNotas, backup[_claveNotas]);

      final temaGuardado = backup[_claveTema];
      if (temaGuardado is int) {
        await prefs.setInt(_claveTema, temaGuardado);
      }

      final sonidoNotificacion = backup[_claveSonidoNotificacion];
      if (sonidoNotificacion is String) {
        await prefs.setString(_claveSonidoNotificacion, sonidoNotificacion);
      }

      final sonidoAlarma = backup[_claveSonidoAlarma];
      if (sonidoAlarma is String) {
        await prefs.setString(_claveSonidoAlarma, sonidoAlarma);
      }
    } on FileSystemException {
      throw BackupException(
        'No se pudo escribir la información restaurada. Verifica que tengas '
        'espacio de almacenamiento disponible y los permisos necesarios.',
      );
    } catch (e) {
      throw BackupException('Ocurrió un error inesperado al restaurar el respaldo.');
    }

    // Recargamos cada provider desde disco para que la UI refleje los datos
    // recién importados sin necesidad de reiniciar la app.
    await ref.read(tareaProvider.notifier).recargarDesdeDisco();
    await ref.read(notaProvider.notifier).recargarDesdeDisco();
    await ref.read(temaProvider.notifier).recargarDesdeDisco();
    await ref.read(sonidoProvider.notifier).recargarDesdeDisco();

    // Los IDs de notificacionesActivas del dispositivo viejo no tienen
    // validez aquí: recargamos las rutinas (con notificacionesActivas ya
    // vacío, ver _decodificarListaSinNotificaciones) y reprogramamos todas
    // las alarmas desde cero en este dispositivo.
    await ref.read(rutinaProvider.notifier).recargarDesdeDisco();
    await ref.read(rutinaProvider.notifier).resincronizarTodasLasAlarmas();
  }

  void _validarVersion(Map<String, dynamic> backup) {
    final dynamic version = backup['version'];
    if (version == null) {
      throw BackupException('El archivo seleccionado no es un respaldo válido de FocusFlow.');
    }
    if (version != _versionBackupActual) {
      throw BackupException(
        'Este respaldo fue creado con una versión no compatible de FocusFlow '
        '(versión $version). Actualiza la app o exporta un nuevo respaldo.',
      );
    }
  }

  List<dynamic> _decodificarLista(String? valorGuardado) {
    if (valorGuardado == null) return [];
    final dynamic decodificado = jsonDecode(valorGuardado);
    return decodificado is List ? decodificado : [];
  }

  // Igual que _decodificarLista, pero para rutinas: vacía notificacionesActivas
  // y ultimaFechaProgramada de cada rutina para que un respaldo restaurado en
  // otro dispositivo nunca arrastre IDs de notificación ni un "final de
  // colchón" que no existen en el sistema operativo de este dispositivo.
  // Si dejáramos ultimaFechaProgramada con el valor viejo, el top-up
  // incremental (_rellenarColchonSiHaceFalta) podría creer que el colchón
  // sigue lleno y saltarse la reprogramación por completo tras importar.
  List<dynamic> _decodificarListaSinNotificaciones(String? valorGuardado) {
    final lista = _decodificarLista(valorGuardado);
    return lista.map((item) {
      if (item is Map<String, dynamic>) {
        return {...item, 'notificacionesActivas': <int>[], 'ultimaFechaProgramada': null};
      }
      return item;
    }).toList();
  }

  Future<void> _restaurarLista(SharedPreferences prefs, String clave, dynamic valor) async {
    if (valor is! List) return;
    await prefs.setString(clave, jsonEncode(valor));
  }
}
