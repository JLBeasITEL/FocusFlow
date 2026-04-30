import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/rutina_provider.dart';
import '../screens/rutina_form_screen.dart'; 
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
      color: activa ? Colors.white : Colors.grey.shade100.withOpacity(0.8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            // 1. ZONA IZQUIERDA: Checkbox e Ícono
            Checkbox(
              value: rutina.completada,
              activeColor: colorTema,
              onChanged: activa 
                  ? (_) => ref.read(rutinaProvider.notifier).toggleCompletada(rutina.id)
                  : null,
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorFuerte.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                IconData(rutina.iconoCode, fontFamily: 'MaterialIcons'),
                size: 26,
                color: colorFuerte,
              ),
            ),
            const SizedBox(width: 12), // Espacio separador

            // 2. ZONA CENTRAL: Textos y hora
            // Al quitar los días, la tarjeta queda mucho más limpia
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center, // Centramos verticalmente
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
                    // Leemos el día actual para saber qué hora mostrar
                    rutina.horarios[DateTime.now().weekday - 1]?.format(context) ?? '--:--',
                    style: TextStyle(fontSize: 14, color: colorFuerte, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            // 3. ZONA DERECHA: Rachas (Se eliminó el botón de editar)
            if (activa && rutina.racha > 0) ...[
              const SizedBox(width: 4),
              const Text('🔥', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 2),
              Text(
                '${rutina.racha}', 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)
              ),
              const SizedBox(width: 12), // Un pequeño espacio final para separar del borde del Card
            ],
          ],
        ),
      ),
    );
  }
}