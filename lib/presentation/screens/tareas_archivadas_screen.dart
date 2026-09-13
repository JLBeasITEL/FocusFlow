import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tarea_archivada_provider.dart';
import '../../providers/tarea_provider.dart';
import '../../providers/tema_provider.dart';

// Vista de solo consulta de tareas recurrentes que agotaron su límite (ver
// TareaNotifier.toggleTarea/_archivarPorLimiteAgotado): en vez de borrarse
// sin más, viven acá — y desde acá se pueden restaurar a la lista activa
// (TareaNotifier.restaurarDesdeArchivo) si se archivaron por error, mismo
// mecanismo que el botón "Deshacer" de la tarjeta usa mientras la tarea
// sigue activa (deshacerRecurrente), pero apuntando al archivo. Entrada
// solo desde Configuraciones (menú de tres puntos), a propósito: es una
// consulta ocasional, no algo que necesite un acceso fijo en la pantalla
// principal. No incluye borrado permanente (decisión de producto aparte).
class TareasArchivadasScreen extends ConsumerWidget {
  const TareasArchivadasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivadas = ref.watch(archivoTareasProvider);
    final colorPrincipal = ref.watch(temaProvider).colorPrincipal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tareas archivadas'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorPrincipal,
      ),
      body: SafeArea(
        top: false,
        child: archivadas.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Todavía no hay tareas archivadas.\nUna tarea recurrente llega aquí cuando agota su límite de repeticiones o de fecha.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorPrincipal.withValues(alpha: 0.6), fontSize: 15, height: 1.4),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: archivadas.length,
                itemBuilder: (context, index) {
                  final tarea = archivadas[index];
                  // Siempre debería ser true para lo que hoy llega al
                  // archivo (toggleTarea/_archivarPorLimiteAgotado siempre
                  // lo fija), pero se chequea igual en vez de asumirlo: es
                  // el mismo criterio que ya usa la tarjeta activa
                  // (puedeDeshacerRecurrente) para decidir si mostrar el
                  // botón de deshacer.
                  final puedeRestaurar = tarea.fechaLimiteAnterior != null;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(Icons.inventory_2_outlined, color: colorPrincipal),
                      title: Text(tarea.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text([
                        tarea.grupo,
                        if (tarea.textoProgresoRecurrencia != null) tarea.textoProgresoRecurrencia!,
                      ].join(' · ')),
                      trailing: puedeRestaurar
                          ? TextButton.icon(
                              onPressed: () => ref.read(tareaProvider.notifier).restaurarDesdeArchivo(tarea.id),
                              icon: const Icon(Icons.undo, size: 18),
                              label: const Text('Restaurar'),
                            )
                          : null,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
