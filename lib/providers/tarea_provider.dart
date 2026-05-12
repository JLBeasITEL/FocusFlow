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

  // --- CARGAR DATOS Y LIMPIEZA AUTOMÁTICA ---
  Future<void> _cargarTareas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tareasJson = prefs.getString(_storageKey);

    if (tareasJson != null) {
      final List<dynamic> listaDecodificada = jsonDecode(tareasJson);
      List<Tarea> tareasCargadas = listaDecodificada.map((item) => Tarea.fromJson(item)).toList();

      // ==============================================================
      // LÓGICA DE LIMPIEZA ANTI-CARRERAS
      // Para hacer la prueba forzada, descomenta la línea de MODO PRUEBA
      // y comenta la de MODO NORMAL.
      // ==============================================================
      
      final hoy = DateTime.now().toIso8601String().split('T')[0]; // <-- MODO NORMAL
      
      final ultimoDiaLimpieza = prefs.getString('ultimo_dia_limpieza_tareas');

      if (ultimoDiaLimpieza != hoy) {
        // 1. Filtramos para eliminar las completadas de ayer
        tareasCargadas = tareasCargadas.where((tarea) => !tarea.esCompletada).toList();
        
        // 2. Registramos que ya limpiamos hoy
        await prefs.setString('ultimo_dia_limpieza_tareas', hoy);
        
        // 3. Asignamos la lista limpia al estado de la aplicación
        state = tareasCargadas;
        
        // 4. ¡CRÍTICO! Guardamos en la base de datos para borrar las viejas para siempre
        _guardarTareas();
        
        print('🧹 Limpieza de tareas completadas ejecutada correctamente (Día: $hoy)');
      } else {
        // Si ya se limpió hoy, simplemente cargamos las tareas normales
        state = tareasCargadas;
      }
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

  Future<void> addTarea(Tarea tarea) async {
    await NotificacionesService().solicitarPermisosEspeciales();
    state = [...state, tarea];
    _guardarTareas(); 
    NotificacionesService().programarAlertaDefinitiva(tarea);
  }

  void toggleTarea(String id) {
    state = [
      for (final tarea in state)
        if (tarea.id == id) tarea.copyWith(esCompletada: !tarea.esCompletada) else tarea,
    ];
    _guardarTareas(); 
    
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
    _guardarTareas(); 
    NotificacionesService().programarAlertaDefinitiva(tareaActualizada);
  }

  void deleteTarea(String id) {
    state = state.where((t) => t.id != id).toList();
    _guardarTareas(); 
    NotificacionesService().cancelarAlerta(id);
  }

  // Esta función se queda vacía para no romper el código de home_screen.dart
  // La limpieza ahora ocurre de forma segura dentro de _cargarTareas()
  Future<void> limpiarTareasCompletadasAlCambiarDeDia() async { }
}

// 2. El Provider moderno (NotifierProvider)
final tareaProvider = NotifierProvider<TareaNotifier, List<Tarea>>(() {
  return TareaNotifier();
});

// --- PROVIDERS DE UI MODERNOS ---

enum TipoOrden { creacion, alfabetico, urgencia, fecha }

class OrdenNotifier extends Notifier<TipoOrden> {
  @override
  TipoOrden build() => TipoOrden.creacion; 

  void cambiarOrden(TipoOrden nuevo) {
    state = nuevo;
  }
}

final ordenProvider = NotifierProvider<OrdenNotifier, TipoOrden>(() => OrdenNotifier());