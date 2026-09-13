import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tarea.dart';
import '../services/notificaciones_service.dart';
import '../services/widget_tareas_service.dart';
import '../services/widget_progreso_service.dart';
import 'tarea_archivada_provider.dart';

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
  // Envuelto en try/catch (igual que NotaNotifier._cargarNotas): sin esto,
  // cualquier excepción imprevista durante la carga o la limpieza diaria
  // queda sin capturar. Eso es especialmente grave cuando esta función se
  // invoca desde BackupService.importarBackup, donde es un eslabón de una
  // cadena secuencial de recargas de varios providers: una excepción acá
  // podría impedir que los providers siguientes se recarguen, dejándolos
  // con el estado viejo en memoria aunque los datos ya estén bien en disco.
  Future<void> _cargarTareas() async {
    try {
      await _cargarTareasInterno();
    } catch (e) {
      debugPrint('Error al cargar tareas: $e');
    }
  }

  Future<void> _cargarTareasInterno() async {
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
    // Mantiene el widget de pantalla de inicio de Tareas en sync con cada
    // creación/edición/completado, ya que todos pasan por este método.
    WidgetTareasService.actualizar();
    // El anillo de Tareas del widget de Progreso también depende de este
    // storage (total y completadas), así que se recalcula junto con Tareas.
    WidgetProgresoService.actualizar();
  }

  // Fuerza una relectura completa desde SharedPreferences, descartando el
  // estado en memoria. Se usa tras restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    await _cargarTareas();
  }

  // Reprograma desde cero las alertas de TODAS las tareas pendientes con
  // fecha límite (incluidas las de cambio de nivel de urgencia, ver
  // NotificacionesService.programarAlertaDefinitiva). Equivalente, para
  // tareas, de RutinaNotifier.resincronizarTodasLasAlarmas: hace falta
  // llamarla junto con esa cada vez que se use
  // NotificacionesService().limpiarTodasLasAlarmasDelSistema() (el botón
  // "Reparar notificaciones" y la limpieza única de "fantasmas_borrados" al
  // abrir la app), porque cancelAll() no distingue entre alarmas de rutinas
  // y de tareas: sin este método, esa limpieza dejaba SIN NINGUNA alerta
  // programada a todas las tareas hasta que el usuario las editara o
  // marcara/desmarcara una por una.
  Future<void> resincronizarTodasLasAlarmas() async {
    for (final tarea in state) {
      if (!tarea.esCompletada && tarea.fechaLimite != null) {
        await NotificacionesService().programarAlertaDefinitiva(tarea);
      }
    }
  }

  // --- MÉTODOS DE ACCIÓN ---

  Future<void> addTarea(Tarea tarea) async {
    await NotificacionesService().solicitarPermisosEspeciales();
    state = [...state, tarea];
    _guardarTareas(); 
    NotificacionesService().programarAlertaDefinitiva(tarea);
  }

  // Tareas recurrentes: al completarlas (false -> true) NUNCA se persiste
  // esCompletada = true mientras sigan activas. En su lugar, en el MISMO
  // copyWith se recalcula fechaLimite con siguienteFecha() y esCompletada
  // vuelve a false — atómicamente, para que una tarea recurrente que sigue
  // viva jamás quede guardada en estado "completada" y termine borrada por
  // la limpieza diaria de _cargarTareasInterno (ver comentario ahí).
  // fechaLimiteAnterior guarda la fecha vieja para poder deshacer (ver
  // deshacerRecurrente) y para que WidgetProgresoService cuente el día como
  // completado. ocurrenciasCompletadas sube en CUALQUIER completación de una
  // recurrente (siga o se archive): es histórico real (ver Tarea, comentario
  // del campo), no una cuenta que solo importe si hay límite puesto.
  //
  // Hay un tercer caso, además de "sigue" y "no recurrente / des-completando":
  // la ocurrencia que se completa agota el límite de la recurrencia (ver
  // Tarea.completarAgotaLimite). Ahí no hay "siguiente fecha" que valga: la
  // tarea se archiva (_archivarPorLimiteAgotado) y esta función corta antes
  // de tocar `state` con el resto de la lógica de abajo.
  void toggleTarea(String id) {
    final tareaActual = state.firstWhere((t) => t.id == id);
    final bool completando = !tareaActual.esCompletada;
    final bool esRecurrente = tareaActual.tipoRecurrencia != TipoRecurrencia.ninguna;

    if (completando && esRecurrente && tareaActual.completarAgotaLimite) {
      _archivarPorLimiteAgotado(tareaActual);
      return;
    }

    final DateTime? nuevaFecha = completando && esRecurrente ? tareaActual.siguienteFecha() : null;
    final bool completandoRecurrente = nuevaFecha != null;

    state = [
      for (final tarea in state)
        if (tarea.id == id)
          completandoRecurrente
              ? tarea.copyWith(
                  fechaLimite: nuevaFecha,
                  fechaLimiteAnterior: tarea.fechaLimite,
                  esCompletada: false,
                  ocurrenciasCompletadas: tarea.ocurrenciasCompletadas + 1,
                  // Respalda el checklist marcado antes de resetearlo, para que
                  // deshacerRecurrente pueda devolverlo. null (no []) cuando la
                  // tarea no tiene subtareas, para no dejar un respaldo vacío
                  // sin sentido persistido.
                  subtareasAnterior: tarea.subtareas.isEmpty ? null : tarea.subtareas,
                  subtareas: tarea.subtareas.map((s) => s.copyWith(completado: false)).toList(),
                )
              : tarea.copyWith(esCompletada: !tarea.esCompletada)
        else
          tarea,
    ];
    _guardarTareas();

    final tareaModificada = state.firstWhere((t) => t.id == id);
    if (completandoRecurrente) {
      // Reprograma desde cero con la nueva fechaLimite: la auditoría previa
      // confirmó que programarAlertaDefinitiva ya cancela lo anterior y
      // recalcula todo, así que basta con llamarla de nuevo.
      NotificacionesService().programarAlertaDefinitiva(tareaModificada);
    } else if (tareaModificada.esCompletada) {
      NotificacionesService().cancelarAlerta(id);
    } else {
      NotificacionesService().programarAlertaDefinitiva(tareaModificada);
    }
  }

  // Archiva una tarea recurrente que acaba de agotar su límite: suma la
  // completación de hoy al histórico, respalda fechaLimite/subtareas
  // vigentes (mismo propósito que en el caso "sigue": permitir deshacer, ver
  // restaurarDesdeArchivo) y la saca de la lista activa hacia el archivo. A
  // propósito NO llama a programarAlertaDefinitiva: no hay una próxima
  // ocurrencia que vaya a necesitar una alarma, así que solo se cancela la
  // que ya existía.
  void _archivarPorLimiteAgotado(Tarea tarea) {
    final archivada = tarea.copyWith(
      ocurrenciasCompletadas: tarea.ocurrenciasCompletadas + 1,
      fechaLimiteAnterior: tarea.fechaLimite,
      subtareasAnterior: tarea.subtareas.isEmpty ? null : tarea.subtareas,
      esCompletada: true,
    );
    state = state.where((t) => t.id != tarea.id).toList();
    _guardarTareas();
    ref.read(archivoTareasProvider.notifier).archivar(archivada);
    NotificacionesService().cancelarAlerta(tarea.id);
  }

  // Reconstruye una tarea recurrente a como estaba justo antes de su última
  // completación, deshaciendo también el contador histórico. Lógica
  // compartida por deshacerRecurrente y restaurarDesdeArchivo: cada uno
  // decide DÓNDE buscar la tarea de origen y DÓNDE deja el resultado (ver
  // comentario de cada uno para por qué están separados en vez de fundirse
  // en un solo método que decida según dónde encuentra la tarea).
  Tarea _reconstruirTrasDeshacer(Tarea tarea) {
    return tarea.copyWith(
      fechaLimite: tarea.fechaLimiteAnterior,
      fechaLimiteAnterior: null,
      subtareas: tarea.subtareasAnterior ?? tarea.subtareas,
      subtareasAnterior: null,
      esCompletada: false,
      ocurrenciasCompletadas: tarea.ocurrenciasCompletadas - 1,
    );
  }

  // Deshace la última completación de una tarea recurrente QUE SIGUE
  // ACTIVA (todavía en `state`): el botón de deshacer de la tarjeta
  // (RutinaCard/TareaCardLandscape), que nunca sale de la lista activa. NO
  // busca en el archivo — para eso está restaurarDesdeArchivo, invocado
  // desde un contexto distinto (la pantalla de archivo) con una expectativa
  // distinta (traer de vuelta algo que ya no está en la lista). Buscar en
  // los dos lugares y decidir según dónde aparece sería más corto, pero
  // frágil: cada contexto sabe de antemano dónde tiene que estar la tarea, y
  // mezclar los dos vuelve invisible un id equivocado o un estado a medio
  // archivar en cualquiera de los dos flujos.
  void deshacerRecurrente(String id) {
    final tarea = state.firstWhere((t) => t.id == id);
    if (tarea.fechaLimiteAnterior == null) return;

    final restaurada = _reconstruirTrasDeshacer(tarea);
    state = [
      for (final t in state)
        if (t.id == id) restaurada else t,
    ];
    _guardarTareas();
    NotificacionesService().programarAlertaDefinitiva(restaurada);
  }

  // Restaura desde el archivo una tarea que agotó su límite (o que
  // archivarDirectamente archivó al editar el tope por debajo de lo ya
  // completado): la invoca la pantalla de tareas archivadas. Ver el
  // comentario de deshacerRecurrente para por qué esto es un método
  // separado en vez de una rama de esa misma función.
  Future<void> restaurarDesdeArchivo(String id) async {
    final tarea = await ref.read(archivoTareasProvider.notifier).restaurar(id);
    if (tarea == null || tarea.fechaLimiteAnterior == null) return;

    final restaurada = _reconstruirTrasDeshacer(tarea);
    state = [...state, restaurada];
    _guardarTareas();
    NotificacionesService().programarAlertaDefinitiva(restaurada);
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

  List<String> obtenerGruposExistentes() {
    final gruposEnUso = state.map((t) => t.grupo).toSet();
    // Combinamos el orden de grupos guardado con los que están en uso
    final gruposGuardados = ref.read(ordenGruposProvider);
    final todosLosGrupos = <String>{...gruposGuardados, ...gruposEnUso}.toList();
    if (!todosLosGrupos.contains('General')) {
      todosLosGrupos.insert(0, 'General');
    }
    return todosLosGrupos;
  }

  Future<void> registrarGrupoPersistente(String nuevoGrupo) async {
    await ref.read(ordenGruposProvider.notifier).agregar(nuevoGrupo);
  }

  // Renombra un grupo existente y reasigna todas las tareas que lo usaban.
  Future<void> renombrarGrupo(String grupoAnterior, String grupoNuevoRaw) async {
    final grupoNuevo = grupoNuevoRaw.trim();
    if (grupoNuevo.isEmpty || grupoNuevo == grupoAnterior) return;

    state = [
      for (final t in state)
        if (t.grupo == grupoAnterior) t.copyWith(grupo: grupoNuevo) else t,
    ];
    _guardarTareas();

    await ref.read(ordenGruposProvider.notifier).renombrar(grupoAnterior, grupoNuevo);
    await ref.read(gruposColapsadosProvider.notifier).renombrar(grupoAnterior, grupoNuevo);
  }

  // Elimina un grupo; las tareas que lo usaban pasan a 'General'.
  // El grupo 'General' no puede eliminarse.
  Future<void> eliminarGrupo(String grupo) async {
    if (grupo == 'General') return;

    state = [
      for (final t in state)
        if (t.grupo == grupo) t.copyWith(grupo: 'General') else t,
    ];
    _guardarTareas();

    await ref.read(ordenGruposProvider.notifier).eliminar(grupo);
    await ref.read(gruposColapsadosProvider.notifier).eliminar(grupo);
  }

  // --- MÉTODOS DE SUBTAREAS ---
  // Ninguno de estos dispara NotificacionesService: las subtareas no afectan
  // urgencia ni fechaLimite, así que no hay alarma que reprogramar/cancelar.

  void agregarSubtarea(String tareaId, String texto) {
    final textoLimpio = texto.trim();
    if (textoLimpio.isEmpty) return;

    state = [
      for (final tarea in state)
        if (tarea.id == tareaId)
          tarea.copyWith(subtareas: [...tarea.subtareas, ItemSubtarea(texto: textoLimpio)])
        else
          tarea,
    ];
    _guardarTareas();
  }

  void toggleSubtarea(String tareaId, String subtareaId) {
    state = [
      for (final tarea in state)
        if (tarea.id == tareaId)
          tarea.copyWith(subtareas: [
            for (final sub in tarea.subtareas)
              if (sub.id == subtareaId) ItemSubtarea(id: sub.id, texto: sub.texto, completado: !sub.completado) else sub,
          ])
        else
          tarea,
    ];
    _guardarTareas();
  }

  void eliminarSubtarea(String tareaId, String subtareaId) {
    state = [
      for (final tarea in state)
        if (tarea.id == tareaId)
          tarea.copyWith(subtareas: tarea.subtareas.where((s) => s.id != subtareaId).toList())
        else
          tarea,
    ];
    _guardarTareas();
  }

  void reordenarSubtareas(String tareaId, int oldIndex, int newIndex) {
    state = [
      for (final tarea in state)
        if (tarea.id == tareaId)
          tarea.copyWith(subtareas: _moverEnLista(tarea.subtareas, oldIndex, newIndex))
        else
          tarea,
    ];
    _guardarTareas();
  }

  // Acepta oldIndex/newIndex tal como los entrega ReorderableListView.onReorder
  // (sin el ajuste manual de -1 que esa API exige al mover hacia abajo).
  List<ItemSubtarea> _moverEnLista(List<ItemSubtarea> lista, int oldIndex, int newIndex) {
    final nuevaLista = List<ItemSubtarea>.from(lista);
    var destino = newIndex;
    if (destino > oldIndex) destino -= 1;
    final item = nuevaLista.removeAt(oldIndex);
    nuevaLista.insert(destino, item);
    return nuevaLista;
  }
}

