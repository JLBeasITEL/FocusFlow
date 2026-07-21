import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// Sentinel para distinguir "no se pasó el parámetro" de "se pasó null a
// propósito" en copyWith. Sin esto, `campo ?? this.campo` ignora los null
// explícitos y no hay forma de borrar fechaLimite/descripcion al editar.
const _sinCambio = Object();

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
      esCompletada: json['esCompletada'],
      grupo: json['grupo'] ?? 'General',
      // Retrocompatibilidad: tareas guardadas antes de esta feature no tienen
      // este campo en su JSON, así que caen en la lista vacía por defecto.
      subtareas: (json['subtareas'] as List?)?.map((s) => ItemSubtarea.fromJson(s as Map<String, dynamic>)).toList() ?? [],
    );
  }
}