// ============================================================================
// rutina_card.dart — VERSIÓN COMENTADA
// ============================================================================
// Este widget dibuja UNA tarjeta individual de rutina dentro de la lista.
// Es el lugar donde el usuario interactúa directamente con una rutina:
// marcarla como completa, ver su racha, su ícono, título y hora.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/rutina_provider.dart'; // Acceso al provider que maneja el estado global de rutinas
import '../../providers/monedas_provider.dart'; // Saldo de monedas de racha, para el botón de omitir
import '../../models/rutina.dart';             // El modelo de datos "Rutina"
import '../../core/colores_estado_rutina.dart';
import '../../core/app_messenger.dart';
import '../../core/celebracion_racha.dart';

// ConsumerWidget: es un widget "sin estado propio" (stateless) pero que SÍ puede
// leer/escuchar el provider de Riverpod a través del parámetro `ref`.
class RutinaCard extends ConsumerWidget {
  // Datos que este widget recibe desde afuera (desde la lista que lo construye).
  final Rutina rutina;     // La rutina específica que esta tarjeta va a mostrar
  final Color colorTema;   // Color del tema visual de esta rutina (para íconos, texto, etc.)

  // Expansión: la decide el PADRE (la lista), no esta tarjeta. Así solo una
  // tarjeta puede estar expandida a la vez sin que RutinaCard necesite
  // estado propio (sigue siendo ConsumerWidget, no Stateful).
  final bool esExpandida;
  final VoidCallback onToggleExpansion;

  // Constructor: todos los parámetros son obligatorios (required).
  const RutinaCard({
    super.key,
    required this.rutina,
    required this.colorTema,
    required this.esExpandida,
    required this.onToggleExpansion,
  });

  @override
  // build() se ejecuta cada vez que este widget necesita dibujarse o redibujarse.
  // `context` da acceso al árbol de widgets; `ref` da acceso al estado de Riverpod.
  Widget build(BuildContext context, WidgetRef ref) {

    // Variable local: ¿esta rutina está activa (encendida) o desactivada por el usuario?
    final bool activa = rutina.activa;

    final bool tieneDescripcion = rutina.descripcion != null && rutina.descripcion!.trim().isNotEmpty;

    // ¿La ocurrencia de HOY fue omitida a propósito (pagada con monedas de
    // racha)? Es un tercer estado, distinto de "pendiente" y de "completada".
    final bool omitida = rutina.omitida;

    // Si la rutina está activa, usamos su color de tema; si está desactivada, todo se ve gris.
    final Color colorFuerte = activa ? colorTema : Colors.grey;

    return Card(
      // Espacio debajo de cada tarjeta, para separarla de la siguiente.
      margin: const EdgeInsets.only(bottom: 16),

      // Bordes redondeados de la tarjeta (20px de radio).
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

      // Sombra: más elevación (más "flotante") si está activa; sin sombra si está apagada.
      elevation: activa ? 4 : 0,

      // Color de fondo: blanco si activa, gris muy claro y semitransparente si está apagada.
      color: activa ? Colors.white : Colors.grey.shade100.withValues(alpha: 0.8),

      // Necesario para que el ripple del InkWell respete las esquinas redondeadas.
      clipBehavior: Clip.antiAlias,

      child: InkWell(
        // Tocar la tarjeta la expande (o la colapsa si ya estaba expandida).
        // Los controles internos (Checkbox, botón de deshacer, pastilla de
        // omitir) tienen su propio InkWell/gesto y ganan el toque cuando cae
        // sobre ellos, así que no compiten por el mismo tap con este.
        onTap: onToggleExpansion,
        child: Padding(
          // Relleno interno de la tarjeta (espacio entre el borde y el contenido).
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),

          // Row: acomoda todo el contenido en una sola fila horizontal.
          // crossAxisAlignment start: ancla checkbox/ícono/pastilla arriba,
          // para que no "floten" al centro cuando la tarjeta crece al expandirse.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ================================================================
              // 1. ZONA IZQUIERDA: estado del día (Checkbox, u omitida) + ícono
              // ================================================================
              // Si la ocurrencia de hoy fue omitida, no tiene sentido mostrar el
              // checkbox normal (no se puede "completar" algo que se saltó sin
              // deshacer la omisión primero): en su lugar mostramos un botón
              // para deshacer, que reembolsa exactamente lo que costó.
              if (omitida)
                IconButton(
                  tooltip: 'Deshacer omisión (te devuelve las monedas)',
                  icon: Icon(Icons.settings_backup_restore_rounded, color: colorOmitidaRutina),
                  onPressed: !activa
                      ? null
                      : () async {
                          await ref.read(rutinaProvider.notifier).toggleOmitida(rutina.id);
                        },
                )
              else
              Checkbox(
                // El checkbox refleja si la rutina ya está marcada como completa hoy.
                value: rutina.completada,

                // Color que toma el checkbox cuando está marcado (usa el color del tema).
                activeColor: colorTema,

                // onChanged define qué pasa cuando el usuario toca el checkbox.
                // Si la rutina NO está activa, el checkbox se deshabilita (null = inactivo, no se puede tocar).
                onChanged: !activa
                  ? null
                  // Si SÍ está activa, definimos la función que se ejecuta al tocarlo.
                  // Es "async" porque adentro vamos a usar "await" para esperar
                  // a que termine el proceso de cancelar/reprogramar notificaciones
                  // ANTES de continuar con el resto de la lógica (evita condiciones de carrera).
                  : (bool? valor) => alternarCompletadaConCelebracion(
                      context: context,
                      ref: ref,
                      rutina: rutina,
                      marcarCompleta: valor == true,
                    ),
              ),

              // Ícono de la rutina, con una pista discreta en la esquina si
              // tiene descripción (para que se sepa que hay algo más al
              // expandir, incluso antes de tocar la tarjeta).
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      // Fondo del círculo: el color del tema pero muy tenue (10% de opacidad).
                      color: colorFuerte.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      // Reconstruye el ícono a partir del código numérico guardado en la rutina.
                      IconData(rutina.iconoCode, fontFamily: 'MaterialIcons'),
                      color: colorFuerte,
                      size: 24,
                    ),
                  ),
                  if (tieneDescripcion)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Icon(Icons.notes_rounded, size: 11, color: colorFuerte),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12), // Separación horizontal antes del texto

