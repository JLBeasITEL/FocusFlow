import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nota.dart';
import '../services/widget_notas_service.dart';

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
    WidgetNotasService.actualizar();
  }

  void agregarNota(NotaPostIt nuevaNota) {
    final nuevoEstado = [nuevaNota, ...state];
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
    WidgetNotasService.actualizar();
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
    WidgetNotasService.actualizar();
    return (elemento: elemento, indice: indice);
  }

  // Reinserta una nota previamente eliminada en su posición original, para
  // el botón "Deshacer" del SnackBar de borrado.
  void restaurar(NotaPostIt elemento, int indice) {
    final nuevoEstado = List<NotaPostIt>.from(state);
    nuevoEstado.insert(indice.clamp(0, nuevoEstado.length), elemento);
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
    WidgetNotasService.actualizar();
  }

  void editarNota(String id, String nuevoTexto, {TipoNota? tipo, List<ItemLista>? elementosLista, int? colorValue, String? titulo}) {
    final nuevoEstado = [
      for (final nota in state)
        if (nota.id == id)
          nota.copyWith(texto: nuevoTexto, tipo: tipo, elementosLista: elementosLista, colorValue: colorValue, titulo: titulo)
        else
          nota,
    ];
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
    WidgetNotasService.actualizar();
  }

  // Alterna si una nota está destacada (aparece en los widgets de Notas).
  // Máximo 2 destacadas a la vez: si ya hay 2 y se intenta destacar una
  // tercera, no hace nada y devuelve false para que la UI avise al usuario
  // en vez de fallar en silencio (ver alternarDestacadaConFeedback en
  // nota_dialog.dart).
  bool alternarDestacada(String id) {
    final indice = state.indexWhere((n) => n.id == id);
    if (indice == -1) return false;
    final actual = state[indice];
    if (!actual.destacada && state.where((n) => n.destacada).length >= 2) {
      return false;
    }
    final nuevoEstado = [
      for (final nota in state)
        if (nota.id == id) nota.copyWith(destacada: !nota.destacada) else nota,
    ];
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
    WidgetNotasService.actualizar();
    return true;
  }

  // Junta las notas indicadas bajo un mismo nombre de grupo. Si el nombre
  // coincide con uno ya existente, las notas seleccionadas simplemente se
  // suman a ese grupo.
  void agruparNotas(List<String> ids, String nombreGrupo) {
    final idsSet = ids.toSet();
    final nuevoEstado = [
      for (final nota in state)
        if (idsSet.contains(nota.id)) nota.copyWith(grupoNombre: nombreGrupo) else nota,
    ];
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
  }

  // Reordena el tablero: saca la nota arrastrada de su posición actual y la
  // reinserta justo donde estaba la nota destino (soltada encima). El orden
  // en el tablero es simplemente el orden de la lista en memoria/disco, así
  // que basta con mover el elemento dentro de state.
  void moverNota(String idArrastrado, String idDestino) {
    if (idArrastrado == idDestino) return;
    final nuevoEstado = List<NotaPostIt>.from(state);
    final indiceOrigen = nuevoEstado.indexWhere((n) => n.id == idArrastrado);
    if (indiceOrigen == -1) return;
    final nota = nuevoEstado.removeAt(indiceOrigen);
    final indiceDestino = nuevoEstado.indexWhere((n) => n.id == idDestino);
    if (indiceDestino == -1) {
      // El destino no existe (borrado entre el drag y el drop): la deja
      // donde estaba en vez de perderla.
      nuevoEstado.insert(indiceOrigen.clamp(0, nuevoEstado.length), nota);
    } else {
      nuevoEstado.insert(indiceDestino, nota);
    }
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
  }

  // Saca una nota de su grupo; vuelve a mostrarse suelta en el tablero.
  void quitarDeGrupo(String id) {
    final nuevoEstado = [
      for (final nota in state)
        if (nota.id == id) nota.copyWith(grupoNombre: '') else nota,
    ];
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
  }

  // Disuelve el grupo completo: todas sus notas vuelven a quedar sueltas.
  void disolverGrupo(String nombreGrupo) {
    final nuevoEstado = [
      for (final nota in state)
        if (nota.grupoNombre == nombreGrupo) nota.copyWith(grupoNombre: '') else nota,
    ];
    state = nuevoEstado;
    _guardarNotas(nuevoEstado);
  }
}

final notaProvider = NotifierProvider<NotaNotifier, List<NotaPostIt>>(() {
  return NotaNotifier();
});
