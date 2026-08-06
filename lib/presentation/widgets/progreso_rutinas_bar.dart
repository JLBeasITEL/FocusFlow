import 'package:flutter/material.dart';
import '../../models/rutina.dart';
import '../../core/colores_estado_rutina.dart';

class ProgresoRutinasBar extends StatelessWidget {
  final List<Rutina> rutinasDeHoy;
  final Color colorTema;

  const ProgresoRutinasBar({
    super.key,
    required this.rutinasDeHoy,
    required this.colorTema,
  });

  @override
  Widget build(BuildContext context) {
    final int total = rutinasDeHoy.length;
    final int completadas = rutinasDeHoy.where((r) => r.completada).length;
    final int omitidas = rutinasDeHoy.where((r) => r.omitida).length;

    final double progresoCompletado = total == 0 ? 0.0 : completadas / total;
    final double progresoOmitido = total == 0 ? 0.0 : omitidas / total;
    final double progresoTotal = progresoCompletado + progresoOmitido;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Textos Superiores ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progreso de hoy',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorTema.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${(progresoTotal * 100).toInt()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorTema,
                      fontSize: 14,
                    ),
                  ),
                  // Aclaración de cuántas de esas son omitidas, solo si hay
                  // alguna: sin esto, "100%" se leería como "todo hecho"
                  // aunque parte sea en realidad omitida.
                  if (omitidas > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '($omitidas omitida${omitidas == 1 ? '' : 's'})',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorOmitidaRutina,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // --- Barra Personalizada con Degradado y Animación ---
          Container(
            height: 12, // Un poco más gruesa para lucir bien el degradado
            width: double.infinity,
            decoration: BoxDecoration(
              color: colorTema.withOpacity(0.15), // Fondo de la barra
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.centerLeft, // Para que se llene de izquierda a derecha

            // La magia de la animación suave
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progresoTotal),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                // Segmentos internos (completado sólido + omitido rayado) en
                // proporción fija completadas:omitidas, dentro del ancho ya
                // animado. ClipRRect solo en el borde exterior del conjunto,
                // igual que antes con un único Container redondeado.
                final List<Widget> segmentos = [
                  if (completadas > 0) Expanded(flex: completadas, child: _SegmentoCompletado(colorTema: colorTema)),
                  if (omitidas > 0) Expanded(flex: omitidas, child: const _SegmentoOmitido()),
                ];

                return FractionallySizedBox(
                  widthFactor: value, // Multiplicador de ancho (0.0 a 1.0)
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: segmentos.isEmpty ? null : Row(children: segmentos),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Tramo sólido con degradado, para las rutinas realmente completadas hoy.
class _SegmentoCompletado extends StatelessWidget {
  final Color colorTema;
  const _SegmentoCompletado({required this.colorTema});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorTema.withOpacity(0.4), // Inicia más claro
            colorTema,                  // Termina en tono sólido
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colorTema.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

// Tramo rayado en ámbar, para las rutinas omitidas hoy (pagadas con moneda de
// racha): color Y patrón distintos del completado a propósito, para que no
// dependa solo del color (accesibilidad / daltonismo).
class _SegmentoOmitido extends StatelessWidget {
  const _SegmentoOmitido();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RayasDiagonalesPainter(color: colorOmitidaRutina),
      child: const SizedBox.expand(),
    );
  }
}

class _RayasDiagonalesPainter extends CustomPainter {
  final Color color;
  const _RayasDiagonalesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color.withOpacity(0.35));

    final Paint raya = Paint()
      ..color = color.withOpacity(0.9)
      ..strokeWidth = 3;
    const double espaciado = 7;
    for (double x = -size.height; x < size.width + size.height; x += espaciado) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), raya);
    }
  }

  @override
  bool shouldRepaint(covariant _RayasDiagonalesPainter oldDelegate) => oldDelegate.color != color;
}
