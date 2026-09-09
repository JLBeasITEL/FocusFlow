import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rutina.dart';
import '../providers/rutina_provider.dart';
import '../providers/monedas_provider.dart';
import '../providers/temporizador_rutina_provider.dart';
import 'colores_estado_rutina.dart';
import 'app_messenger.dart';
import 'celebracion_racha.dart';

// ============================================================
// manejarToqueCheckboxRutina — único punto de entrada del checkbox
// ------------------------------------------------------------
// Punto de convergencia único para las tres UI que pueden marcar una
// rutina como completada: el checkbox de RutinaCard (portrait), el de
// RutinaLandscapeCard, y el botón "Completar" del panel de detalle en
// landscape (home_screen.dart) — ninguna de las tres implementa su
// propia decisión de "¿toca el diálogo del temporizador o se completa
// directo?", todas llaman acá.
//
// Reglas (diseño acordado, ver auditoría previa):
//   - Desmarcar (valor != true) SIEMPRE va directo, sin diálogo, tenga
//     o no duración configurada.
//   - Si ya está completada u omitida, SIEMPRE directo (no debería
//     llegar acá con valor==true en ese estado, pero es la misma regla
//     aplicada de forma defensiva).
//   - Si no hay duración configurada para HOY (0 minutos), directo.
//   - Si ya hay un temporizador corriendo para ESTA MISMA rutina, no
//     se hace nada: no hay pausa/reanudación ni reinicio del conteo
//     (ver diseño acordado, "Sin pausa ni reanudación. Solo
//     cancelar."); la única forma de tocar un temporizador activo es
//     editar/desactivar/borrar/omitir la rutina (ver rutina_provider.dart).
//   - En cualquier otro caso: se abre el diálogo de duración.
// ============================================================
Future<void> manejarToqueCheckboxRutina({
  required BuildContext context,
  required WidgetRef ref,
  required Rutina rutina,
  required bool? valor,
}) async {
  if (valor != true || rutina.completada || rutina.omitida) {
    await alternarCompletadaConCelebracion(
      context: context,
      ref: ref,
      rutina: rutina,
      marcarCompleta: valor == true,
    );
    return;
  }

  // Misma fuente de "ahora" que el resto del feature (nunca DateTime.now()
  // directo), y misma convención de índice de día que horarios/duraciones
  // (0=lunes..6=domingo, ver rutina_provider.dart._calcularProximaFecha).
  final DateTime ahora = ref.read(relojProvider)();
  final int hoyIndex = ahora.weekday - 1;
  final int duracionHoy = rutina.duraciones[hoyIndex] ?? 0;

  if (duracionHoy <= 0) {
    await alternarCompletadaConCelebracion(
      context: context,
      ref: ref,
      rutina: rutina,
      marcarCompleta: true,
    );
    return;
  }

  final TemporizadorRutina? activo = ref.read(temporizadorRutinaProvider);
  if (activo != null && activo.rutinaId == rutina.id) {
    return;
  }

  if (!context.mounted) return;
  await _mostrarDialogoTemporizador(
    context: context,
    ref: ref,
    rutina: rutina,
    duracionMinutos: duracionHoy,
  );
}

Future<void> _mostrarDialogoTemporizador({
  required BuildContext context,
  required WidgetRef ref,
  required Rutina rutina,
  required int duracionMinutos,
}) {
  final int costo = rutina.omisionesSeguidas + 1;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Temporizador de la rutina'),
      content: Text(
        'Esta rutina tiene un temporizador de $duracionMinutos minutos. '
        'Al aceptar, empieza la cuenta atrás — recién al terminar podrás confirmarla como hecha.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Regresar'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            final int monedas = ref.read(monedasProvider);
            final bool exito = await ref.read(rutinaProvider.notifier).toggleOmitida(rutina.id);
            if (!exito) {
              mostrarSnackBarSimple(
                mensaje: 'No te alcanzan las monedas de racha para omitir "${rutina.titulo}" '
                    '(necesitas $costo, tienes $monedas).',
                colorFondo: colorOmitidaRutina,
                colorTexto: Colors.white,
              );
            }
          },
          child: Text('Omitir · $costo🪙', style: TextStyle(color: colorOmitidaRutina, fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            final DateTime venceEn = ref.read(relojProvider)().add(Duration(minutes: duracionMinutos));
            await ref.read(temporizadorRutinaProvider.notifier).iniciar(rutinaId: rutina.id, venceEn: venceEn);
          },
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
}
