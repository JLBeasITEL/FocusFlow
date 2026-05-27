import 'package:flutter/material.dart';

// 1. Definimos los tipos
enum TipoNota { texto, lista }

// 2. Modelo para los elementos de la lista
class ItemLista {
  String texto;
  bool completado;

  ItemLista({required this.texto, this.completado = false});
}

// 3. La clase Nota principal
class Nota {
  final String id;
  String texto; 
  int colorValue; 
  double rotacion;
  TipoNota tipo;
  List<ItemLista> elementosLista;

  Nota({
    required this.id,
    required this.texto,
    required this.colorValue,
    required this.rotacion,
    this.tipo = TipoNota.texto,
    List<ItemLista>? elementosLista,
  }) : elementosLista = elementosLista ?? [];

  Color get color => Color(colorValue);
  
  Nota copyWith({
    String? texto, 
    int? colorValue,
    TipoNota? tipo,
    List<ItemLista>? elementosLista,
  }) {
    return Nota(
      id: id,
      texto: texto ?? this.texto,
      colorValue: colorValue ?? this.colorValue,
      rotacion: rotacion,
      tipo: tipo ?? this.tipo,
      // Copiamos profundamente la lista para evitar errores de referencia
      elementosLista: elementosLista ?? this.elementosLista.map((e) => ItemLista(texto: e.texto, completado: e.completado)).toList(),
    );
  }
}