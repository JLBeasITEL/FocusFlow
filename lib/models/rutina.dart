import 'package:flutter/material.dart';

class Rutina {
  final String id;
  final String titulo;
  final String? descripcion;
  final TimeOfDay horaDian;
  final List<bool> diasSemana; // [Lunes, Martes, Miercoles, Jueves, Viernes, Sabado, Domingo]
  final int iconoCode;
  final bool activa;
  final int racha; // 🔥 NUEVO: Contador de rachas

  Rutina({
    required this.id,
    required this.titulo,
    this.descripcion,
    required this.horaDian,
    required this.diasSemana,
    required this.iconoCode,
    this.activa = true,
    this.racha = 0, // Inicia en 0 por defecto
  });

  Rutina copyWith({
    String? id,
    String? titulo,
    String? descripcion,
    TimeOfDay? horaDian,
    List<bool>? diasSemana,
    int? iconoCode,
    bool? activa,
    int? racha,
  }) {
    return Rutina(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
      horaDian: horaDian ?? this.horaDian,
      diasSemana: diasSemana ?? this.diasSemana,
      iconoCode: iconoCode ?? this.iconoCode,
      activa: activa ?? this.activa,
      racha: racha ?? this.racha,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titulo': titulo,
      'descripcion': descripcion,
      'hora': horaDian.hour,
      'minuto': horaDian.minute,
      'diasSemana': diasSemana,
      'iconoCode': iconoCode,
      'activa': activa,
      'racha': racha,
    };
  }

  factory Rutina.fromJson(Map<String, dynamic> json) {
    return Rutina(
      id: json['id'] as String,
      titulo: json['titulo'] as String,
      descripcion: json['descripcion'] as String?,
      horaDian: TimeOfDay(hour: json['hora'] as int, minute: json['minuto'] as int),
      diasSemana: List<bool>.from(json['diasSemana']),
      iconoCode: json['iconoCode'] as int,
      activa: json['activa'] as bool,
      racha: json['racha'] as int? ?? 0,
    );
  }
}