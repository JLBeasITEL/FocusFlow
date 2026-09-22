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
        // TODA tarea completada de ayer (recurrente o no) va al archivo en
        // vez de borrarse sin más: el archivo es la consulta general de
        // "qué desapareció de la lista principal", no solo de recurrentes
        // que agotaron su límite. Una recurrente completada acá es SIEMPRE
        // su última ocurrencia (la que agotó el límite, ver
        // _completarUltimaOcurrencia/archivarDirectamente): una recurrente
        // que sigue viva nunca queda con esCompletada=true (ver comentario
        // de toggleTarea).
        final paraArchivar = tareasCargadas.where((tarea) => tarea.esCompletada).toList();

        // 1. Filtramos para eliminar las completadas de ayer
        tareasCargadas = tareasCargadas.where((tarea) => !tarea.esCompletada).toList();

        // 2. Registramos que ya limpiamos hoy
        await prefs.setString('ultimo_dia_limpieza_tareas', hoy);

        // 3. Asignamos la lista limpia al estado de la aplicación
        state = tareasCargadas;

        // 4. ¡CRÍTICO! Guardamos en la base de datos para sacar las completadas
        // de la lista activa (lista_tareas_v1) de forma permanente.
        _guardarTareas();

        // Recién acá se archivan de verdad: no antes de que _guardarTareas()
        // haya confirmado que ya salieron de la lista activa.
        for (final tarea in paraArchivar) {
          await ref.read(archivoTareasProvider.notifier).archivar(tarea);
        }
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

  // Tareas recurrentes QUE SIGUEN vivas: al completarlas (false -> true)
  // NUNCA se persiste esCompletada = true. En su lugar, en el MISMO copyWith
  // se recalcula fechaLimite con siguienteFecha() y esCompletada vuelve a
  // false — atómicamente, para que una recurrente que sigue viva jamás
  // quede guardada en estado "completada" y termine borrada por la limpieza
  // diaria de _cargarTareasInterno (ver comentario ahí). fechaLimiteAnterior
  // guarda la fecha vieja para poder deshacer (ver deshacerRecurrente) y
  // para que WidgetProgresoService cuente el día como completado.
  // ocurrenciasCompletadas sube en CUALQUIER completación de una recurrente
  // (siga o sea la última): es histórico real (ver Tarea, comentario del
  // campo), no una cuenta que solo importe si hay límite puesto.
  //
  // Hay un tercer caso, además de "sigue" y "no recurrente / des-completando":
  // la ocurrencia que se completa agota el límite de la recurrencia (ver
  // Tarea.completarAgotaLimite). Ahí SÍ se persiste esCompletada=true, igual
  // que cualquier tarea normal — se ve tachada en la lista el resto del día
  // y la limpieza diaria la manda al archivo en vez de borrarla (ver
  // _completarUltimaOcurrencia y el comentario de _cargarTareasInterno).
  //
  // Y un cuarto caso, simétrico al anterior: DESmarcar una recurrente que
  // está tachada por haber agotado su límite. Un simple flip de esCompletada
  // dejaría fechaLimite/contador desalineados (fechaLimite quedó igual, el
  // contador ya subió) — se deshace con la reconstrucción completa de
  // deshacerRecurrente, la misma que usa el botón de "Deshacer" dedicado.
  void toggleTarea(String id) {
    final tareaActual = state.firstWhere((t) => t.id == id);
    final bool completando = !tareaActual.esCompletada;
    final bool esRecurrente = tareaActual.tipoRecurrencia != TipoRecurrencia.ninguna;

    if (completando && esRecurrente && tareaActual.completarAgotaLimite) {
      _completarUltimaOcurrencia(tareaActual);
      return;
    }

    if (!completando && esRecurrente && tareaActual.fechaLimiteAnterior != null) {
      deshacerRecurrente(id);
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
                  // Respalda el contador ANTES de subirlo, para que
                  // _reconstruirTrasDeshacer sepa exactamente a qué valor
                  // volver (ver comentario del campo en Tarea) en vez de
                  // asumir "restar 1".
                  ocurrenciasCompletadasAnterior: tarea.ocurrenciasCompletadas,
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

  // Completa la ÚLTIMA ocurrencia de una recurrente que acaba de agotar su
  // límite: se marca esCompletada=true y se queda en `state` — se ve tachada
  // en la lista exactamente igual que cualquier tarea completada normal,
  // durante el resto del día. Recién la limpieza diaria de
  // _cargarTareasInterno la manda al archivo (en vez de borrarla, como haría
  // con una tarea normal), no este método. Respalda fechaLimite/contador
  // (mismo propósito que el caso "sigue": permitir deshacer con
  // deshacerRecurrente mientras siga activa, o con restaurarDesdeArchivo una
  // vez archivada). A propósito NO llama a programarAlertaDefinitiva: no hay
  // una próxima ocurrencia que vaya a necesitar una alarma, así que solo se
  // cancela la que ya existía.
  void _completarUltimaOcurrencia(Tarea tarea) {
    state = [
      for (final t in state)
        if (t.id == tarea.id)
          t.copyWith(
            esCompletada: true,
            ocurrenciasCompletadas: t.ocurrenciasCompletadas + 1,
            ocurrenciasCompletadasAnterior: t.ocurrenciasCompletadas,
            fechaLimiteAnterior: t.fechaLimite,
          )
        else
          t,
    ];
    _guardarTareas();
    NotificacionesService().cancelarAlerta(tarea.id);
  }

  // Mismo tratamiento que _completarUltimaOcurrencia, pero al EDITAR una
  // tarea cuando el nuevo tope ya quedó por debajo de lo que ya se había
  // completado (ver Tarea.yaAgotoLimite: ej. tenía 12 cuotas, lleva 8, y el
  // usuario lo cambia a 6). A diferencia de ese método, acá NO se está
  // completando ninguna ocurrencia — el histórico (ocurrenciasCompletadas)
  // se queda tal cual quedó editado, nunca sube. El formulario
  // (add_tarea_modal.dart) es responsable de confirmar esto con el usuario
  // ANTES de llamar acá.
  void archivarDirectamente(Tarea tareaEditada) {
    final completada = tareaEditada.copyWith(
      esCompletada: true,
      // Sin incremento: ocurrenciasCompletadasAnterior == ocurrenciasCompletadas
      // a propósito, para que restaurar esta tarea sea un no-op sobre el
      // contador (ver _reconstruirTrasDeshacer) — nada que "deshacer" ahí,
      // ya que nada se completó.
      ocurrenciasCompletadasAnterior: tareaEditada.ocurrenciasCompletadas,
      fechaLimiteAnterior: tareaEditada.fechaLimite,
    );
    state = [
      for (final t in state)
        if (t.id == tareaEditada.id) completada else t,
    ];
    _guardarTareas();
    NotificacionesService().cancelarAlerta(tareaEditada.id);
  }

  // Reconstruye una tarea recurrente a como estaba justo antes del evento
  // que se deshace (completar una ocurrencia, o el archivado directo de
  // archivarDirectamente), usando los respaldos "Anterior" en vez de asumir
  // matemática fija (ver comentario de ocurrenciasCompletadasAnterior en
  // Tarea: no todo evento que archiva sube el contador de la misma forma).
  // Lógica compartida por deshacerRecurrente y restaurarDesdeArchivo: cada
  // uno decide DÓNDE buscar la tarea de origen y DÓNDE deja el resultado
  // (ver comentario de cada uno para por qué están separados en vez de
  // fundirse en un solo método que decida según dónde encuentra la tarea).
  Tarea _reconstruirTrasDeshacer(Tarea tarea) {
    return tarea.copyWith(
      fechaLimite: tarea.fechaLimiteAnterior,
      fechaLimiteAnterior: null,
      subtareas: tarea.subtareasAnterior ?? tarea.subtareas,
      subtareasAnterior: null,
      esCompletada: false,
      ocurrenciasCompletadas: tarea.ocurrenciasCompletadasAnterior ?? tarea.ocurrenciasCompletadas,
      ocurrenciasCompletadasAnterior: null,
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

  // Restaura desde el archivo CUALQUIER tarea archivada (una recurrente que
  // agotó su límite, una que archivarDirectamente archivó al editar el tope
  // por debajo de lo ya completado, o una tarea normal que la limpieza
  // diaria archivó al completarse): la invoca la pantalla de tareas
  // archivadas. Ver el comentario de deshacerRecurrente para por qué esto es
  // un método separado en vez de una rama de esa misma función.
  //
  // Solo las recurrentes traen fechaLimiteAnterior (respaldo puesto por
  // _completarUltimaOcurrencia/archivarDirectamente/el caso "sigue" de
  // toggleTarea): para esas, _reconstruirTrasDeshacer devuelve fechaLimite y
  // el contador a como estaban antes. Una tarea normal no tiene ese
  // respaldo -ni falta que le hace-: alcanza con desmarcarla, conservando
  // su fechaLimite tal cual (usar _reconstruirTrasDeshacer ahí la dejaría
  // con fechaLimite null, perdiendo la fecha original).
  Future<void> restaurarDesdeArchivo(String id) async {
    final tarea = await ref.read(archivoTareasProvider.notifier).restaurar(id);
    if (tarea == null) return;

    final restaurada = tarea.fechaLimiteAnterior != null ? _reconstruirTrasDeshacer(tarea) : tarea.copyWith(esCompletada: false);
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
    await ref.read(iconosGruposProvider.notifier).renombrar(grupoAnterior, grupoNuevo);
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
    await ref.read(iconosGruposProvider.notifier).eliminar(grupo);
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

// --- FILTRO DE TAREAS ---
// "Día" no compara contra un día de la semana (Tarea no tiene ese campo,
// solo fechaLimite como DateTime? puntual): compara la fecha límite contra
// el calendario real (hoy, esta semana) o contra estaAtrasada/null.
enum FiltroDia { todas, hoy, estaSemana, atrasadas, sinFecha }

extension FiltroDiaLabel on FiltroDia {
  String get label {
    switch (this) {
      case FiltroDia.todas: return 'Todos los días';
      case FiltroDia.hoy: return 'Hoy';
      case FiltroDia.estaSemana: return 'Esta semana';
      case FiltroDia.atrasadas: return 'Atrasadas';
      case FiltroDia.sinFecha: return 'Sin fecha';
    }
  }
}

enum FiltroSubtareas { todas, conSubtareas, sinSubtareas }

extension FiltroSubtareasLabel on FiltroSubtareas {
  String get label {
    switch (this) {
      case FiltroSubtareas.todas: return 'Todas';
      case FiltroSubtareas.conSubtareas: return 'Con subtareas';
      case FiltroSubtareas.sinSubtareas: return 'Sin subtareas';
    }
  }
}

enum FiltroRecurrencia { todas, recurrentes, noRecurrentes }

extension FiltroRecurrenciaLabel on FiltroRecurrencia {
  String get label {
    switch (this) {
      case FiltroRecurrencia.todas: return 'Todas';
      case FiltroRecurrencia.recurrentes: return 'Recurrentes';
      case FiltroRecurrencia.noRecurrentes: return 'No recurrentes';
    }
  }
}

enum FiltroCompletado { todas, completas, incompletas }

extension FiltroCompletadoLabel on FiltroCompletado {
  String get label {
    switch (this) {
      case FiltroCompletado.todas: return 'Todas';
      case FiltroCompletado.completas: return 'Completas';
      case FiltroCompletado.incompletas: return 'Incompletas';
    }
  }
}

bool _mismoDiaCalendario(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class FiltroTareas {
  final Set<int> nivelesUrgencia;
  final FiltroDia dia;
  final Set<String> grupos;
  final FiltroSubtareas subtareas;
  final FiltroRecurrencia recurrencia;
  final FiltroCompletado completado;

  const FiltroTareas({
    this.nivelesUrgencia = const {},
    this.dia = FiltroDia.todas,
    this.grupos = const {},
    this.subtareas = FiltroSubtareas.todas,
    this.recurrencia = FiltroRecurrencia.todas,
    this.completado = FiltroCompletado.todas,
  });

  bool get activo =>
      nivelesUrgencia.isNotEmpty ||
      dia != FiltroDia.todas ||
      grupos.isNotEmpty ||
      subtareas != FiltroSubtareas.todas ||
      recurrencia != FiltroRecurrencia.todas ||
      completado != FiltroCompletado.todas;

  int get cantidadActivos {
    var n = 0;
    if (nivelesUrgencia.isNotEmpty) n++;
    if (dia != FiltroDia.todas) n++;
    if (grupos.isNotEmpty) n++;
    if (subtareas != FiltroSubtareas.todas) n++;
    if (recurrencia != FiltroRecurrencia.todas) n++;
    if (completado != FiltroCompletado.todas) n++;
    return n;
  }

  FiltroTareas copyWith({
    Set<int>? nivelesUrgencia,
    FiltroDia? dia,
    Set<String>? grupos,
    FiltroSubtareas? subtareas,
    FiltroRecurrencia? recurrencia,
    FiltroCompletado? completado,
  }) {
    return FiltroTareas(
      nivelesUrgencia: nivelesUrgencia ?? this.nivelesUrgencia,
      dia: dia ?? this.dia,
      grupos: grupos ?? this.grupos,
      subtareas: subtareas ?? this.subtareas,
      recurrencia: recurrencia ?? this.recurrencia,
      completado: completado ?? this.completado,
    );
  }

  // Usa tarea.urgencia (getter recalculado) y no urgenciaBase, para que el
  // filtro coincida con el nivel que la tarjeta realmente muestra.
  bool coincide(Tarea t) {
    if (nivelesUrgencia.isNotEmpty && !nivelesUrgencia.contains(t.urgencia)) return false;
    if (grupos.isNotEmpty && !grupos.contains(t.grupo)) return false;

    switch (completado) {
      case FiltroCompletado.completas:
        if (!t.esCompletada) return false;
      case FiltroCompletado.incompletas:
        if (t.esCompletada) return false;
      case FiltroCompletado.todas:
        break;
    }

    switch (subtareas) {
      case FiltroSubtareas.conSubtareas:
        if (t.subtareas.isEmpty) return false;
      case FiltroSubtareas.sinSubtareas:
        if (t.subtareas.isNotEmpty) return false;
      case FiltroSubtareas.todas:
        break;
    }

    switch (recurrencia) {
      case FiltroRecurrencia.recurrentes:
        if (t.tipoRecurrencia == TipoRecurrencia.ninguna) return false;
      case FiltroRecurrencia.noRecurrentes:
        if (t.tipoRecurrencia != TipoRecurrencia.ninguna) return false;
      case FiltroRecurrencia.todas:
        break;
    }

    switch (dia) {
      case FiltroDia.hoy:
        if (t.fechaLimite == null || !_mismoDiaCalendario(t.fechaLimite!, DateTime.now())) return false;
      case FiltroDia.estaSemana:
        if (t.fechaLimite == null) return false;
        final ahora = DateTime.now();
        final inicioSemana = DateTime(ahora.year, ahora.month, ahora.day).subtract(Duration(days: ahora.weekday - 1));
        final finSemana = inicioSemana.add(const Duration(days: 7));
        if (t.fechaLimite!.isBefore(inicioSemana) || !t.fechaLimite!.isBefore(finSemana)) return false;
      case FiltroDia.atrasadas:
        if (!t.estaAtrasada) return false;
      case FiltroDia.sinFecha:
        if (t.fechaLimite != null) return false;
      case FiltroDia.todas:
        break;
    }

    return true;
  }
}

class FiltroTareasNotifier extends Notifier<FiltroTareas> {
  static const String _key = 'filtro_tareas_v1';

  @override
  FiltroTareas build() {
    _cargar();
    return const FiltroTareas();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_key);
    if (guardado == null) return;
    try {
      final mapa = jsonDecode(guardado) as Map<String, dynamic>;
      state = FiltroTareas(
        nivelesUrgencia: Set<int>.from(mapa['nivelesUrgencia'] ?? const []),
        dia: FiltroDia.values.firstWhere((d) => d.name == mapa['dia'], orElse: () => FiltroDia.todas),
        grupos: Set<String>.from(mapa['grupos'] ?? const []),
        subtareas: FiltroSubtareas.values.firstWhere((s) => s.name == mapa['subtareas'], orElse: () => FiltroSubtareas.todas),
        recurrencia: FiltroRecurrencia.values.firstWhere((r) => r.name == mapa['recurrencia'], orElse: () => FiltroRecurrencia.todas),
        completado: FiltroCompletado.values.firstWhere((c) => c.name == mapa['completado'], orElse: () => FiltroCompletado.todas),
      );
    } catch (_) {
      // Filtro guardado corrupto: seguimos con el filtro vacío por defecto.
    }
  }

  Future<void> actualizar(FiltroTareas nuevo) async {
    state = nuevo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'nivelesUrgencia': state.nivelesUrgencia.toList(),
      'dia': state.dia.name,
      'grupos': state.grupos.toList(),
      'subtareas': state.subtareas.name,
      'recurrencia': state.recurrencia.name,
      'completado': state.completado.name,
    }));
  }

  Future<void> limpiar() async {
    state = const FiltroTareas();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final filtroTareasProvider = NotifierProvider<FiltroTareasNotifier, FiltroTareas>(() {
  return FiltroTareasNotifier();
});
// --- ÍCONOS PERSONALIZADOS DE GRUPOS (CARPETAS) ---
// Guarda qué ícono eligió el usuario para cada carpeta (grupo de tareas).
// El valor es la clave de un ícono del catálogo de iconos_grupo.dart (no el
// codePoint) para que el respaldo sea estable. Ausencia de un grupo en el
// mapa = ícono por defecto (carpeta). Como el nombre del grupo es la llave,
// renombrarGrupo/eliminarGrupo en TareaNotifier avisan a este notifier.
class IconosGruposNotifier extends Notifier<Map<String, String>> {
  static const String _key = 'tareas_grupos_iconos_v1';

  @override
  Map<String, String> build() {
    _cargar();
    return {};
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_key);
    if (guardado != null) {
      state = Map<String, String>.from(jsonDecode(guardado));
    }
  }

  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state));
  }

  // Fuerza una relectura completa desde SharedPreferences. Se usa tras
  // restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    state = {};
    await _cargar();
  }

  // Asigna el ícono de un grupo; con null vuelve al ícono por defecto.
  Future<void> establecer(String grupo, String? clave) async {
    final nuevo = {...state};
    if (clave == null) {
      if (nuevo.remove(grupo) == null) return;
    } else {
      nuevo[grupo] = clave;
    }
    state = nuevo;
    await _guardar();
  }

  Future<void> renombrar(String anterior, String nuevo) async {
    final clave = state[anterior];
    if (clave == null) return;
    state = {...state}..remove(anterior);
    state = {...state, nuevo: clave};
    await _guardar();
  }

  Future<void> eliminar(String grupo) => establecer(grupo, null);
}

final iconosGruposProvider = NotifierProvider<IconosGruposNotifier, Map<String, String>>(() {
  return IconosGruposNotifier();
});
