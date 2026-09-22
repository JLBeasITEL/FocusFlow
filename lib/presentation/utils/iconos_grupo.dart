import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/tarea_provider.dart';

// Catálogo de íconos que se pueden asignar a una carpeta (grupo de tareas).
// Se guarda la clave (String) y no el codePoint para que los respaldos sigan
// siendo válidos aunque cambie la versión de Flutter, y para que el
// tree-shaking de íconos siga funcionando (todos son constantes Icons.*).
const Map<String, IconData> catalogoIconosGrupo = {
  'trabajo': Icons.work_rounded,
  'estudio': Icons.school_rounded,
  'libro': Icons.menu_book_rounded,
  'casa': Icons.home_rounded,
  'compras': Icons.shopping_cart_rounded,
  'dinero': Icons.attach_money_rounded,
  'salud': Icons.favorite_rounded,
  'deporte': Icons.fitness_center_rounded,
  'comida': Icons.restaurant_rounded,
  'viaje': Icons.flight_rounded,
  'auto': Icons.directions_car_rounded,
  'familia': Icons.family_restroom_rounded,
  'amigos': Icons.groups_rounded,
  'mascota': Icons.pets_rounded,
  'musica': Icons.music_note_rounded,
  'juegos': Icons.sports_esports_rounded,
  'codigo': Icons.code_rounded,
  'idea': Icons.lightbulb_rounded,
  'estrella': Icons.star_rounded,
  'importante': Icons.priority_high_rounded,
  'reunion': Icons.event_rounded,
  'llamada': Icons.call_rounded,
  'correo': Icons.mail_rounded,
  'herramientas': Icons.build_rounded,
  'jardin': Icons.local_florist_rounded,
  'arte': Icons.palette_rounded,
  'foto': Icons.photo_camera_rounded,
  'tecnologia': Icons.devices_rounded,
  'meta': Icons.flag_rounded,
  'personal': Icons.person_rounded,
};

// Emojis de acceso rápido, además del teclado de emojis del sistema (ver
// _SelectorIconoGrupoSheet, que también acepta cualquier emoji escrito a
// mano). Son solo una selección corta para no abrumar la hoja.
const List<String> emojisRapidosGrupo = [
  '📌', '⭐', '🔥', '💡', '📚', '💼', '🏠', '🛒', '💰', '❤️',
  '🏋️', '🍽️', '✈️', '🚗', '👨‍👩‍👧', '🐾', '🎵', '🎮', '🎨', '📷',
];

const IconData iconoGrupoPorDefecto = Icons.folder_rounded;
const IconData iconoGrupoAbiertoPorDefecto = Icons.folder_open_rounded;

// Prefijo que distingue un emoji guardado como ícono de grupo de una clave
// del catálogo de Material Icons de arriba (ver establecer()/_guardar() en
// IconosGruposNotifier, que guardan este String tal cual).
const String _prefijoEmoji = 'emoji:';

// Representa el ícono elegido para un grupo: un IconData del catálogo O un
// emoji suelto, nunca ambos. Sealed a mano (sin paquete `sealed`) porque solo
// necesita estos dos casos y un exhaustive-check simple con los getters.
class IconoGrupoElegido {
  final IconData? icono;
  final String? emoji;
  const IconoGrupoElegido.icono(IconData this.icono) : emoji = null;
  const IconoGrupoElegido.emoji(String this.emoji) : icono = null;
}

// Ícono personalizado de un grupo, o null si usa el de carpeta por defecto
// (o si la clave guardada ya no existe en el catálogo, p. ej. un respaldo
// viejo de otra versión de la app).
IconoGrupoElegido? iconoPersonalizadoDeGrupo(Map<String, String> iconos, String grupo) {
  final clave = iconos[grupo];
  if (clave == null) return null;
  if (clave.startsWith(_prefijoEmoji)) {
    final emoji = clave.substring(_prefijoEmoji.length);
    return emoji.isEmpty ? null : IconoGrupoElegido.emoji(emoji);
  }
  final icono = catalogoIconosGrupo[clave];
  return icono == null ? null : IconoGrupoElegido.icono(icono);
}

