import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nota.dart';

class NotaNotifier extends Notifier<List<NotaPostIt>> {
  static const String _storageKey = 'lista_notas_postit_v2';

  @override
  List<NotaPostIt> build() {
    _cargarNotas();
    return [];
  }

  Future<void> _cargarNotas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? notasJson = prefs.getString(_storageKey);
      if (notasJson != null) {
        final List<dynamic> listaDecodificada = jsonDecode(notasJson);
        state = listaDecodificada.map((item) => NotaPostIt.fromMap(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Error al cargar notas offline: $e');
    }
  }

  Future<void> _guardarNotas(List<NotaPostIt> nuevasNotas) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String notasJson = jsonEncode(nuevasNotas.map((n) => n.toMap()).toList());
      await prefs.setString(_storageKey, notasJson);
    } catch (e) {
      debugPrint('Error al persistir notas offline: $e');
    }
  }

  // Fuerza una relectura completa desde SharedPreferences, descartando el
  // estado en memoria. Se usa tras restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    await _cargarNotas();
  }

  void agregarNota(NotaPostIt nuevaNota) {
    final nuevoEstado = [nuevaNota, ...state];
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
  }

  // Elimina y devuelve los datos necesarios para deshacer (el elemento tal
  // cual estaba, con su checklist completa, y su índice original). Devuelve
  // null si el id no existe.
  ({NotaPostIt elemento, int indice})? eliminarConDeshacer(String id) {
    final indice = state.indexWhere((n) => n.id == id);
    if (indice == -1) return null;
    final elemento = state[indice];
    final nuevoEstado = List<NotaPostIt>.from(state)..removeAt(indice);
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
    return (elemento: elemento, indice: indice);
  }

  // Reinserta una nota previamente eliminada en su posición original, para
  // el botón "Deshacer" del SnackBar de borrado.
  void restaurar(NotaPostIt elemento, int indice) {
    final nuevoEstado = List<NotaPostIt>.from(state);
    nuevoEstado.insert(indice.clamp(0, nuevoEstado.length), elemento);
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
  }

  void editarNota(String id, String nuevoTexto, {TipoNota? tipo, List<ItemLista>? elementosLista, int? colorValue}) {
    final nuevoEstado = [
      for (final nota in state)
        if (nota.id == id)
          nota.copyWith(texto: nuevoTexto, tipo: tipo, elementosLista: elementosLista, colorValue: colorValue)
        else
          nota,
    ];
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
  }
}

final notaProvider = NotifierProvider<NotaNotifier, List<NotaPostIt>>(() {
  return NotaNotifier();
});