// 2. El Provider moderno (NotifierProvider)
final tareaProvider = NotifierProvider<TareaNotifier, List<Tarea>>(() {
  return TareaNotifier();
});

// --- ORDEN DE GRUPOS (CARPETAS) ---
// Guarda el orden en que el usuario quiere ver los grupos de tareas.
// Vive en su propio provider (y no como campo privado de TareaNotifier)
// para que la UI pueda observarlo (ref.watch) y repintarse cuando el
// usuario arrastra un grupo para reordenarlo.
class OrdenGruposNotifier extends Notifier<List<String>> {
  static const String _key = 'lista_grupos_v1';

  @override
  List<String> build() {
    _cargarOrden();
    return ['General'];
  }

  Future<void> _cargarOrden() async {
    final prefs = await SharedPreferences.getInstance();
    final gruposJson = prefs.getString(_key);
    if (gruposJson != null) {
      state = List<String>.from(jsonDecode(gruposJson));
    }
  }

  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state));
  }

  // Fuerza una relectura completa desde SharedPreferences. Se usa tras
  // restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    await _cargarOrden();
  }

  // Agrega un grupo nuevo al final del orden guardado, si aún no existe.
  Future<void> agregar(String grupo) async {
    if (state.contains(grupo)) return;
    state = [...state, grupo];
    await _guardar();
  }

  Future<void> renombrar(String anterior, String nuevo) async {
    if (!state.contains(anterior)) {
      await agregar(nuevo);
      return;
    }
    state = [for (final g in state) if (g == anterior) nuevo else g];
    await _guardar();
  }

  Future<void> eliminar(String grupo) async {
    state = state.where((g) => g != grupo).toList();
    await _guardar();
  }

  // Reordena el grupo arrastrado dentro de la lista completa de grupos,
  // a partir de oldIndex/newIndex recibidos de ReorderableListView, que
  // apuntan a "visibles" (los grupos que tienen tareas y se ven en pantalla,
  // que pueden ser menos que el total de grupos guardados). Los grupos
  // ocultos (sin tareas visibles ahora) mantienen su posición relativa: se
  // ubica al grupo arrastrado justo después del grupo visible que quedó
  // inmediatamente antes de él tras el arrastre.
  Future<void> reordenarVisibles(List<String> visiblesAntes, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final grupoMovido = visiblesAntes[oldIndex];

    final visiblesDespues = List<String>.from(visiblesAntes);
    var destino = newIndex;
    if (destino > oldIndex) destino -= 1;
    visiblesDespues.removeAt(oldIndex);
    visiblesDespues.insert(destino, grupoMovido);

    final indiceEnVisibles = visiblesDespues.indexOf(grupoMovido);
    final anterior = indiceEnVisibles == 0 ? null : visiblesDespues[indiceEnVisibles - 1];

    final listaCompleta = List<String>.from(state)..remove(grupoMovido);
    if (anterior == null) {
      listaCompleta.insert(0, grupoMovido);
    } else {
      final posAnterior = listaCompleta.indexOf(anterior);
      listaCompleta.insert(posAnterior + 1, grupoMovido);
    }

    state = listaCompleta;
    await _guardar();
  }
}

