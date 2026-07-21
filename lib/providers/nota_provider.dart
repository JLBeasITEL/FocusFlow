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

  void eliminarNota(String id) {
    final nuevoEstado = state.where((n) => n.id != id).toList();
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
