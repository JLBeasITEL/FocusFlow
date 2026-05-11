import 'package:flutter_riverpod/legacy.dart' show StateNotifier, StateNotifierProvider;
import '../models/nota.dart';

class NotaNotifier extends StateNotifier<List<Nota>> {
  NotaNotifier() : super([]);

  void agregarNota(Nota nuevaNota) {
    state = [nuevaNota, ...state];
    // Aquí llamarías a: _repository.guardarNota(nuevaNota);
  }

  void eliminarNota(String id) {
    state = state.where((n) => n.id != id).toList();
    // Aquí llamarías a: _repository.borrarNota(id);
  }

  void editarNota(String id, String nuevoTexto) {
    state = [
      for (final nota in state)
        if (nota.id == id)
          Nota(
            id: nota.id,
            texto: nuevoTexto,
            colorValue: nota.colorValue,
            rotacion: nota.rotacion,
          )
        else
          nota,
    ];
  }
}

final notaProvider = StateNotifierProvider<NotaNotifier, List<Nota>>((ref) {
  return NotaNotifier();
});