import 'package:flutter_riverpod/legacy.dart' show StateNotifier, StateNotifierProvider;
import '../models/nota.dart';

class NotaNotifier extends StateNotifier<List<Nota>> {
  NotaNotifier() : super([]);

  void agregarNota(Nota nuevaNota) {
    state = [nuevaNota, ...state];
  }

  void eliminarNota(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  // Aquí incluimos los nuevos parámetros opcionales para las listas
  void editarNota(String id, String nuevoTexto, {TipoNota? tipo, List<ItemLista>? elementosLista}) {
    state = [
      for (final nota in state)
        if (nota.id == id)
          nota.copyWith(
            texto: nuevoTexto,
            tipo: tipo,
            elementosLista: elementosLista,
          )
        else
          nota,
    ];
  }
}

final notaProvider = StateNotifierProvider<NotaNotifier, List<Nota>>((ref) {
  return NotaNotifier();
});