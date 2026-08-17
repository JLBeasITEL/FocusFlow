import 'package:flutter/material.dart';

enum TipoNota { texto, lista }

class ItemLista {
  String texto;
  bool completado;
  ItemLista({required this.texto, this.completado = false});

  Map<String, dynamic> toMap() => {'texto': texto, 'completado': completado};
  factory ItemLista.fromMap(Map<String, dynamic> map) => ItemLista(
    texto: map['texto'] ?? '',
    completado: map['completado'] ?? false,
  );
}

class NotaPostIt {
  final String id;
  String texto;
  int colorValue;
  double rotacion;
  TipoNota tipo;
  List<ItemLista> elementosLista;
  // Título opcional ('' = sin título). Se muestra más grande que el
  // cuerpo, tanto en el diálogo de edición como en la tarjeta del tablero.
  String titulo;
  // Nombre del grupo al que pertenece ('' = suelta, sin grupo). La
  // identidad del grupo es su propio nombre: no existe una entidad
  // "grupo" separada, así que cuando la última nota con ese nombre se
  // desagrupa o se elimina, el grupo simplemente deja de existir.
  String grupoNombre;
  // true si el usuario la destacó para que aparezca en los widgets de
  // Notas (máximo 2 a la vez, ver alternarDestacada en nota_provider.dart).
  bool destacada;
  // Momento de creación (millisecondsSinceEpoch), independiente del orden
  // en el tablero (que el usuario puede reordenar arrastrando, ver
  // moverNota). Los widgets lo usan para elegir "las últimas 2 creadas"
  // cuando no hay ninguna destacada. Notas guardadas antes de este campo
  // existir quedan en 0 (la fecha real se perdió), lo que las trata como
  // las más antiguas posibles — comportamiento razonable por defecto.
  int creadaEn;

  NotaPostIt({
    required this.id,
    required this.texto,
    required this.colorValue,
    required this.rotacion,
    this.tipo = TipoNota.texto,
    List<ItemLista>? elementosLista,
    this.titulo = '',
    this.grupoNombre = '',
    this.destacada = false,
    this.creadaEn = 0,
  }) : elementosLista = elementosLista ?? [];

  Color get color => Color(colorValue);

  NotaPostIt copyWith({
    String? texto,
    int? colorValue,
    TipoNota? tipo,
    List<ItemLista>? elementosLista,
    String? titulo,
    String? grupoNombre,
    bool? destacada,
  }) {
    return NotaPostIt(
      id: id,
      texto: texto ?? this.texto,
      colorValue: colorValue ?? this.colorValue,
      rotacion: rotacion,
      tipo: tipo ?? this.tipo,
      elementosLista: elementosLista ?? this.elementosLista.map((e) => ItemLista(texto: e.texto, completado: e.completado)).toList(),
      titulo: titulo ?? this.titulo,
      grupoNombre: grupoNombre ?? this.grupoNombre,
      destacada: destacada ?? this.destacada,
      creadaEn: creadaEn,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'texto': texto,
    'colorValue': colorValue,
    'rotacion': rotacion,
    'tipo': tipo.name,
    'elementosLista': elementosLista.map((e) => e.toMap()).toList(),
    'titulo': titulo,
    'grupoNombre': grupoNombre,
    'destacada': destacada,
    'creadaEn': creadaEn,
  };

  factory NotaPostIt.fromMap(Map<String, dynamic> map) => NotaPostIt(
    id: map['id'] ?? '',
    texto: map['texto'] ?? '',
    colorValue: map['colorValue'] ?? 0xFFFFF7D1,
    rotacion: (map['rotacion'] as num?)?.toDouble() ?? 0.0,
    tipo: TipoNota.values.firstWhere((e) => e.name == map['tipo'], orElse: () => TipoNota.texto),
    elementosLista: (map['elementosLista'] as List?)?.map((e) => ItemLista.fromMap(e as Map<String, dynamic>)).toList() ?? [],
    titulo: map['titulo'] ?? '',
    grupoNombre: map['grupoNombre'] ?? '',
    destacada: map['destacada'] ?? false,
    creadaEn: (map['creadaEn'] as num?)?.toInt() ?? 0,
  );
}
