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

const IconData iconoGrupoPorDefecto = Icons.folder_rounded;
const IconData iconoGrupoAbiertoPorDefecto = Icons.folder_open_rounded;

// Ícono personalizado de un grupo, o null si usa el de carpeta por defecto
// (o si la clave guardada ya no existe en el catálogo).
IconData? iconoPersonalizadoDeGrupo(Map<String, String> iconos, String grupo) {
  final clave = iconos[grupo];
  return clave == null ? null : catalogoIconosGrupo[clave];
}

// Muestra el selector de ícono del grupo y guarda la elección. Devuelve
// cuando el usuario elige un ícono, restablece el por defecto o cancela.
Future<void> mostrarSelectorIconoGrupo(BuildContext context, WidgetRef ref, String grupo) async {
  final actual = ref.read(iconosGruposProvider)[grupo];
  const restablecer = '__defecto__';

  final elegido = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Ícono de "$grupo"'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final e in catalogoIconosGrupo.entries)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, e.key),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: e.key == actual ? Theme.of(ctx).colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Icon(e.value, size: 26),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, restablecer), child: const Text('Carpeta por defecto')),
      ],
    ),
  );

  if (elegido == null) return;
  await ref.read(iconosGruposProvider.notifier).establecer(grupo, elegido == restablecer ? null : elegido);
}
