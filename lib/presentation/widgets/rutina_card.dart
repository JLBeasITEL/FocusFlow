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
import '../../models/rutina.dart';             // El modelo de datos "Rutina"

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
            // 1. ZONA IZQUIERDA: Checkbox (marcar como completada) + ícono
            // ================================================================
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

                    // ¿En cuántos días de la semana está programada esta rutina?
                    final diasPorSemana = rutina.horarios.length;

                    // Si por alguna razón no tiene días asignados, no seguimos (evita división por cero).
                    if (diasPorSemana == 0) return;

                    // PASO 3: Verificamos si la nueva racha completa un "ciclo semanal" exacto.
                    // Ejemplo: si la rutina es de 3 días a la semana, cada 3 completadas = 1 semana cumplida.
                    //
                    // Caso especial: si la rutina es de 1 solo día a la semana, "nuevaRacha % 1"
                    // siempre da 0, así que sin este mínimo el festejo se dispararía desde la
                    // PRIMERA vez que se marca (nuevaRacha == 1), cuando en realidad eso es
                    // apenas 1 marca, no una racha sostenida. Exigimos al menos 2 completadas
                    // (2 semanas) antes del primer festejo, igual que ocurre de forma natural
                    // con las rutinas de 2+ días a la semana.
                    final minimoParaFestejar = diasPorSemana == 1 ? 2 : diasPorSemana;

                    if (nuevaRacha >= minimoParaFestejar && nuevaRacha % diasPorSemana == 0) {

                      // Calculamos cuántas semanas completas representa esta racha.
                      final semanas = nuevaRacha ~/ diasPorSemana; // división entera

                      // PASO 4: Armamos el texto de felicitación según el tipo de hábito.
                      String textoFelicidades;
                      if (diasPorSemana >= 5) {
                        // Si es un hábito de 5, 6 o 7 días por semana, celebramos por DÍAS seguidos.
                        textoFelicidades =
                            '¡Felicidades! Has mantenido este hábito impecable durante $nuevaRacha días seguidos.';
                      } else {
                        // Si es un hábito de menos de 5 días por semana, celebramos por SEMANAS.
                        final pluralSemanas = semanas == 1
                            ? '1 semana consecutiva'
                            : '$semanas semanas consecutivas';
                        textoFelicidades =
                            '¡Felicidades! Has mantenido este hábito impecable durante $pluralSemanas.';
                      }

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
                      // Color del texto: negro si activa, gris si desactivada.
                      color: activa ? Colors.black87 : Colors.grey,
                    ),
                    maxLines: 1,                       // Nunca ocupa más de una línea
                    overflow: TextOverflow.ellipsis,   // Si no cabe, corta con "..."
                  ),
                  const SizedBox(height: 4),

                  // Hora programada para HOY específicamente.
                  // rutina.horarios es un Map<int, TimeOfDay> donde la llave es el día de la semana (0=Lunes).
                  // DateTime.now().weekday devuelve 1=Lunes...7=Domingo, por eso se resta 1.
                  Text(
                    rutina.horarios[DateTime.now().weekday - 1]?.format(context) ?? '--:--',
                    style: TextStyle(fontSize: 14, color: colorFuerte, fontWeight: FontWeight.w600),
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
          ],
        ),
      ),
    );
  }
}