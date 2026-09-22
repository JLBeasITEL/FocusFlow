import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_messenger.dart';
import '../../models/rutina.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/tema_provider.dart';

// Hoja inferior para cambiar la hora de las rutinas de HOY sin entrar al
// formulario completo de cada una. El cambio se aplica al día de la semana
// de hoy (horarios[hoy]), o sea que también vale para los mismos días de las
// semanas siguientes; los demás días de la rutina no se tocan. Guarda con
// editarRutina, que ya cancela y reprograma las notificaciones de la rutina.
Future<void> mostrarHorarioDeHoy(BuildContext context, Color colorTema) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HorarioHoySheet(colorTema: colorTema),
  );
}

class _HorarioHoySheet extends ConsumerWidget {
  final Color colorTema;
  const _HorarioHoySheet({required this.colorTema});

  Future<void> _cambiarHora(BuildContext context, WidgetRef ref, Rutina rutina, int diaHoy) async {
    final actual = rutina.horarios[diaHoy]!;
    final nueva = await showTimePicker(context: context, initialTime: actual);
    if (nueva == null || nueva == actual) return;

    await ref.read(rutinaProvider.notifier).editarRutina(
          rutina.copyWith(horarios: {...rutina.horarios, diaHoy: nueva}),
        );
    if (!context.mounted) return;
    final tema = ref.read(temaProvider);
    mostrarSnackBarSimple(
      mensaje: 'Horario de "${rutina.titulo}" actualizado',
      colorFondo: colorTema,
      colorTexto: tema.colorSobrePrincipal,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int diaHoy = DateTime.now().weekday - 1;
    final rutinasDeHoy = ref.watch(rutinaProvider).where((r) => r.activa && r.horarios.containsKey(diaHoy)).toList()
      ..sort((a, b) {
        final ha = a.horarios[diaHoy]!;
        final hb = b.horarios[diaHoy]!;
        return (ha.hour * 60 + ha.minute).compareTo(hb.hour * 60 + hb.minute);
      });

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Horario de hoy (${DateFormat('EEEE', 'es_ES').format(DateTime.now())})',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorTema),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Toca una rutina para cambiar su hora. El cambio aplica a todos los ${DateFormat('EEEE', 'es_ES').format(DateTime.now())} de esa rutina.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
            Flexible(
              child: rutinasDeHoy.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No hay rutinas programadas para hoy.')),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: rutinasDeHoy.length,
                      itemBuilder: (context, i) {
                        final r = rutinasDeHoy[i];
                        return ListTile(
                          leading: Icon(IconData(r.iconoCode, fontFamily: 'MaterialIcons'), color: colorTema),
                          title: Text(r.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(r.horarios[diaHoy]!.format(context), style: TextStyle(fontWeight: FontWeight.w600, color: colorTema)),
                              const SizedBox(width: 8),
                              Icon(Icons.schedule_rounded, size: 20, color: colorTema),
                            ],
                          ),
                          onTap: () => _cambiarHora(context, ref, r, diaHoy),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