// Dibuja el ícono de un grupo (personalizado o el de carpeta por defecto),
// como ícono de Material o como emoji según lo que el usuario haya elegido.
// Un solo punto de dibujo para los 4 lugares que muestran el ícono de una
// carpeta (cabecera, arrastre, vista horizontal, "Editar grupos"), así que
// agregar un nuevo tipo de ícono personalizado (como los emojis) solo
// requiere tocar esta función.
Widget iconoWidgetDeGrupo(
  Map<String, String> iconos,
  String grupo, {
  required double size,
  required Color color,
  IconData iconoPorDefecto = iconoGrupoPorDefecto,
}) {
  final elegido = iconoPersonalizadoDeGrupo(iconos, grupo);
  if (elegido?.emoji != null) {
    // El emoji trae su propio color; se dibuja más grande que un IconData
    // equivalente (los glifos de emoji tienen bastante margen interno) para
    // que se vea del mismo tamaño visual que los íconos de al lado.
    return Text(elegido!.emoji!, style: TextStyle(fontSize: size * 1.15, height: 1));
  }
  return Icon(elegido?.icono ?? iconoPorDefecto, size: size, color: color);
}

// Muestra el selector de ícono del grupo (catálogo de Material Icons +
// emojis) y guarda la elección. Devuelve cuando el usuario elige algo,
// restablece el por defecto o cancela.
Future<void> mostrarSelectorIconoGrupo(BuildContext context, WidgetRef ref, String grupo) async {
  final actual = ref.read(iconosGruposProvider)[grupo];
  const restablecer = '__defecto__';

  final elegido = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SelectorIconoGrupoSheet(grupo: grupo, actual: actual, restablecer: restablecer),
  );

  if (elegido == null) return;
  await ref.read(iconosGruposProvider.notifier).establecer(grupo, elegido == restablecer ? null : elegido);
}

class _SelectorIconoGrupoSheet extends StatefulWidget {
  final String grupo;
  final String? actual;
  final String restablecer;
  const _SelectorIconoGrupoSheet({required this.grupo, required this.actual, required this.restablecer});

  @override
  State<_SelectorIconoGrupoSheet> createState() => _SelectorIconoGrupoSheetState();
}

class _SelectorIconoGrupoSheetState extends State<_SelectorIconoGrupoSheet> {
  // Campo para escribir/pegar CUALQUIER emoji (usando el propio teclado de
  // emojis del sistema operativo), no solo los de acceso rápido de abajo.
  late final TextEditingController _emojiController =
      TextEditingController(text: widget.actual?.startsWith(_prefijoEmoji) == true ? widget.actual!.substring(_prefijoEmoji.length) : '');

  @override
  void dispose() {
    _emojiController.dispose();
    super.dispose();
  }

  void _elegirEmoji(String emoji) {
    final limpio = emoji.trim();
    if (limpio.isEmpty) return;
    Navigator.pop(context, '$_prefijoEmoji$limpio');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ícono de "${widget.grupo}"', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // Cualquier emoji: pega uno o abre el teclado de emojis del
              // sistema tocando el campo (en el teclado de Android/iOS hay
              // un botón para cambiar a emojis).
              Text('Emoji', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _emojiController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28),
                      maxLength: 4, // margen para emojis compuestos (banderas, piel, familias)
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: '🙂',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _elegirEmoji(_emojiController.text),
                    child: const Text('Usar'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final emoji in emojisRapidosGrupo)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _elegirEmoji(emoji),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),
              Text('Íconos', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final e in catalogoIconosGrupo.entries)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, e.key),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: e.key == widget.actual ? Theme.of(context).colorScheme.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Icon(e.value, size: 26),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, widget.restablecer),
                  child: const Text('Carpeta por defecto'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
