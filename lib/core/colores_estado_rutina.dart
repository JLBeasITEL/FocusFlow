import 'package:flutter/material.dart';

// Color fijo para el estado "omitida" de una rutina, independiente del color
// de tema de cada rutina — mismo criterio que la paleta de estado fija de
// RutinasWidgetProvider.kt (verde/gris), para no mezclar significados entre
// el color de tema (identidad de la rutina) y el color de estado (qué pasó
// hoy con ella). Compartido entre ProgresoRutinasBar y RutinaCard para que
// el mismo color signifique "omitida" en toda la UI.
const Color colorOmitidaRutina = Color(0xFFF59E0B); // ámbar
