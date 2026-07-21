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

  NotaPostIt({
    required this.id,
    required this.texto,
    required this.colorValue,
    required this.rotacion,
    this.tipo = TipoNota.texto,
    List<ItemLista>? elementosLista,
  }) : elementosLista = elementosLista ?? [];

  Color get color => Color(colorValue);

  NotaPostIt copyWith({
    String? texto,
    int? colorValue,
    TipoNota? tipo,
    List<ItemLista>? elementosLista,
  }) {
    return NotaPostIt(
      id: id,
      texto: texto ?? this.texto,
      colorValue: colorValue ?? this.colorValue,
      rotacion: rotacion,
      tipo: tipo ?? this.tipo,
      elementosLista: elementosLista ?? this.elementosLista.map((e) => ItemLista(texto: e.texto, completado: e.completado)).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'texto': texto,
    'colorValue': colorValue,
    'rotacion': rotacion,
    'tipo': tipo.name,
    'elementosLista': elementosLista.map((e) => e.toMap()).toList(),
  };

  factory NotaPostIt.fromMap(Map<String, dynamic> map) => NotaPostIt(
    id: map['id'] ?? '',
    texto: map['texto'] ?? '',
    colorValue: map['colorValue'] ?? 0xFFFFF7D1,
    rotacion: (map['rotacion'] as num?)?.toDouble() ?? 0.0,
    tipo: TipoNota.values.firstWhere((e) => e.name == map['tipo'], orElse: () => TipoNota.texto),
    elementosLista: (map['elementosLista'] as List?)?.map((e) => ItemLista.fromMap(e as Map<String, dynamic>)).toList() ?? [],
  );
}
