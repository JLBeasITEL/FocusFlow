import 'package:flutter/material.dart';
import '../../models/rutina.dart';

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
    double progreso = 0.0;
    
    if (rutinasDeHoy.isNotEmpty) {
      final completadas = rutinasDeHoy.where((r) => r.completada).length;
      progreso = completadas / rutinasDeHoy.length;
    }

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
              Text(
                '${(progreso * 100).toInt()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  color: colorTema,
                  fontSize: 14,
                ),
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
              tween: Tween<double>(begin: 0, end: progreso),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic, 
              builder: (context, value, _) {
                return FractionallySizedBox(
                  widthFactor: value, // Multiplicador de ancho (0.0 a 1.0)
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      // El degradado dinámico basado en tu tema
                      gradient: LinearGradient(
                        colors: [
                          colorTema.withOpacity(0.4), // Inicia más claro
                          colorTema,                  // Termina en tono sólido
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      // Sutil efecto de brillo para darle profundidad
                      boxShadow: [
                        BoxShadow(
                          color: colorTema.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
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