              // ================================================================
              // 2. ZONA CENTRAL: título, hora, racha y (si está expandida) descripción
              // ================================================================
              Expanded(
                // IntrinsicHeight + stretch: le da a la pastilla de omitir (más
                // abajo) la altura completa de esta fila como zona táctil,
                // en vez de ensancharla con un SizedBox horizontal (eso fue lo
                // que causaba el RenderFlex overflow: un ancho fijo de 48dp no
                // le alcanzaba al contenido de la pastilla). Solo afecta a esta
                // sub-fila (título/hora/descripción + pastilla), no al ícono ni
                // al checkbox de la izquierda.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        // Expanded hace que esta columna ocupe todo el espacio horizontal
                        // sobrante entre el ícono (izquierda) y la pastilla de omitir (derecha).
                        // ConstrainedBox(minHeight: 48): garantiza que la fila nunca sea
                        // más baja que el mínimo táctil de Material, sin importar métricas
                        // exactas de fuente — así la pastilla (que estira su altura a la
                        // de esta columna) siempre llega a >=48dp de alto.
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, // Alinea el texto a la izquierda
                          children: [
                            // Título + racha en la misma fila: la racha queda anclada
                            // arriba a la derecha, alineada con la primera línea del título.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    rutina.titulo,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      // Si ya está completada, le pone una línea tachada encima del texto.
                                      decoration: rutina.completada ? TextDecoration.lineThrough : null,
                                      // Color del texto: ámbar si se omitió hoy, negro si activa, gris si desactivada.
                                      color: omitida ? colorOmitidaRutina : (activa ? Colors.black87 : Colors.grey),
                                    ),
                                    // Colapsada: hasta 2 líneas con "...". Expandida: sin límite.
                                    maxLines: esExpandida ? null : 2,
                                    overflow: esExpandida ? TextOverflow.visible : TextOverflow.ellipsis,
                                  ),
                                ),
                                if (activa && rutina.racha > 0) ...[
                                  const SizedBox(width: 6),
                                  _RachaBadge(racha: rutina.racha),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),

                            // Hora programada para HOY, o la etiqueta de estado "Omitida"
                            // si se pagó con monedas para saltarla — igual que el widget
                            // de pantalla de inicio, que ya distingue Pendiente/Hecha/Omitida.
                            Text(
                              omitida
                                  ? 'Omitida hoy'
                                  : (rutina.horarios[DateTime.now().weekday - 1]?.format(context) ?? '--:--'),
                              style: TextStyle(
                                fontSize: 14,
                                color: omitida ? colorOmitidaRutina : colorFuerte,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            // Descripción opcional: solo visible con la tarjeta expandida.
                            // AnimatedSize hace que la tarjeta crezca/encoja con una
                            // transición suave en vez de un salto brusco (mismo patrón
                            // de TareaCard: 300ms, easeInOut).
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              alignment: Alignment.topLeft,
                              child: esExpandida && tieneDescripcion
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        rutina.descripcion!,
                                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.3),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                        ),
                      ),

                      // ================================================================
                      // 3. Botón "Omitir por hoy": solo tiene sentido si todavía está
                      // pendiente (ni completada ni ya omitida) y la rutina está activa.
                      // Vive en este Row (no en el externo) para heredar, vía stretch,
                      // la altura completa de la columna título/hora/descripción como
                      // zona táctil vertical.
                      // ================================================================
                      if (activa && !rutina.completada && !omitida) _BotonOmitirRutina(rutina: rutina),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// _RachaBadge — contador de racha (🔥N) compacto y solo informativo.
