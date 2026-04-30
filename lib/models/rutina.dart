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
  
  // NUEVO CAMPO AÑADIDO
  final bool esFlexible; 

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
    // Lo inicializamos por defecto en false para que el diseño clásico sea el predeterminado
    this.esFlexible = false, 
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
      'esFlexible': esFlexible, // Guardamos el estado del interruptor
    };
  }

  factory Rutina.fromJson(Map<String, dynamic> json) {
    Map<int, TimeOfDay> horariosParsados = {};

    // 1. Cargamos el nuevo formato
    if (json.containsKey('horarios') && json['horarios'] != null) {
      final Map<String, dynamic> hMap = json['horarios'];
      hMap.forEach((k, v) {
        horariosParsados[int.parse(k)] = TimeOfDay(hour: v['hour'], minute: v['minute']);
      });
    } 
    // 2. Mantenemos la compatibilidad con las rutinas viejas
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
      // Si la rutina es antigua y no tiene este campo en la memoria, le ponemos false
      esFlexible: json['esFlexible'] as bool? ?? false, 
    );
  }
}