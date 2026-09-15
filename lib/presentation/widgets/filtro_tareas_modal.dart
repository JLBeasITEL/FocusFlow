import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tarea_provider.dart';
import '../../providers/tema_provider.dart';
import '../../core/colores_estado_tarea.dart';

// Mismo patrón que abrirFormularioTarea (add_tarea_modal.dart): punto de
// entrada único para no repetir showModalBottomSheet en cada call site.
void abrirFiltroTareas(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const FiltroTareasModal(),
  );
}

class FiltroTareasModal extends ConsumerWidget {
  const FiltroTareasModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroTareasProvider);
    final notifier = ref.read(filtroTareasProvider.notifier);
    final tema = ref.watch(temaProvider);
    final colorPrincipal = tema.colorPrincipal;
    final grupos = ref.read(tareaProvider.notifier).obtenerGruposExistentes();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24, right: 24, top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                const Text(
                  'Filtrar tareas',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                if (filtro.activo)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => notifier.limpiar(),
                      child: const Text('Limpiar', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            _SeccionFiltro(
              titulo: 'Estado',
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final valor in FiltroCompletado.values)
                    FilterChip(
                      label: Text(valor.label),
                      selected: filtro.completado == valor,
                      selectedColor: colorPrincipal.withValues(alpha: 0.2),
                      checkmarkColor: colorPrincipal,
                      onSelected: (_) => notifier.actualizar(filtro.copyWith(completado: valor)),
                    ),
                ],
              ),
            ),

            _SeccionFiltro(
              titulo: 'Urgencia',
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final nivel in [1, 2, 3, 4])
                    FilterChip(
                      label: Text(labelUrgenciaTarea(nivel)),
                      selected: filtro.nivelesUrgencia.contains(nivel),
                      selectedColor: colorUrgenciaTarea(nivel, tema).withValues(alpha: 0.25),
                      checkmarkColor: colorUrgenciaTarea(nivel, tema),
                      side: BorderSide(color: colorUrgenciaTarea(nivel, tema).withValues(alpha: 0.6)),
                      onSelected: (seleccionado) {
                        final nuevos = {...filtro.nivelesUrgencia};
                        if (seleccionado) {
                          nuevos.add(nivel);
                        } else {
                          nuevos.remove(nivel);
                        }
                        notifier.actualizar(filtro.copyWith(nivelesUrgencia: nuevos));
                      },
                    ),
                ],
              ),
            ),

            _SeccionFiltro(
              titulo: 'Día',
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final valor in FiltroDia.values)
                    FilterChip(
                      label: Text(valor.label),
                      selected: filtro.dia == valor,
                      selectedColor: colorPrincipal.withValues(alpha: 0.2),
                      checkmarkColor: colorPrincipal,
                      onSelected: (_) => notifier.actualizar(filtro.copyWith(dia: valor)),
                    ),
                ],
              ),
            ),

            if (grupos.isNotEmpty)
              _SeccionFiltro(
                titulo: 'Grupo',
                child: Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final grupo in grupos)
                      FilterChip(
                        label: Text(grupo),
                        selected: filtro.grupos.contains(grupo),
                        selectedColor: colorPrincipal.withValues(alpha: 0.2),
                        checkmarkColor: colorPrincipal,
                        onSelected: (seleccionado) {
                          final nuevos = {...filtro.grupos};
                          if (seleccionado) {
                            nuevos.add(grupo);
                          } else {
                            nuevos.remove(grupo);
                          }
                          notifier.actualizar(filtro.copyWith(grupos: nuevos));
                        },
                      ),
                  ],
                ),
              ),

            _SeccionFiltro(
              titulo: 'Recurrencia',
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final valor in FiltroRecurrencia.values)
                    FilterChip(
                      label: Text(valor.label),
                      selected: filtro.recurrencia == valor,
                      selectedColor: colorPrincipal.withValues(alpha: 0.2),
                      checkmarkColor: colorPrincipal,
                      onSelected: (_) => notifier.actualizar(filtro.copyWith(recurrencia: valor)),
                    ),
                ],
              ),
            ),

            _SeccionFiltro(
              titulo: 'Subtareas',
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final valor in FiltroSubtareas.values)
                    FilterChip(
                      label: Text(valor.label),
                      selected: filtro.subtareas == valor,
                      selectedColor: colorPrincipal.withValues(alpha: 0.2),
                      checkmarkColor: colorPrincipal,
                      onSelected: (_) => notifier.actualizar(filtro.copyWith(subtareas: valor)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeccionFiltro extends StatelessWidget {
  final String titulo;
  final Widget child;

  const _SeccionFiltro({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
