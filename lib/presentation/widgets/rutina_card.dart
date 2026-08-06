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

// ConsumerWidget: es un widget "sin estado propio" (stateless) pero que SÍ puede
// leer/escuchar el provider de Riverpod a través del parámetro `ref`.
class RutinaCard extends ConsumerWidget {
  // Datos que este widget recibe desde afuera (desde la lista que lo construye).
  final Rutina rutina;     // La rutina específica que esta tarjeta va a mostrar
  final Color colorTema;   // Color del tema visual de esta rutina (para íconos, texto, etc.)

  // Constructor: ambos parámetros son obligatorios (required).
  const RutinaCard({super.key, required this.rutina, required this.colorTema});

  @override
  // build() se ejecuta cada vez que este widget necesita dibujarse o redibujarse.
  // `context` da acceso al árbol de widgets; `ref` da acceso al estado de Riverpod.
  Widget build(BuildContext context, WidgetRef ref) {

    // Variable local: ¿esta rutina está activa (encendida) o desactivada por el usuario?
    final bool activa = rutina.activa;

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

      child: Padding(
        // Relleno interno de la tarjeta (espacio entre el borde y el contenido).
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),

        // Row: acomoda todo el contenido en una sola fila horizontal.
        child: Row(
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
                : (bool? valor) async {

                  // PASO 1: Cambiamos el estado de "completada" en el provider,
                  // y ESPERAMOS (await) a que termine todo el proceso interno:
                  // - Actualizar el estado en memoria
                  // - Guardar en SharedPreferences
                  // - Cancelar las notificaciones/alarmas viejas
                  // - Reprogramar las nuevas (si aplica)
                  // Gracias al await, este código no continúa hasta que TODO eso termine.
                  await ref.read(rutinaProvider.notifier).toggleCompletada(rutina.id);

                  // El await anterior puede tardar (guardado, notificaciones); si el
                  // usuario ya salió de la pantalla, el context ya no es válido para UI.
                  if (!context.mounted) return;

                  // PASO 2: Solo si el usuario ACABA de marcarla como completada
                  // (no si la está desmarcando), revisamos si merece festejo por racha.
                  if (valor == true) {

                    // Calculamos cuál sería la nueva racha (sumando 1 a la actual).
                    // Nota: usamos "rutina.racha" (el valor ANTES del toggle) porque
                    // este widget todavía no se ha reconstruido con el nuevo valor.
                    final nuevaRacha = rutina.racha + 1;

                    // PASO 3: Verificamos si la nueva racha completa un nuevo múltiplo
                    // de rachaPorMoneda (7, 14, 21, 28... sin tope, se repite cada vez
                    // que la racha vuelve a cruzar un múltiplo). Es EXACTAMENTE el
                    // mismo hito, fijo para TODAS las rutinas sin importar cuántos
                    // días/semana tengan programados, que usa toggleCompletada en
                    // rutina_provider.dart para otorgar la moneda real — este chequeo
                    // acá solo decide cuándo MOSTRAR el diálogo, la moneda en sí ya se
                    // otorgó en el provider antes de que este código se ejecute.
                    if (nuevaRacha % rachaPorMoneda == 0) {

                      // PASO 4: Texto de felicitación. Ya no distingue por días/semana
                      // (con el hito fijo en 7, la racha no corresponde 1 a 1 con
                      // semanas de calendario para rutinas de pocos días/semana), así
                      // que es el mismo mensaje para cualquier frecuencia.
                      final String textoFelicidades =
                          '¡Felicidades! Llevas $nuevaRacha veces seguidas sin fallar con este hábito.\n'
                          '+1 moneda de racha 🪙';

                      // PASO 5: Mostramos un diálogo emergente de felicitación.
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          // Bordes redondeados del diálogo.
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          content: Column(
                            // El tamaño de la columna se ajusta al contenido (no ocupa toda la pantalla).
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Emoji grande de fuego como ícono central.
                              const Text('🔥', style: TextStyle(fontSize: 72)),
                              const SizedBox(height: 16),

                              // Título del diálogo.
                              const Text(
                                '¡Racha Cumplida!',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),

                              // Texto dinámico de felicitación (el que armamos en el paso 4).
                              Text(
                                textoFelicidades,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade700, height: 1.4),
                              ),
                              const SizedBox(height: 24),

                              // Botón para cerrar el diálogo.
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  minimumSize: const Size(double.infinity, 50), // Ocupa todo el ancho disponible
                                ),
                                // Al presionar, cierra el diálogo (pop = quitar de la pila de navegación).
                                onPressed: () => Navigator.pop(context),
                                child: const Text(
                                  '¡A seguir así!',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  }
                },
            ),

            // Contenedor circular que envuelve el ícono de la rutina.
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
            const SizedBox(width: 12), // Separación horizontal antes del texto

            // ================================================================
            // 2. ZONA CENTRAL: Título de la rutina y hora programada para hoy
            // ================================================================
            Expanded(
              // Expanded hace que esta columna ocupe todo el espacio horizontal
              // sobrante entre el ícono (izquierda) y la racha (derecha).
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // Alinea el texto a la izquierda
                children: [
                  // Título de la rutina.
                  Text(
                    rutina.titulo,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      // Si ya está completada, le pone una línea tachada encima del texto.
                      decoration: rutina.completada ? TextDecoration.lineThrough : null,
                      // Color del texto: ámbar si se omitió hoy, negro si activa, gris si desactivada.
                      color: omitida ? colorOmitidaRutina : (activa ? Colors.black87 : Colors.grey),
                    ),
                    maxLines: 1,                       // Nunca ocupa más de una línea
                    overflow: TextOverflow.ellipsis,   // Si no cabe, corta con "..."
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
                ],
              ),
            ),

            // ================================================================
            // 3. ZONA DERECHA: Contador de racha (solo si está activa y racha > 0)
            // ================================================================
            if (activa && rutina.racha > 0) ...[
              // El operador ...[ ] ("spread") inserta estos widgets directamente
              // en la lista children, solo si la condición del "if" es verdadera.
              const SizedBox(width: 4),
              const Text('🔥', style: TextStyle(fontSize: 14)), // Emoji de fuego
              const SizedBox(width: 2),
              Text(
                '${rutina.racha}', // Número de racha actual
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16),
              ),
              const SizedBox(width: 12),
            ],

            // ================================================================
            // 4. Botón "Omitir por hoy": solo tiene sentido si todavía está
            // pendiente (ni completada ni ya omitida) y la rutina está activa.
            // ================================================================
            if (activa && !rutina.completada && !omitida) _BotonOmitirRutina(rutina: rutina),
          ],
        ),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
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
        child: Container(
          margin: const EdgeInsets.only(left: 4),
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
    );
  }
}