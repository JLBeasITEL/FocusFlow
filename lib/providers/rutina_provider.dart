import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rutina.dart';

class RutinaNotifier extends Notifier<List<Rutina>> {
  static const String _storageKey = 'lista_rutinas_v2';

  @override
  List<Rutina> build() {
    _cargarRutinas();
    return [];
  }

  Future<void> _cargarRutinas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rutinasJson = prefs.getString(_storageKey);

    if (rutinasJson != null) {
      final List<dynamic> listaDecodificada = jsonDecode(rutinasJson);
      final List<Rutina> rutinas = listaDecodificada.map((item) => Rutina.fromJson(item)).toList();

      // Comprobamos si cambió el día para reiniciar el checklist diario
      final hoy = DateTime.now().toIso8601String().split('T')[0];
      state = rutinas.map((r) {
        if (r.fechaCompletada != hoy) {
          return r.copyWith(completada: false, fechaCompletada: hoy);
        }
        return r;
      }).toList();
    }
  }

  Future<void> _guardarRutinas() async {
    final prefs = await SharedPreferences.getInstance();
    final String rutinasCodificadas = jsonEncode(state.map((r) => r.toJson()).toList());
    await prefs.setString(_storageKey, rutinasCodificadas);
  }

  void addRutina(Rutina rutina) {
    state = [...state, rutina];
    _guardarRutinas();
  }

  // --- FUNCIÓN PARA EDITAR ---
  void editarRutina(Rutina rutinaEditada) {
    state = [
      for (final r in state)
        if (r.id == rutinaEditada.id) rutinaEditada else r,
    ];
    _guardarRutinas();
  }

  void toggleActiva(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(activa: !r.activa) else r,
    ];
    _guardarRutinas();
  }

  // --- FUNCIÓN PARA MARCAR COMO COMPLETADA DIARIA ---
  void toggleCompletada(String id) {
    final hoy = DateTime.now().toIso8601String().split('T')[0];
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(
            completada: !r.completada,
            racha: !r.completada ? r.racha + 1 : (r.racha > 0 ? r.racha - 1 : 0),
            fechaCompletada: hoy,
          )
        else
          r,
    ];
    _guardarRutinas();
  }

  // Añade este método al final de tu clase RutinaNotifier
  void incrementarRacha(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(racha: r.racha + 1) else r,
    ];
    _guardarRutinas();
  }

    // En rutina_provider.dart
  void eliminarRutina(String id) {
    state = state.where((r) => r.id != id).toList();
    _guardarRutinas();
  }
}

final rutinaProvider = NotifierProvider<RutinaNotifier, List<Rutina>>(() {
  return RutinaNotifier();
});

