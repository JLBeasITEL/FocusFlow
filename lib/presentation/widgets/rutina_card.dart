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
import '../../core/temporizador_rutina_dialogo.dart';

// ConsumerWidget: es un widget "sin estado propio" (stateless) pero que SÍ puede
// leer/escuchar el provider de Riverpod a través del parámetro `ref`.
class RutinaCard extends ConsumerWidget {
  // Alto mínimo de la fila inferior: es la zona táctil recomendada del botón
  // de omitir (_BotonOmitirRutina), NO un alto "de la fila" en general. Solo
  // debe aplicarse cuando ese botón realmente va a dibujarse (hayBotonOmitir)
  // — si se aplicara siempre, una fila que solo muestra la racha (o "Omitida
  // hoy") queda con espacio muerto de sobra por encima y por debajo, ya que
  // ninguno de los dos necesita 48dp para verse bien.
  static const double _alturaTactilBotonOmitir = 48;

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

    // Cambio de UI independiente del temporizador: la hora de hoy deja de
    // tener sentido una vez que la ocurrencia de hoy ya se resolvió.
    // "Omitida hoy" se mantiene (es su propia etiqueta de estado, no la
    // hora); al completar sin omitir no queda ninguna etiqueta — el
    // checkbox marcado y el título tachado ya comunican el estado, así que
    // no hace falta repetirlo con texto.
    final bool ocultarHora = rutina.completada && !omitida;
    final bool hayRacha = activa && rutina.racha > 0;
    final bool hayBotonOmitir = activa && !rutina.completada && !omitida;
    // Si no queda hora, ni racha, ni botón de omitir, la fila entera no
    // tiene nada que mostrar: se colapsa por completo (sin el minHeight de
    // 48 fijo) en vez de dejar una franja vacía del alto de la zona táctil
    // del botón de omitir.
    final bool filaInferiorVacia = ocultarHora && !hayRacha && !hayBotonOmitir;

