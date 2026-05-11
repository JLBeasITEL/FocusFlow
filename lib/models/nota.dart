import 'package:flutter/material.dart';

class Nota {
  final String id;
  final String texto;
  final int colorValue; // Guardamos el valor numérico del color
  final double rotacion;

  Nota({
    required this.id,
    required this.texto,
    required this.colorValue,
    required this.rotacion,
  });

  // Para poder usar el color en los widgets fácilmente
  Color get color => Color(colorValue);
}