// Se ancla junto a la primera línea del título, no es tocable (sin
// InkWell): a diferencia de _BotonOmitirRutina, no dispara ninguna acción.
// ============================================================
class _RachaBadge extends StatelessWidget {
  final int racha;
  const _RachaBadge({required this.racha});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 2),
          Text(
            '$racha',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// _BotonOmitirRutina — "comodín" de omitir, pagado con monedas de racha
// ------------------------------------------------------------
// Chip compacto (mismo estilo visual que el contador de racha 🔥N de
// arriba) que muestra el costo en monedas de omitir HOY esta rutina
// (rutina.omisionesSeguidas + 1: sube con cada omisión consecutiva sin
// una completada real de por medio, ver toggleOmitida). Se atenúa a
// gris cuando el saldo no alcanza, pero se deja tocar igual para que
// el usuario reciba feedback claro (tooltip + SnackBar) en vez de un
// botón "muerto" sin explicación.
// ============================================================
class _BotonOmitirRutina extends ConsumerWidget {
  final Rutina rutina;
  const _BotonOmitirRutina({required this.rutina});

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
      // El área táctil gana ALTURA (no ancho): el padre (Row con stretch +
      // IntrinsicHeight en RutinaCard) le da a este InkWell la altura
      // completa de la columna título/hora/descripción (garantizada a
      // >=48dp por el ConstrainedBox de esa columna). El ancho queda
      // natural, sin forzar ningún SizedBox horizontal — eso fue lo que
      // antes causaba el RenderFlex overflow al no caber el contenido de
      // la pastilla en un ancho fijo de 48dp.
      // La tarjeta ahora es tocable para expandir/colapsar, así que este
      // InkWell propio es lo que evita que ese toque se cuele hacia el de
      // la tarjeta (gana el gesto al ser el más interno).
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () async {
            final bool exito = await ref.read(rutinaProvider.notifier).toggleOmitida(rutina.id);
            if (!exito) {
              mostrarSnackBarSimple(
                mensaje:
                    'No te alcanzan las monedas de racha para omitir "${rutina.titulo}" '
                    '(necesitas $costo, tienes $monedas).',
                colorFondo: colorOmitidaRutina,
                colorTexto: Colors.white,
              );
            }
          },
          // topCenter (no Center): la pastilla visual queda arriba, a la
          // misma altura que la racha y la primera línea del título; el
          // área táctil (todo el InkWell) sigue ocupando la columna
          // completa hacia abajo para llegar a los 48dp mínimos.
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.redo_rounded, size: 16, color: color),
                  const SizedBox(width: 3),
                  Text(
                    '$costo🪙',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}