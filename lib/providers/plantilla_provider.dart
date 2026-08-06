import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plantilla.dart';

class PlantillaNotifier extends Notifier<List<Plantilla>> {
  static const String _storageKey = 'lista_plantillas_tareas_v1';

  @override
  List<Plantilla> build() {
    _cargarPlantillas();
    return [];
  }

  Future<void> _cargarPlantillas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? plantillasJson = prefs.getString(_storageKey);
    if (plantillasJson != null) {
      final List<dynamic> listaDecodificada = jsonDecode(plantillasJson);
      state = listaDecodificada.map((item) => Plantilla.fromJson(item)).toList();
    }
  }

  Future<void> _guardarPlantillas() async {
    final prefs = await SharedPreferences.getInstance();
    final String plantillasCodificadas = jsonEncode(state.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, plantillasCodificadas);
  }

  // Fuerza una relectura completa desde SharedPreferences. Se usa tras
  // restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    await _cargarPlantillas();
  }

  Future<void> agregarPlantilla(Plantilla plantilla) async {
    state = [...state, plantilla];
    await _guardarPlantillas();
  }

  Future<void> renombrarPlantilla(String id, String nuevoNombre) async {
    state = [
      for (final p in state)
        if (p.id == id) p.copyWith(nombre: nuevoNombre) else p,
    ];
    await _guardarPlantillas();
  }

  Future<void> eliminarPlantilla(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _guardarPlantillas();
  }
}

final plantillaProvider = NotifierProvider<PlantillaNotifier, List<Plantilla>>(() {
  return PlantillaNotifier();
});
