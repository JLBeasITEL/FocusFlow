import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rutina.dart';
import '../providers/rutina_provider.dart';

// Marca/desmarca una rutina como completada hoy y, si el cambio cruza un
// nuevo múltiplo de rachaPorMoneda (7, 14, 21...), muestra el diálogo de
// felicitación. Compartido entre RutinaCard (portrait) y
// RutinaLandscapeCard para no duplicar ni la detección del hito ni el
// diálogo en sí.
Future<void> alternarCompletadaConCelebracion({
  required BuildContext context,
  required WidgetRef ref,
  required Rutina rutina,
  required bool marcarCompleta,
}) async {
  await ref.read(rutinaProvider.notifier).toggleCompletada(rutina.id);
  if (!context.mounted || !marcarCompleta) return;

  // Usamos rutina.racha (el valor ANTES del toggle) porque el widget que
  // llamó a esta función todavía no se reconstruyó con el nuevo valor.
  final nuevaRacha = rutina.racha + 1;
  if (nuevaRacha % rachaPorMoneda != 0) return;
  // Mismo criterio que toggleCompletada (rutina_provider.dart): si este
  // hito de racha ya se pagó antes (el usuario desmarcó y volvió a marcar
  // sobre el mismo múltiplo de 7), ya no se otorga una moneda nueva — así
  // que tampoco corresponde mostrar el diálogo de felicitación, que sin
  // este chequeo diría "+1 moneda" aunque no se otorgó ninguna.
  if (nuevaRacha <= rutina.rachaPagadaHasta) return;

  final String textoFelicidades =
      '¡Felicidades! Llevas $nuevaRacha veces seguidas sin fallar con este hábito.\n'
      '+1 moneda de racha 🪙';

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 72)),
          const SizedBox(height: 16),
          const Text('¡Racha Cumplida!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(textoFelicidades, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade700, height: 1.4)),
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
          ),
        ],
      ),
    ),
  );
}
