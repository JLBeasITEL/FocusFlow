import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// Sentinel para distinguir "no se pasó el parámetro" de "se pasó null a
// propósito" en copyWith. Sin esto, `campo ?? this.campo` ignora los null
// explícitos y no hay forma de borrar fechaLimite/descripcion al editar.
const _sinCambio = Object();

// Persistido como string (name/byName en toJson/fromJson), NO como índice:
// un índice se corrompe silenciosamente si el orden de los valores cambia
// alguna vez, un string no.
enum TipoRecurrencia { ninguna, dias, meses }

// Mismo patrón que ItemLista en models/nota.dart (texto + completado marcable),
// pero con id propio y estable: las operaciones de subtareas (toggle, eliminar,
// reordenar) necesitan identificar un ítem sin depender de su posición en la lista.
class ItemSubtarea {
  final String id;
  String texto;
  bool completado;

  ItemSubtarea({String? id, required this.texto, this.completado = false}) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {'id': id, 'texto': texto, 'completado': completado};

  factory ItemSubtarea.fromJson(Map<String, dynamic> json) => ItemSubtarea(
    id: json['id'] ?? _uuid.v4(),
    texto: json['texto'] ?? '',
    completado: json['completado'] ?? false,
  );
}

class Tarea {
  bool get estaAtrasada {
    // Si no tiene fecha límite o ya la marcaste como completada, no está atrasada
    if (fechaLimite == null || esCompletada) return false;
    
    // Comparamos el reloj actual de tu celular con la fecha límite guardada
    return fechaLimite!.isBefore(DateTime.now());
  }
  final String id;
  final String titulo;
  final String? descripcion;
  final DateTime? fechaLimite;
  final double? horasEstimadas; // NUEVO: ¿Cuánto tiempo te tomará hacerla? (admite decimales)
  final int urgenciaBase; // La urgencia manual que eliges si no usas el auto-piloto
  final bool esCompletada;
  final String grupo;
  final List<ItemSubtarea> subtareas;

  // --- RECURRENCIA POR INTERVALO ---
  // Una sola instancia viva por tarea: al completarla (ver
  // TareaNotifier.toggleTarea), en vez de archivarla se recalcula
  // fechaLimite con siguienteFecha() y esCompletada vuelve a false en el
  // mismo copyWith, atómicamente. Nunca debe persistirse esCompletada=true
  // en una tarea recurrente, porque la limpieza diaria de
  // TareaNotifier._cargarTareasInterno la borraría para siempre.
  final TipoRecurrencia tipoRecurrencia;
  final int? intervalo; // N días o N meses, según tipoRecurrencia
  final int? diaAncla; // 1-31, solo para meses; se fija al crear/editar y no cambia entre ocurrencias
  // Guarda el fechaLimite que tenía la tarea justo antes de la última vez
  // que se completó, para poder deshacer (ver
  // TareaNotifier.deshacerRecurrente) y para que WidgetProgresoService
  // pueda seguir contándola como "completada hoy" aunque su fechaLimite ya
  // haya avanzado a la próxima ocurrencia.
  final DateTime? fechaLimiteAnterior;

  Tarea({
    String? id,
    required this.titulo,
    this.descripcion,
    this.fechaLimite,
    this.horasEstimadas,
    required this.urgenciaBase,
    this.esCompletada = false,
    this.grupo = 'General',
    List<ItemSubtarea>? subtareas,
    this.tipoRecurrencia = TipoRecurrencia.ninguna,
    this.intervalo,
    this.diaAncla,
    this.fechaLimiteAnterior,
  }) : id = id ?? _uuid.v4(),
       subtareas = subtareas ?? [];

  // Progreso de subtareas ya calculado una sola vez aquí, para que la UI
  // (indicador "2/5" y barra de progreso) no repita este conteo en cada build.
  (int completadas, int total) get progresoSubtareas {
    final total = subtareas.length;
    final completadas = subtareas.where((s) => s.completado).length;
    return (completadas, total);
  }

  double get porcentajeSubtareas {
    final (completadas, total) = progresoSubtareas;
    if (total == 0) return 0.0;
    return completadas / total;
  }

  // --- MOTOR DE URGENCIA INTELIGENTE ---
  // Al usar 'get', la urgencia se recalcula automáticamente cada vez que la pantalla la lee
  int get urgencia {
    // 1. Si está completada, o no tiene fecha límite, o no tiene tiempo estimado, 
    // usamos la urgencia manual de toda la vida.
    if (esCompletada || fechaLimite == null || horasEstimadas == null) {
      return urgenciaBase;
    }

    // 2. Si tiene auto-piloto, calculamos cuánto tiempo falta
    final ahora = DateTime.now();
    final tiempoRestante = fechaLimite!.difference(ahora);

    // Si ya se pasó la fecha o si el tiempo que falta es IGUAL O MENOR al que necesitas
    if (tiempoRestante.inHours <= horasEstimadas!) {
      return 4; // MUY ALTO (¡Empieza ahora!)
    } 
    // Si tienes un "colchón" del 50% de tiempo extra
    else if (tiempoRestante.inHours <= (horasEstimadas! * 1.5).round()) {
      return 3; // ALTO
    } 
    // Si tienes el doble de tiempo necesario
    else if (tiempoRestante.inHours <= (horasEstimadas! * 2).round()) {
      return 2; // MEDIO
    } 
    // Si tienes muchísimo tiempo de sobra
    else {
      return 1; // BAJO
    }
  }

