import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tarea.dart';
import '../services/notificaciones_service.dart';

// 1. Usamos la sintaxis moderna 'Notifier' de Riverpod 2.0
class TareaNotifier extends Notifier<List<Tarea>> {
  static const String _storageKey = 'lista_tareas_v1';

  @override
  List<Tarea> build() {
    // Al construirse, intentamos cargar los datos guardados
    _cargarTareas();
    // Retornamos una lista vacía mientras se leen los datos del disco
    return []; 
  }

  // --- CARGAR DATOS ---
  Future<void> _cargarTareas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tareasJson = prefs.getString(_storageKey);

    if (tareasJson != null) {
      final List<dynamic> listaDecodificada = jsonDecode(tareasJson);
      state = listaDecodificada.map((item) => Tarea.fromJson(item)).toList();
    }
  }

  // --- GUARDAR DATOS (Se llama automáticamente en cada cambio) ---
  Future<void> _guardarTareas() async {
    final prefs = await SharedPreferences.getInstance();
    final String tareasCodificadas = jsonEncode(
      state.map((t) => t.toJson()).toList(),
    );
    await prefs.setString(_storageKey, tareasCodificadas);
  }

  // --- MÉTODOS DE ACCIÓN ---

  // Cambiamos 'void' por 'Future<void>' y agregamos 'async'
  Future<void> addTarea(Tarea tarea) async {
    
    // 1. ANTES de guardar la tarea, verificamos y pedimos los permisos especiales
    await NotificacionesService().solicitarPermisosEspeciales();

    // 2. Ahora sí, guardamos la tarea en la memoria y en el teléfono
    state = [...state, tarea];
    _guardarTareas(); 
    
    // 3. Programamos la alarma (ahora con la seguridad de que Android nos dejará)
    NotificacionesService().programarAlertaDefinitiva(tarea);
  }

  void toggleTarea(String id) {
    state = [
      for (final tarea in state)
        if (tarea.id == id) tarea.copyWith(esCompletada: !tarea.esCompletada) else tarea,
    ];
    
    _guardarTareas(); // Guardamos el cambio de estado
    
    final tareaModificada = state.firstWhere((t) => t.id == id);
    if (tareaModificada.esCompletada) {
      NotificacionesService().cancelarAlerta(id);
    } else {
      NotificacionesService().programarAlertaDefinitiva(tareaModificada);
    }
  }

  void updateTarea(Tarea tareaActualizada) {
    state = [
      for (final t in state)
        if (t.id == tareaActualizada.id) tareaActualizada else t,
    ];
    _guardarTareas(); // Guardamos la edición
    NotificacionesService().programarAlertaDefinitiva(tareaActualizada);
  }

  void deleteTarea(String id) {
    state = state.where((t) => t.id != id).toList();
    _guardarTareas(); // Guardamos la eliminación
    NotificacionesService().cancelarAlerta(id);
  }
}

// 2. El Provider moderno (NotifierProvider)
final tareaProvider = NotifierProvider<TareaNotifier, List<Tarea>>(() {
  return TareaNotifier();
});

// --- PROVIDERS DE UI MODERNOS ---

enum TipoOrden { creacion, alfabetico, urgencia, fecha }

class OrdenNotifier extends Notifier<TipoOrden> {
  @override
  TipoOrden build() => TipoOrden.creacion; // Estado inicial

  // Método moderno para cambiar el estado
  void cambiarOrden(TipoOrden nuevo) {
    state = nuevo;
  }
}
final ordenProvider = NotifierProvider<OrdenNotifier, TipoOrden>(() => OrdenNotifier());


enum TemaApp { clasico, zenClasico, brisaMarina, atardecerMinimalista }

class TemaNotifier extends Notifier<TemaApp> {
  @override
  TemaApp build() => TemaApp.clasico; // Estado inicial

  // Método moderno para cambiar el estado
  void cambiarTema(TemaApp nuevo) {
    state = nuevo;
  }
}
final temaProvider = NotifierProvider<TemaNotifier, TemaApp>(() => TemaNotifier());