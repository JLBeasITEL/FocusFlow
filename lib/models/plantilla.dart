import 'package:uuid/uuid.dart';
import 'tarea.dart';

const _uuid = Uuid();

// Guarda la "forma" de una tarea que se repite seguido (pero no todos los
// días, si no sería una Rutina) para poder recrearla rápido: título,
// subtareas, grupo y urgencia. Fecha límite y horas estimadas quedan fuera
// a propósito, porque son propias de cada ocasión en la que se usa.
class Plantilla {
  final String id;
  final String nombre;
  final String titulo;
  final String grupo;
  final int urgenciaBase;
  final List<ItemSubtarea> subtareas;

  Plantilla({
    String? id,
    required this.nombre,
    required this.titulo,
    required this.grupo,
    required this.urgenciaBase,
    List<ItemSubtarea>? subtareas,
  }) : id = id ?? _uuid.v4(),
       subtareas = subtareas ?? [];

  Plantilla copyWith({
    String? nombre,
    String? titulo,
    String? grupo,
    int? urgenciaBase,
    List<ItemSubtarea>? subtareas,
  }) {
    return Plantilla(
      id: id,
      nombre: nombre ?? this.nombre,
      titulo: titulo ?? this.titulo,
      grupo: grupo ?? this.grupo,
      urgenciaBase: urgenciaBase ?? this.urgenciaBase,
      subtareas: subtareas ?? this.subtareas.map((s) => ItemSubtarea(id: s.id, texto: s.texto, completado: s.completado)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'titulo': titulo,
    'grupo': grupo,
    'urgenciaBase': urgenciaBase,
    'subtareas': subtareas.map((s) => s.toJson()).toList(),
  };

  factory Plantilla.fromJson(Map<String, dynamic> json) => Plantilla(
    id: json['id'],
    nombre: json['nombre'] ?? '',
    titulo: json['titulo'] ?? '',
    grupo: json['grupo'] ?? 'General',
    urgenciaBase: json['urgenciaBase'] ?? 1,
    subtareas: (json['subtareas'] as List?)?.map((s) => ItemSubtarea.fromJson(s as Map<String, dynamic>)).toList() ?? [],
  );
}
