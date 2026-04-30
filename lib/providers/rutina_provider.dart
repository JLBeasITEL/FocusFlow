import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rutina.dart';
// import '../services/notificaciones_service.dart'; // Lo usaremos en el siguiente paso

class RutinaNotifier extends Notifier<List<Rutina>> {
  static const String _storageKey = 'lista_rutinas_v1';

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
      state = listaDecodificada.map((item) => Rutina.fromJson(item)).toList();
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
    // TODO: Llamar al servicio de notificaciones semanales
  }

  void toggleActiva(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(activa: !r.activa) else r,
    ];
    _guardarRutinas();
    // TODO: Activar/Desactivar alarma nativa
  }

  void incrementarRacha(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(racha: r.racha + 1) else r,
    ];
    _guardarRutinas();
  }
}

final rutinaProvider = NotifierProvider<RutinaNotifier, List<Rutina>>(() {
  return RutinaNotifier();
});