  // Calcula la próxima fecha límite de una tarea recurrente a partir de la
  // fechaLimite ACTUAL (no de "ahora"): si la tarea se completa tarde, la
  // siguiente ocurrencia sigue siendo relativa a cuándo debía vencer, no a
  // cuándo se completó de verdad. Devuelve null si no aplica (sin
  // recurrencia, sin fecha, o sin intervalo configurado).
  DateTime? siguienteFecha() {
    if (tipoRecurrencia == TipoRecurrencia.ninguna || fechaLimite == null || intervalo == null) {
      return null;
    }
    final base = fechaLimite!;

    if (tipoRecurrencia == TipoRecurrencia.dias) {
      return base.add(Duration(days: intervalo!));
    }

    // meses: se avanza `intervalo` meses conservando diaAncla (el día del
    // mes original) como referencia, en vez del día de `base` — así
    // "31 ene" recortado a "28 feb" no se queda pegado en 28 para siempre:
    // la siguiente ocurrencia vuelve a intentar el día 31 (-> 31 mar).
    final ancla = diaAncla ?? base.day;
    final mesesTotales = base.month - 1 + intervalo!;
    final anioDestino = base.year + mesesTotales ~/ 12;
    final mesDestino = mesesTotales % 12 + 1;
    // día 0 del mes siguiente al destino == último día del mes destino.
    final ultimoDiaMesDestino = DateTime(anioDestino, mesDestino + 1, 0).day;
    final diaFinal = ancla > ultimoDiaMesDestino ? ultimoDiaMesDestino : ancla;

    return DateTime(anioDestino, mesDestino, diaFinal, base.hour, base.minute);
  }

  Tarea copyWith({
    String? id,
    String? titulo,
    Object? descripcion = _sinCambio,
    Object? fechaLimite = _sinCambio,
    Object? horasEstimadas = _sinCambio,
    int? urgenciaBase,
    bool? esCompletada,
    String? grupo,
    List<ItemSubtarea>? subtareas,
    TipoRecurrencia? tipoRecurrencia,
    Object? intervalo = _sinCambio,
    Object? diaAncla = _sinCambio,
    Object? fechaLimiteAnterior = _sinCambio,
  }) {
    return Tarea(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: identical(descripcion, _sinCambio) ? this.descripcion : descripcion as String?,
      fechaLimite: identical(fechaLimite, _sinCambio) ? this.fechaLimite : fechaLimite as DateTime?,
      horasEstimadas: identical(horasEstimadas, _sinCambio) ? this.horasEstimadas : horasEstimadas as double?,
      urgenciaBase: urgenciaBase ?? this.urgenciaBase,
      esCompletada: esCompletada ?? this.esCompletada,
      grupo: grupo ?? this.grupo,
      subtareas: subtareas ?? this.subtareas.map((s) => ItemSubtarea(id: s.id, texto: s.texto, completado: s.completado)).toList(),
      tipoRecurrencia: tipoRecurrencia ?? this.tipoRecurrencia,
      intervalo: identical(intervalo, _sinCambio) ? this.intervalo : intervalo as int?,
      diaAncla: identical(diaAncla, _sinCambio) ? this.diaAncla : diaAncla as int?,
      fechaLimiteAnterior: identical(fechaLimiteAnterior, _sinCambio) ? this.fechaLimiteAnterior : fechaLimiteAnterior as DateTime?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titulo': titulo,
      'descripcion': descripcion,
      'fechaLimite': fechaLimite?.toIso8601String(),
      'horasEstimadas': horasEstimadas, // Guardamos este nuevo dato
      'urgenciaBase': urgenciaBase,
      'esCompletada': esCompletada,
      'grupo': grupo,
      'subtareas': subtareas.map((s) => s.toJson()).toList(),
      'tipoRecurrencia': tipoRecurrencia.name,
      'intervalo': intervalo,
      'diaAncla': diaAncla,
      'fechaLimiteAnterior': fechaLimiteAnterior?.toIso8601String(),
    };
  }

  factory Tarea.fromJson(Map<String, dynamic> json) {

    return Tarea(

      id: json['id'],
      titulo: json['titulo'],
      descripcion: json['descripcion'],
      fechaLimite: json['fechaLimite'] != null ? DateTime.parse(json['fechaLimite']) : null,
      // (json['horasEstimadas'] as num?) porque datos antiguos lo guardaron como int
      horasEstimadas: (json['horasEstimadas'] as num?)?.toDouble(),
      urgenciaBase: json['urgencia'] ?? json['urgenciaBase'] ?? 1, // Retrocompatibilidad
      esCompletada: json['esCompletada'] as bool? ?? false,
      grupo: json['grupo'] ?? 'General',
      // Retrocompatibilidad: tareas guardadas antes de esta feature no tienen
      // este campo en su JSON, así que caen en la lista vacía por defecto.
      subtareas: (json['subtareas'] as List?)?.map((s) => ItemSubtarea.fromJson(s as Map<String, dynamic>)).toList() ?? [],
      // Tareas guardadas antes de esta feature (o con un string desconocido/
      // corrupto) no rompen: caen en TipoRecurrencia.ninguna, el mismo
      // comportamiento que ya tenían.
      tipoRecurrencia: TipoRecurrencia.values.asNameMap()[json['tipoRecurrencia'] as String?] ?? TipoRecurrencia.ninguna,
      intervalo: json['intervalo'] as int?,
      diaAncla: json['diaAncla'] as int?,
      fechaLimiteAnterior: json['fechaLimiteAnterior'] != null ? DateTime.tryParse(json['fechaLimiteAnterior'] as String) : null,
    );
  }
}