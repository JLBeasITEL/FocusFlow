import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/rutina_provider.dart';
import '../../models/rutina.dart';

class RutinaCard extends ConsumerWidget {
  final Rutina rutina;
  final Color colorTema;

  const RutinaCard({super.key, required this.rutina, required this.colorTema});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool activa = rutina.activa;
    final Color colorFuerte = activa ? colorTema : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: activa ? 4 : 0,
      color: activa ? Colors.white : Colors.grey.shade100.withValues(alpha: 0.8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            // 1. ZONA IZQUIERDA: Checkbox e Ícono
            Checkbox(
              value: rutina.completada,
              activeColor: colorTema,
              onChanged: !activa 
                ? null 
                : (bool? valor) {
                  // 1. Ejecutamos el cambio de estado en la base de datos
                  ref.read(rutinaProvider.notifier).toggleCompletada(rutina.id);

                  // 2. Si el usuario acaba de marcar la tarea como completada
                  if (valor == true) {
                    final nuevaRacha = rutina.racha + 1;
                    
                    // ¿Cuántos días a la semana está programado este hábito?
                    final diasPorSemana = rutina.horarios.length;
                    if (diasPorSemana == 0) return; // Evitar errores si no hay días

                    // 3. Verificamos si completó un "ciclo semanal" exacto de su hábito
                    if (nuevaRacha > 0 && nuevaRacha % diasPorSemana == 0) {
                      
                      // Calculamos cuántas semanas reales lleva cumpliendo
                      final semanas = nuevaRacha ~/ diasPorSemana;
                      
                      // 4. Lógica de texto inteligente
                      String textoFelicidades;
                      if (diasPorSemana >= 5) {
                        // Si son 5, 6 o 7 días, celebramos el número de días
                        textoFelicidades = '¡Felicidades! Has mantenido este hábito impecable durante $nuevaRacha días seguidos.';
                      } else {
                        // Si son menos de 5 días, celebramos el número de semanas
                        final pluralSemanas = semanas == 1 ? '1 semana consecutiva' : '$semanas semanas consecutivas';
                        textoFelicidades = '¡Felicidades! Has mantenido este hábito impecable durante $pluralSemanas.';
                      }

                      // 5. Mostramos la felicitación
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🔥', style: TextStyle(fontSize: 72)),
                              const SizedBox(height: 16),
                              const Text(
                                '¡Racha Cumplida!', 
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
                              ),
                              const SizedBox(height: 12),
                              Text(
                                textoFelicidades,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade700, height: 1.4),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  minimumSize: const Size(double.infinity, 50),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: const Text('¡A seguir así!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              )
                            ],
                          ),
                        ),
                      );
                    }
                  }
                },
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorFuerte.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                IconData(rutina.iconoCode, fontFamily: 'MaterialIcons'),
                color: colorFuerte,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // 2. ZONA CENTRAL: Título y Hora
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rutina.titulo,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      decoration: rutina.completada ? TextDecoration.lineThrough : null,
                      color: activa ? Colors.black87 : Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis, 
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rutina.horarios[DateTime.now().weekday - 1]?.format(context) ?? '--:--',
                    style: TextStyle(fontSize: 14, color: colorFuerte, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            // 3. ZONA DERECHA: Rachas
            if (activa && rutina.racha > 0) ...[
              const SizedBox(width: 4),
              const Text('🔥', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 2),
              Text(
                '${rutina.racha}', 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)
              ),
              const SizedBox(width: 12), 
            ],
          ],
        ),
      ),
    );
  }
}