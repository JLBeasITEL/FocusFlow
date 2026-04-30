import 'package:uuid/uuid.dart';

const _uuid = Uuid();

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
  final int? horasEstimadas; // NUEVO: ¿Cuánto tiempo te tomará hacerla?
  final int urgenciaBase; // La urgencia manual que eliges si no usas el auto-piloto
  final bool esCompletada;

  Tarea({
    String? id,
    required this.titulo,
    this.descripcion,
    this.fechaLimite,
    this.horasEstimadas,
    required this.urgenciaBase,
    this.esCompletada = false,
  }) : id = id ?? _uuid.v4();

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
    String? descripcion,
    DateTime? fechaLimite,
    int? horasEstimadas,
    int? urgenciaBase,
    bool? esCompletada,
  }) {
    return Tarea(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
      fechaLimite: fechaLimite ?? this.fechaLimite,
      horasEstimadas: horasEstimadas ?? this.horasEstimadas,
      urgenciaBase: urgenciaBase ?? this.urgenciaBase,
      esCompletada: esCompletada ?? this.esCompletada,
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
    };
  }

  factory Tarea.fromJson(Map<String, dynamic> json) {
    
    return Tarea(
      
      id: json['id'],
      titulo: json['titulo'],
      descripcion: json['descripcion'],
      fechaLimite: json['fechaLimite'] != null ? DateTime.parse(json['fechaLimite']) : null,
      horasEstimadas: json['horasEstimadas'], // Leemos este nuevo dato
      urgenciaBase: json['urgencia'] ?? json['urgenciaBase'] ?? 1, // Retrocompatibilidad
      esCompletada: json['esCompletada'],
    );
  }
}