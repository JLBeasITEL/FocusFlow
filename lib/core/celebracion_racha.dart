import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rutina.dart';
import '../providers/rutina_provider.dart';

// Marca/desmarca una rutina como completada hoy y, si el cambio cierra un
// hito de racha que otorga monedas, muestra el diálogo de felicitación.
// Compartido entre RutinaCard (portrait) y RutinaLandscapeCard para no
// duplicar ni la detección del hito ni el diálogo en sí.
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
  // MISMA función que usa toggleCompletada para acreditar (ver
  // rutina_provider.dart), no una copia del criterio: si devuelve null no
  // se otorgó ninguna moneda —hito no alcanzado, o ya cobrado porque el
  // usuario desmarcó y volvió a marcar sobre el mismo hito— y entonces
  // tampoco corresponde festejar. Sin este chequeo el diálogo diría
  // "+N monedas" aunque no se otorgó ninguna.
  final RecompensaRacha? recompensa = calcularRecompensaRacha(
    diasPorSemana: rutina.diasPorSemana,
    nuevaRacha: nuevaRacha,
    rachaPagadaHasta: rutina.rachaPagadaHasta,
  );
  if (recompensa == null) return;

  // El multiplicador solo se nombra cuando de verdad multiplicó: en la
  // primera semana (x1) mencionarlo sería ruido.
  final String plural = recompensa.monedas == 1 ? 'moneda' : 'monedas';
  final String detalleMultiplicador = recompensa.multiplicador > 1
      ? '\n×${recompensa.multiplicador} por llevar ${recompensa.semanas} semanas en racha'
      : '';
  final String textoFelicidades =
      '¡Felicidades! Llevas $nuevaRacha veces seguidas sin fallar con este hábito.\n'
      '+${recompensa.monedas} $plural de racha 🪙$detalleMultiplicador';

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