final ordenGruposProvider = NotifierProvider<OrdenGruposNotifier, List<String>>(() {
  return OrdenGruposNotifier();
});

// --- ESTADO ABIERTO/CERRADO DE GRUPOS (CARPETAS) ---
// Guarda qué carpetas dejó minimizadas el usuario, para que sobrevivan al
// reinicio de la app. Ausencia de un grupo en el set = carpeta abierta
// (mismo comportamiento que había antes de persistir esto), así que un
// grupo nuevo siempre aparece abierto sin necesidad de inicializarlo acá.
// El nombre del grupo es la llave (ver Tarea.grupo en models/tarea.dart:
// no existe un id de grupo separado), por eso renombrarGrupo/eliminarGrupo
// en TareaNotifier avisan a este notifier para no dejar basura ni perder
// el estado al renombrar.
class GruposColapsadosNotifier extends Notifier<Set<String>> {
  static const String _key = 'tareas_grupos_colapsados_v1';

  @override
  Set<String> build() {
    _cargar();
    return {};
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_key);
    if (guardado != null) {
      state = Set<String>.from(jsonDecode(guardado));
    }
  }

  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toList()));
  }

  Future<void> toggle(String grupo) async {
    final nuevoSet = {...state};
    if (!nuevoSet.remove(grupo)) nuevoSet.add(grupo);
    state = nuevoSet;
    await _guardar();
  }

  Future<void> renombrar(String anterior, String nuevo) async {
    if (!state.contains(anterior)) return;
    final nuevoSet = {...state}..remove(anterior);
    nuevoSet.add(nuevo);
    state = nuevoSet;
    await _guardar();
  }

  Future<void> eliminar(String grupo) async {
    if (!state.contains(grupo)) return;
    final nuevoSet = {...state}..remove(grupo);
    state = nuevoSet;
    await _guardar();
  }
}

