import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tarea.dart';

// Almacén separado para tareas recurrentes que agotaron su límite (ver
// TareaNotifier.toggleTarea/archivarDirectamente): viven en su propia clave
// de SharedPreferences, NUNCA en lista_tareas_v1, para que la limpieza
// diaria de tareas completadas (TareaNotifier._cargarTareasInterno) no las
// alcance y las borre. Es "consultable" (TareasArchivadasScreen), no una
// papelera de un solo sentido: TareaNotifier.restaurarDesdeArchivo puede
// devolver una tarea de acá a la lista activa.
class ArchivoTareasNotifier extends Notifier<List<Tarea>> {
  static const String _storageKey = 'lista_tareas_archivadas_v1';

  @override
  List<Tarea> build() {
    _cargarArchivo();
    return [];
  }

  Future<void> _cargarArchivo() async {
    final prefs = await SharedPreferences.getInstance();
    final String? archivoJson = prefs.getString(_storageKey);
    if (archivoJson != null) {
      final List<dynamic> listaDecodificada = jsonDecode(archivoJson);
      state = listaDecodificada.map((item) => Tarea.fromJson(item)).toList();
    }
  }

  Future<void> _guardarArchivo() async {
    final prefs = await SharedPreferences.getInstance();
    final String archivoCodificado = jsonEncode(state.map((t) => t.toJson()).toList());
    await prefs.setString(_storageKey, archivoCodificado);
  }

  // Fuerza una relectura completa desde SharedPreferences. Se usa tras
  // restaurar un respaldo (mismo patrón que el resto de los providers).
  Future<void> recargarDesdeDisco() async {
    await _cargarArchivo();
  }

  Future<void> archivar(Tarea tarea) async {
    state = [...state, tarea];
    await _guardarArchivo();
  }

  // Saca la tarea del archivo y la devuelve, para que quien la pidió
  // (TareaNotifier.restaurarDesdeArchivo) la reconstruya y la reinserte en
  // la lista activa. Null si no está (ya restaurada, o id inexistente): el
  // llamador decide qué hacer en ese caso, no este notifier.
  Future<Tarea?> restaurar(String id) async {
    Tarea? encontrada;
    try {
      encontrada = state.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
    state = state.where((t) => t.id != id).toList();
    await _guardarArchivo();
    return encontrada;
  }
}

final archivoTareasProvider = NotifierProvider<ArchivoTareasNotifier, List<Tarea>>(() {
  return ArchivoTareasNotifier();
});
