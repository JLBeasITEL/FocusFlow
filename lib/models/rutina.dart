import 'package:flutter/material.dart';

class Rutina {
  final String id;
  final String titulo;
  final String? descripcion;
  final Map<int, TimeOfDay> horarios; 
  final int iconoCode;
  final bool activa;
  final int racha; 
  final bool completada; 
  final String? fechaCompletada;
  final bool esFlexible; 

  // ============================================================
  // NUEVO CAMPO: notificacionesActivas
  // ------------------------------------------------------------
  // Guarda la lista EXACTA de IDs de notificación que quedaron
  // programados en el sistema (Android AlarmManager) la última vez
  // que se ejecutó _gestionarNotificacionesRutina().
  //
  // Por qué existe: antes, para cancelar una notificación, el código
  // RECALCULABA el ID a partir de una fórmula matemática (hash del id
  // + offsets). Si ese cálculo no coincidía EXACTO con el ID que se
  // usó al programar (por overflow de enteros, timing, etc.), la
  // cancelación fallaba en silencio y la notificación seguía sonando.
  //
  // Ahora, en vez de recalcular, simplemente anotamos aquí los IDs
  // reales que se usaron al programar, y para cancelar usamos
  // exactamente esa lista. Ya no hay adivinanza posible.
  // ============================================================
  final List<int> notificacionesActivas;

  // ============================================================
  // NUEVO CAMPO: ultimaFechaProgramada
  // ------------------------------------------------------------
  // Fecha del occurrence MÁS LEJANO que quedó efectivamente
  // programado la última vez que se gestionaron las notificaciones
  // de esta rutina (el final del colchón de 4 semanas). Con esto,
  // cada apertura de la app puede decidir si el colchón todavía
  // alcanza (y no hacer ninguna llamada nativa) o si hace falta
  // rellenarlo, en vez de cancelar/reprogramar todo siempre.
  //
  // null = "todavía no se sabe" (rutina creada antes de este campo,
  // o recién restaurada de un respaldo de otro dispositivo): fuerza
  // un reset completo una sola vez para sembrarlo. Nunca debe causar
  // un crash si falta o viene corrupto.
  // ============================================================
  final DateTime? ultimaFechaProgramada;

  Rutina({
    required this.id,
    required this.titulo,
    this.descripcion,
    required this.horarios,
    required this.iconoCode,
    this.activa = true,
    this.racha = 0,
    this.completada = false,
    this.fechaCompletada,
    this.esFlexible = false,
    this.notificacionesActivas = const [], // Por defecto, ninguna notificación programada aún
    this.ultimaFechaProgramada,
  });

  Rutina copyWith({
    String? id,
    String? titulo,
    String? descripcion,
    Map<int, TimeOfDay>? horarios,
    int? iconoCode,
    bool? activa,
    int? racha,
    bool? completada,
    String? fechaCompletada,
    bool? esFlexible,
    List<int>? notificacionesActivas,
    DateTime? ultimaFechaProgramada,
  }) {
    return Rutina(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
      horarios: horarios ?? this.horarios,
      iconoCode: iconoCode ?? this.iconoCode,
      activa: activa ?? this.activa,
      racha: racha ?? this.racha,
      completada: completada ?? this.completada,
      fechaCompletada: fechaCompletada ?? this.fechaCompletada,
      esFlexible: esFlexible ?? this.esFlexible,
      notificacionesActivas: notificacionesActivas ?? this.notificacionesActivas,
      ultimaFechaProgramada: ultimaFechaProgramada ?? this.ultimaFechaProgramada,
    );
  }

  Map<String, dynamic> toJson() {
    final horariosJson = horarios.map((key, value) => MapEntry(key.toString(), {'hour': value.hour, 'minute': value.minute}));
    
    return {
      'id': id,
      'titulo': titulo,
      'descripcion': descripcion,
      'horarios': horariosJson,
      'iconoCode': iconoCode,
      'activa': activa,
      'racha': racha,
      'completada': completada,
      'fechaCompletada': fechaCompletada,
      'esFlexible': esFlexible,
      // Guardamos la lista de IDs reales para poder recuperarla al reabrir la app
      'notificacionesActivas': notificacionesActivas,
      'ultimaFechaProgramada': ultimaFechaProgramada?.toIso8601String(),
    };
  }

  factory Rutina.fromJson(Map<String, dynamic> json) {
    Map<int, TimeOfDay> horariosParsados = {};

    if (json.containsKey('horarios') && json['horarios'] != null) {
      final Map<String, dynamic> hMap = json['horarios'];
      hMap.forEach((k, v) {
        horariosParsados[int.parse(k)] = TimeOfDay(hour: v['hour'], minute: v['minute']);
      });
    } 
    else if (json.containsKey('diasSemana')) {
      List<bool> viejosDias = List<bool>.from(json['diasSemana']);
      TimeOfDay viejaHora = TimeOfDay(hour: json['hora'] as int, minute: json['minuto'] as int);
      for(int i=0; i<viejosDias.length; i++) {
        if (viejosDias[i]) horariosParsados[i] = viejaHora;
      }
    }

    return Rutina(
      id: json['id'] as String,
      titulo: json['titulo'] as String,
      descripcion: json['descripcion'] as String?,
      horarios: horariosParsados,
      iconoCode: json['iconoCode'] as int,
      activa: json['activa'] as bool,
      racha: json['racha'] as int? ?? 0,
      completada: json['completada'] as bool? ?? false,
      fechaCompletada: json['fechaCompletada'] as String?,
      esFlexible: json['esFlexible'] as bool? ?? false, 
      // Rutinas guardadas ANTES de este cambio no tendrán este campo:
      // les asignamos lista vacía (no rompe nada, simplemente no habrá
      // nada que cancelar de forma "recordada" hasta que se reprogramen
      // por primera vez con el nuevo sistema).
      notificacionesActivas: (json['notificacionesActivas'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [],
      // Rutinas guardadas ANTES de este campo (o restauradas de un respaldo
      // de otro dispositivo) no lo tendrán: usamos tryParse para que un
      // valor ausente o corrupto se convierta en null en vez de crashear,
      // y null fuerza el reset completo que "siembra" el campo de nuevo.
      ultimaFechaProgramada: json['ultimaFechaProgramada'] != null
          ? DateTime.tryParse(json['ultimaFechaProgramada'] as String)
          : null,
    );
  }
}