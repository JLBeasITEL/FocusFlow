import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/rutina.dart';
import '../../providers/rutina_provider.dart';

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
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Icono
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorFuerte.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(IconData(rutina.iconoCode, fontFamily: 'MaterialIcons'), size: 30, color: colorFuerte),
            ),
            const SizedBox(width: 16),
            
            // Información
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rutina.titulo,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: activa ? Colors.black87 : Colors.grey,
                      decoration: activa ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  Text(
                    rutina.horaDian.format(context),
                    style: TextStyle(fontSize: 15, color: colorFuerte, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  // Indicador de días
                  Row(
                    children: ['L', 'M', 'M', 'J', 'V', 'S', 'D'].asMap().entries.map((entry) {
                      bool diaActivo = rutina.diasSemana[entry.key];
                      return Container(
                        margin: const EdgeInsets.only(right: 4),
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: diaActivo && activa ? colorFuerte : Colors.grey.shade300,
                        ),
                        child: Text(
                          entry.value,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: diaActivo && activa ? Colors.white : Colors.grey.shade600),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            // Switch y Racha
            Column(
              children: [
                Switch(
                  value: activa,
                  activeColor: colorTema,
                  onChanged: (_) => ref.read(rutinaProvider.notifier).toggleActiva(rutina.id),
                ),
                if (activa && rutina.racha > 0)
                  Row(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 12)),
                      Text('${rutina.racha}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }
}