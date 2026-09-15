import 'dart:math' as math;

// Tamaño mínimo de celda (dp) para el tablero de notas: por debajo de esto
// una nota deja de ser usable (texto ilegible, clip de borrado imposible de
// tocar, contenido desbordado). Compartido entre el tablero principal
// (home_screen.dart) y la pantalla de un grupo (grupo_notas_card.dart) para
// que ambos ajusten el tamaño de celda al mismo criterio.
const double tamanoMinimoCeldaNotas = 140.0;

// Prueba cada cantidad de columnas viable y elige la que produce las celdas
// cuadradas más grandes sin que el total de filas necesite más alto del
// disponible: así las notas se ajustan al tamaño de pantalla y a la
// orientación del dispositivo dejando el mínimo espacio vacío.
int calcularColumnasOptimas({
  required int totalCeldas,
  required double anchoDisponible,
  required double altoDisponible,
  required double espaciado,
  double tamanoMinimoCelda = tamanoMinimoCeldaNotas,
}) {
  if (totalCeldas <= 0 || anchoDisponible <= 0) return 1;
  const int minColumnas = 1;
  final int columnasPorAncho = ((anchoDisponible + espaciado) / (tamanoMinimoCelda + espaciado)).floor();
  final int maxColumnas = math.max(minColumnas, math.min(totalCeldas, columnasPorAncho));

  int mejorColumnas = minColumnas;
  double mejorTamanoCelda = 0;

  for (int c = minColumnas; c <= maxColumnas; c++) {
    final double tamanoCelda = (anchoDisponible - espaciado * (c - 1)) / c;
    if (tamanoCelda <= 0) continue;
    final int filas = (totalCeldas / c).ceil();
    final double altoNecesario = filas * tamanoCelda + espaciado * (filas - 1);

    if (altoNecesario <= altoDisponible && tamanoCelda > mejorTamanoCelda) {
      mejorColumnas = c;
      mejorTamanoCelda = tamanoCelda;
    }
  }

  // Si ninguna combinación entra sin scroll (pantalla chica o muchas notas),
  // nos quedamos con la que exige más columnas: son las celdas más chicas,
  // pero las que menos alto ocupan.
  if (mejorTamanoCelda == 0) mejorColumnas = maxColumnas;

  return mejorColumnas;
}
