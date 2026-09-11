import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/rutina.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../providers/tema_provider.dart';
import '../../providers/temporizador_rutina_provider.dart';
import '../../core/colores_estado_rutina.dart';
import '../../core/app_messenger.dart';
import '../../core/temporizador_rutina_dialogo.dart';
import 'anillo_temporizador_rutina.dart';

// Versión compacta de RutinaCard (widgets/rutina_card.dart) para la grilla
// de 3 columnas del layout horizontal: mismas acciones (marcar completada,
// con la celebración de racha, y omitir por hoy) en una tarjeta cuadrada
// en vez de una fila alta.
class RutinaLandscapeCard extends ConsumerWidget {
  final Rutina rutina;
  final TemaApp tema;
  // Abre/actualiza el panel de detalle (título completo + descripción) en
  // home_screen.dart, que decide él mismo si esto es una nueva selección o
  // un toggle-para-cerrar (compara contra la rutina ya seleccionada). Esta
  // tarjeta no sabe nada de ese estado, solo avisa que la tocaron.
  final VoidCallback onTap;
  const RutinaLandscapeCard({super.key, required this.rutina, required this.tema, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool activa = rutina.activa;
    final bool omitida = rutina.omitida;
    final Color colorFuerte = activa ? tema.colorPrincipal : Colors.grey;
    // Mismo .select que rutina_card.dart (portrait): esta tarjeta solo se
    // repinta cuando el temporizador que cambia es el de ESTA rutina. El
    // record agrupa segundosRestantes (texto) y fraccionCompletada (anillo)
    // en una sola suscripción.
    final (int, double)? temporizadorPropio = ref.watch(
      temporizadorRutinaProvider.select(
        (t) => (t != null && t.rutinaId == rutina.id) ? (t.segundosRestantes, t.fraccionCompletada) : null,
      ),
    );
    final int? segundosRestantes = temporizadorPropio?.$1;
    final double? fraccionTemporizador = temporizadorPropio?.$2;
    // Mismo criterio que en rutina_card.dart (portrait): "Omitida hoy" es su
    // propia etiqueta de estado y se mantiene; al completar sin omitir no
    // queda ninguna etiqueta de hora (checkbox marcado + título tachado ya
    // lo comunican). Con un temporizador activo para esta rutina, el
    // contador tiene precedencia sobre ambas (ver diseño acordado).
    final bool ocultarHora = rutina.completada && !omitida && segundosRestantes == null;

    // Todo el cuerpo de la tarjeta es tocable (abre/actualiza el panel de
    // detalle en home_screen.dart), sin robarle el gesto al checkbox, al
    // botón de deshacer omisión ni a la pastilla de omitir: los tres son
    // descendientes de este GestureDetector, y en la gesture arena de
    // Flutter el recognizer más profundo (el del control) gana sobre el del
    // padre — es el mismo mecanismo del que depende, por ejemplo, un
    // ListTile con un IconButton de trailing. HitTestBehavior.opaque hace
    // que el padding entre esos controles también sea tocable, no solo el
    // texto pintado.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tema.colorSuperficieCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorFuerte.withValues(alpha: 0.18)),
        ),
        // Sin mainAxisSize.min (queremos que el Column SÍ llene el alto fijo
        // de la celda, ver mainAxisExtent en home_screen.dart) y con
        // mainAxisAlignment.center: cuando ocultarHora (o cualquier otro
        // motivo futuro) deja menos contenido, se centra dentro de esa altura
        // fija en vez de quedar arriba con un hueco al fondo — el grid ya
        // fuerza la misma altura de celda para todas las tarjetas, así que
        // acá no hay opción de "encoger", solo de recentrar.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                // Temporizador activo para ESTA rutina: reemplaza al checkbox
                // (misma precedencia que en RutinaCard/portrait). Tamaño
                // igual al SizedBox de 24x24 que ya usaba el checkbox, para
                // no correr el resto de la fila.
                if (segundosRestantes != null)
                  AnilloTemporizadorRutina(
                    fraccion: fraccionTemporizador!,
                    tamano: 24,
                    color: tema.colorPrincipal,
                    onTap: () => manejarToqueAnilloTemporizador(context: context, ref: ref, rutina: rutina),
                  )
                else if (omitida)
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
                          : (valor) => manejarToqueCheckboxRutina(
                                context: context,
                                ref: ref,
                                rutina: rutina,
                                valor: valor,
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
            if (!ocultarHora) ...[
              const SizedBox(height: 2),
              Text(
                segundosRestantes != null
                    ? formatoCuentaRegresiva(segundosRestantes)
                    : (omitida ? 'Omitida hoy' : (rutina.horarios[DateTime.now().weekday - 1]?.format(context) ?? '--:--')),
                style: TextStyle(
                  fontSize: 11,
                  color: (omitida && segundosRestantes == null) ? colorOmitidaRutina : colorFuerte,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
      ),
    );
  }
}

// Ejecuta la omisión y avisa si no alcanzan las monedas — la parte
// riesgosa de "omitir" (costo, gasto, feedback si falla) en un único
// lugar, compartida entre _BotonOmitirCompacto (pastilla de la tarjeta) y
// BotonOmitirRutinaPanel (botón grande del panel de detalle en
// home_screen.dart), para que ambos muestren siempre el mismo precio y el
// mismo mensaje de "no alcanza" en vez de arriesgarse a que diverjan.
Future<void> omitirRutinaLandscapeConFeedback({
  required WidgetRef ref,
  required Rutina rutina,
  required int costo,
  required int monedas,
}) async {
  final bool exito = await ref.read(rutinaProvider.notifier).toggleOmitida(rutina.id);
  if (!exito) {
    mostrarSnackBarSimple(
      mensaje: 'No te alcanzan las monedas de racha para omitir "${rutina.titulo}" (necesitas $costo, tienes $monedas).',
      colorFondo: colorOmitidaRutina,
      colorTexto: Colors.white,
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
        onTap: () => omitirRutinaLandscapeConFeedback(ref: ref, rutina: rutina, costo: costo, monedas: monedas),
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

// Versión grande del botón de omitir, para el panel de detalle
// (home_screen.dart). Misma fuente de verdad que la pastilla de la
// tarjeta (omitirRutinaLandscapeConFeedback): mismo costo, mismo mensaje
// si no alcanzan las monedas — solo cambia la presentación.
class BotonOmitirRutinaPanel extends ConsumerWidget {
  final Rutina rutina;
  const BotonOmitirRutinaPanel({super.key, required this.rutina});

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
      child: OutlinedButton.icon(
        onPressed: () => omitirRutinaLandscapeConFeedback(ref: ref, rutina: rutina, costo: costo, monedas: monedas),
        icon: Icon(Icons.redo_rounded, size: 18, color: color),
        label: Text('Omitir · $costo🪙', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