final gruposColapsadosProvider = NotifierProvider<GruposColapsadosNotifier, Set<String>>(() {
  return GruposColapsadosNotifier();
});

// --- PROVIDERS DE UI MODERNOS ---

enum TipoOrden { creacion, alfabetico, urgencia, fecha }

// Etiqueta legible de cada orden, compartida entre el menú de portrait
// (home_screen.dart) y el panel lateral del layout horizontal.
extension TipoOrdenLabel on TipoOrden {
  String get label {
    switch (this) {
      case TipoOrden.creacion:
        return 'Original';
      case TipoOrden.alfabetico:
        return 'Alfabético (A-Z)';
      case TipoOrden.urgencia:
        return 'Mayor urgencia';
      case TipoOrden.fecha:
        return 'Próximas a vencer';
    }
  }
}

class OrdenNotifier extends Notifier<TipoOrden> {
  static const String _key = 'tipo_orden_v1';

  @override
  TipoOrden build() {
    _cargarOrden();
    return TipoOrden.creacion;
  }

  Future<void> _cargarOrden() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_key);
    if (guardado != null) {
      state = TipoOrden.values.firstWhere(
        (t) => t.name == guardado,
        orElse: () => TipoOrden.creacion,
      );
    }
  }

  Future<void> cambiarOrden(TipoOrden nuevo) async {
    state = nuevo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, nuevo.name);
  }
}

final ordenProvider = NotifierProvider<OrdenNotifier, TipoOrden>(() => OrdenNotifier());

// --- VISTA AGRUPADA / TODAS JUNTAS ---
// Controla si la lista de tareas se muestra separada por grupos (carpetas)
// o como una sola lista plana, sin importar el grupo de cada tarea.
class VistaAgrupadaNotifier extends Notifier<bool> {
  static const String _key = 'tareas_vista_agrupada';

  @override
  bool build() {
    _cargarPreferencia();
    return true; // Por defecto se muestran agrupadas, como hasta ahora
  }

  Future<void> _cargarPreferencia() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getBool(_key);
    if (guardado != null) state = guardado;
  }

  Future<void> cambiarVista(bool agrupada) async {
    state = agrupada;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, agrupada);
  }
}

final vistaAgrupadaProvider = NotifierProvider<VistaAgrupadaNotifier, bool>(() {
  return VistaAgrupadaNotifier();
});