    // Modo compacto: una vez que la ocurrencia de hoy ya se resolvió
    // (completada U omitida), no hay botón de omitir en ningún caso
    // (hayBotonOmitir ya lo excluye para ambas) — ni la racha ni "Omitida
    // hoy" necesitan una fila propia con zona táctil, así que se fusionan
    // con el título en una sola línea en vez de reservar una fila inferior
    // completa. Aplica a los dos estados por igual (no solo completada) para
    // que el criterio sea consistente: que unas tarjetas colapsen y otras no
    // según el estado se vería arbitrario.
    final bool modoCompacto = rutina.completada || omitida;

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
          // crossAxisAlignment center: el checkbox/botón de deshacer y el
          // círculo del ícono quedan centrados verticalmente respecto a la
          // altura TOTAL del bloque de la derecha (título + descripción +
          // fila inferior), no anclados a su primera línea. Como el Row se
          // relayoutea en cada frame en que AnimatedSize cambia la altura
          // de ese bloque, el centrado se recalcula solo y se mantiene
          // correcto también durante la animación de expandir/colapsar.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
                  : (bool? valor) => manejarToqueCheckboxRutina(
                      context: context,
                      ref: ref,
                      rutina: rutina,
                      valor: valor,
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
              // 2. ZONA CENTRAL: dos layouts posibles según el estado.
              // Normal (rutina pendiente): título en su propia línea, luego
              // descripción, luego la fila inferior de hora/racha/omitir.
              // Compacto (completada u omitida, ver modoCompacto arriba):
              // título y racha (u "Omitida hoy") comparten una sola línea —
              // ver _construirContenidoCompacto para el porqué.
              // ================================================================
              Expanded(
                child: modoCompacto
                    ? _construirContenidoCompacto(
                        omitida: omitida,
                        activa: activa,
                        tieneDescripcion: tieneDescripcion,
                        esExpandida: esExpandida,
                        hayRacha: hayRacha,
                      )
                    : _construirContenidoNormal(
                        context: context,
                        omitida: omitida,
                        activa: activa,
                        colorFuerte: colorFuerte,
                        tieneDescripcion: tieneDescripcion,
                        esExpandida: esExpandida,
                        hayRacha: hayRacha,
                        hayBotonOmitir: hayBotonOmitir,
                        ocultarHora: ocultarHora,
                        filaInferiorVacia: filaInferiorVacia,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // _construirContenidoNormal — rutina pendiente (ni completada ni omitida).
  // Título en su propia línea, descripción opcional, y la fila inferior de
  // siempre (hora — racha — botón de omitir). Extraído tal cual estaba
  // antes de introducir el modo compacto: comportamiento sin cambios para
  // este caso, incluidos los caminos de ocultarHora/filaInferiorVacia que
  // en la práctica ya no se alcanzan acá (solo aplicaban a completada/
  // omitida, que ahora van siempre por _construirContenidoCompacto) — se
  // conservan para no alterar nada de este método por fuera de la
  // bifurcación en sí.
  // ============================================================
  Widget _construirContenidoNormal({
    required BuildContext context,
    required bool omitida,
    required bool activa,
    required Color colorFuerte,
    required bool tieneDescripcion,
    required bool esExpandida,
    required bool hayRacha,
    required bool hayBotonOmitir,
    required bool ocultarHora,
    required bool filaInferiorVacia,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Alinea el texto a la izquierda
      children: [
        // Título: ya no comparte fila con nada, ocupa todo el
        // ancho disponible hasta el borde derecho de la tarjeta.
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
          // Colapsada: hasta 2 líneas con "...". Expandida: sin límite.
          maxLines: esExpandida ? null : 2,
          overflow: esExpandida ? TextOverflow.visible : TextOverflow.ellipsis,
        ),

        // Descripción opcional: va ENTRE el título y la hora, solo
        // visible con la tarjeta expandida. AnimatedSize hace que
        // la tarjeta crezca/encoja con una transición suave en vez
        // de un salto brusco (mismo patrón de TareaCard: 300ms,
        // easeInOut).
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
        // ========================================================
        // Separador + fila inferior: hora (izquierda) — racha y
        // botón de omitir (derecha). El SizedBox(height: 8) va
        // JUNTO con la fila (no suelto antes): si filaInferiorVacia
        // no queda nada que mostrar abajo, y dejar ese separador
        // suelto sumaría una "cola" invisible al bloque de texto,
        // corriendo el título hacia arriba respecto al centro real
        // de la tarjeta (ver CrossAxisAlignment.center del Row
        // exterior: centra el checkbox/ícono contra la altura TOTAL
        // de este bloque, cola incluida). Sin la fila, se omiten
        // ambos widgets por completo — no solo se colapsa a
        // SizedBox.shrink — para que el bloque restante (aquí,
        // el título solo) sea lo único que el Row exterior centra.
        // ConstrainedBox(minHeight: _alturaTactilBotonOmitir) +
        // IntrinsicHeight + stretch: le da al botón de omitir una
        // zona táctil de ese alto mínimo (creciendo hacia
        // arriba/abajo del contenido, no hacia los lados) sin
        // ensanchar su pastilla visual ni forzar esa misma altura
        // en el resto de la tarjeta — es la misma técnica que ya
        // se usó para corregir el RenderFlex overflow anterior.
        // El mínimo solo se aplica si el botón de omitir
        // realmente va a mostrarse (hayBotonOmitir): sin él (rutina
        // completada u omitida), la fila —con solo la racha o la
        // etiqueta de estado— se dimensiona a su contenido real,
        // sin la zona táctil de más que nadie necesita ahí.
        // ========================================================
        if (!filaInferiorVacia) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: hayBotonOmitir ? _alturaTactilBotonOmitir : 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hora programada para HOY, la etiqueta de estado
                  // "Omitida" si se pagó con monedas para saltarla
                  // (igual que el widget de pantalla de inicio), o
                  // nada si ya se completó sin omitir (el checkbox
                  // marcado y el título tachado ya lo comunican).
                  // Flexible (no un ancho fijo): en tarjetas angostas
                  // con racha de 2+ dígitos y pastilla de omitir a la
                  // vez, la hora cede ancho (con ellipsis) en vez de
                  // desbordar la fila — racha y omitir nunca se
                  // recortan, solo la hora si hace falta.
                  Flexible(
                    child: Center(
                      child: ocultarHora
                          ? const SizedBox.shrink()
                          : Text(
                              omitida
                                  ? 'Omitida hoy'
                                  : (rutina.horarios[DateTime.now().weekday - 1]?.format(context) ?? '--:--'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: omitida ? colorOmitidaRutina : colorFuerte,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  // Empuja racha y botón de omitir al extremo derecho,
                  // dejando a la hora pegada al borde izquierdo.
                  const Spacer(),
                  if (hayRacha) ...[
                    Center(child: _RachaTexto(racha: rutina.racha)),
                    // Separación con el botón de omitir: evita toques
                    // accidentales ahora que comparten la misma fila.
                    const SizedBox(width: 16),
                  ],
                  // Botón "Omitir por hoy": solo tiene sentido si
                  // todavía está pendiente (ni completada ni ya
                  // omitida) y la rutina está activa.
                  if (hayBotonOmitir) _BotonOmitirRutina(rutina: rutina),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // _construirContenidoCompacto — rutina completada U omitida.
  // ------------------------------------------------------------
  // Una vez que la ocurrencia de hoy ya se resolvió, no hay botón de omitir
  // en ningún caso (hayBotonOmitir ya lo excluye para completada Y
  // omitida) — ni la racha ni la etiqueta "Omitida hoy" necesitan zona
  // táctil propia, así que en vez de reservar una fila inferior completa
  // se fusionan con el título en una sola línea: título a la izquierda
  // (Expanded, admite varias líneas igual que en modo normal — un Row con
  // Expanded no obliga a truncar a una sola línea, la fila simplemente
  // crece con el texto), "Omitida hoy" y/o la racha a la derecha. La
  // tarjeta queda notablemente más baja al no reservar esa fila aparte.
  // Aplica a los dos estados por igual (no solo completada): un criterio
  // que colapsara unas tarjetas sí y otras no según el estado se vería
  // arbitrario, y el color ámbar + el ícono de deshacer ya distinguen
  // "omitida" de "completada" sin necesitar además una fila propia.
  // La descripción expandible, que en modo normal vive ENTRE el título y
  // la fila inferior, pasa a vivir DEBAJO de esta línea combinada — ya no
  // hay un "entre" posible una vez que título y racha comparten renglón.
  // ============================================================
  Widget _construirContenidoCompacto({
    required bool omitida,
    required bool activa,
    required bool tieneDescripcion,
    required bool esExpandida,
    required bool hayRacha,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                rutina.titulo,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  decoration: rutina.completada ? TextDecoration.lineThrough : null,
                  color: omitida ? colorOmitidaRutina : (activa ? Colors.black87 : Colors.grey),
                ),
                // Mismo criterio que en modo normal: hasta 2 líneas
                // colapsada, sin límite si la tarjeta está expandida.
                maxLines: esExpandida ? null : 2,
                overflow: esExpandida ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            if (omitida) ...[
              const SizedBox(width: 12),
              Text(
                'Omitida hoy',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: colorOmitidaRutina, fontWeight: FontWeight.w600),
              ),
            ],
            if (hayRacha) ...[
              const SizedBox(width: 12),
              _RachaTexto(racha: rutina.racha),
            ],
          ],
        ),
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
    );
  }
}

// ============================================================
// _RachaTexto — contador de racha (🔥N), solo informativo.
// ------------------------------------------------------------
// A propósito NO lleva pastilla/fondo ni InkWell: es texto suelto sobre
// el blanco de la tarjeta, para que no se confunda con el botón de
// omitir (que sí es tocable) al compartir ahora la misma fila inferior.
// ============================================================
class _RachaTexto extends StatelessWidget {
  final int racha;
  const _RachaTexto({required this.racha});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🔥', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 3),
        Text(
          '$racha',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14),
        ),
      ],
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
      // El área táctil gana ALTURA (no ancho): el padre (fila inferior con
      // ConstrainedBox(minHeight: 48) + IntrinsicHeight + stretch en
      // RutinaCard) le da a este InkWell al menos 48dp de alto. El ancho
      // queda natural, sin forzar ningún SizedBox horizontal — eso fue lo
      // que antes causaba el RenderFlex overflow al no caber el contenido
      // de la pastilla en un ancho fijo de 48dp.
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
          // La pastilla visual queda centrada en la fila inferior (hora /
          // racha / omitir comparten esa línea); el área táctil (todo el
          // InkWell) sigue ocupando el alto completo de la fila.
          child: Center(
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