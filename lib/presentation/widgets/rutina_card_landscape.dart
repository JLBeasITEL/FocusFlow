import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/rutina.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../providers/tema_provider.dart';
import '../../core/colores_estado_rutina.dart';
import '../../core/celebracion_racha.dart';
import '../../core/app_messenger.dart';

// Versión compacta de RutinaCard (widgets/rutina_card.dart) para la grilla
// de 3 columnas del layout horizontal: mismas acciones (marcar completada,
// con la celebración de racha, y omitir por hoy) en una tarjeta cuadrada
// en vez de una fila alta.
class RutinaLandscapeCard extends ConsumerWidget {
  final Rutina rutina;
  final TemaApp tema;
  const RutinaLandscapeCard({super.key, required this.rutina, required this.tema});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool activa = rutina.activa;
    final bool omitida = rutina.omitida;
    final Color colorFuerte = activa ? tema.colorPrincipal : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tema.colorSuperficieCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorFuerte.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (omitida)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Deshacer omisión (te devuelve las monedas)',
                  icon: Icon(Icons.settings_backup_restore_rounded, color: colorOmitidaRutina, size: 20),
                  onPressed: !activa ? null : () => ref.read(rutinaProvider.notifier).toggleOmitida(rutina.id),
                )
              else
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: rutina.completada,
                    activeColor: tema.colorPrincipal,
                    onChanged: !activa
                        ? null
                        : (valor) => alternarCompletadaConCelebracion(
                              context: context,
                              ref: ref,
                              rutina: rutina,
                              marcarCompleta: valor == true,
                            ),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: colorFuerte.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(IconData(rutina.iconoCode, fontFamily: 'MaterialIcons'), color: colorFuerte, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rutina.titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              decoration: rutina.completada ? TextDecoration.lineThrough : null,
              color: omitida ? colorOmitidaRutina : (activa ? tema.colorTextoSuperficie : Colors.grey),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            omitida ? 'Omitida hoy' : (rutina.horarios[DateTime.now().weekday - 1]?.format(context) ?? '--:--'),
            style: TextStyle(fontSize: 11, color: omitida ? colorOmitidaRutina : colorFuerte, fontWeight: FontWeight.w600),
          ),
          if (activa && (rutina.racha > 0 || (!rutina.completada && !omitida))) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (rutina.racha > 0) ...[
                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.orange)),
                  const SizedBox(width: 4),
                  Text('${rutina.racha}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)),
                ],
                const Spacer(),
                if (!rutina.completada && !omitida) _BotonOmitirCompacto(rutina: rutina),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// Mismo comodín de "omitir por hoy" que _BotonOmitirRutina (rutina_card.dart),
// en versión compacta para caber dentro de la tarjeta cuadrada de la grilla.
class _BotonOmitirCompacto extends ConsumerWidget {
  final Rutina rutina;
  const _BotonOmitirCompacto({required this.rutina});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int monedas = ref.watch(monedasProvider);
    final int costo = rutina.omisionesSeguidas + 1;
    final bool alcanza = monedas >= costo;
    final Color color = alcanza ? colorOmitidaRutina : Colors.grey;

    return Tooltip(
      message: alcanza
          ? 'Omitir hoy por $costo 🪙 (protege tu racha)'
          : 'Te faltan monedas de racha: necesitas $costo, tienes $monedas',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          final bool exito = await ref.read(rutinaProvider.notifier).toggleOmitida(rutina.id);
          if (!exito) {
            mostrarSnackBarSimple(
              mensaje: 'No te alcanzan las monedas de racha para omitir "${rutina.titulo}" (necesitas $costo, tienes $monedas).',
              colorFondo: colorOmitidaRutina,
              colorTexto: Colors.white,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.redo_rounded, size: 12, color: color),
              const SizedBox(width: 2),
              Text('$costo🪙', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
