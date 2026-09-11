import 'package:flutter/material.dart';

// ============================================================
// AnilloTemporizadorRutina — estado visual propio para "temporizador en
// progreso" en el hueco del checkbox (adición A, ver memoria de la
// feature). Mismo patrón que "omitida" ya usa: un control distinto
// reemplaza al checkbox en su misma posición mientras dura ese estado
// (ver rutina_card.dart / rutina_card_landscape.dart).
// ------------------------------------------------------------
// Empieza vacío (fraccion = 0.0) y se llena en sentido horario hasta
// completarse (1.0) al vencer -- CircularProgressIndicator ya dibuja así
// por default, sin necesidad de un CustomPainter propio. Es puramente
// visual: el widget en sí no decide qué pasa al tocarlo, solo expone
// onTap para que quien lo use (RutinaCard/RutinaLandscapeCard) dispare el
// diálogo de confirmación compartido (ver manejarToqueAnilloTemporizador
// en temporizador_rutina_dialogo.dart) -- un solo lugar que decide esa
// lógica, no una por tarjeta.
// ============================================================
class AnilloTemporizadorRutina extends StatelessWidget {
  final double fraccion;
  final double tamano;
  final Color color;
  final VoidCallback onTap;

  const AnilloTemporizadorRutina({
    super.key,
    required this.fraccion,
    required this.tamano,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double grosor = tamano * 0.12;
    return InkResponse(
      onTap: onTap,
      radius: tamano * 0.75,
      child: SizedBox(
        width: tamano,
        height: tamano,
        child: Padding(
          padding: EdgeInsets.all(grosor / 2),
          child: CircularProgressIndicator(
            value: fraccion,
            strokeWidth: grosor,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ),
    );
  }
}
