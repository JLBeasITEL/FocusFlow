import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tarea_archivada_provider.dart';
import '../../providers/tarea_provider.dart';
import '../../providers/tema_provider.dart';

// Vista de solo consulta de CUALQUIER tarea que desapareció de la lista
// principal al completarse (ver la limpieza diaria en
// TareaNotifier._cargarTareasInterno): una tarea normal completada, o una
// recurrente que agotó su límite (ver TareaNotifier._completarUltimaOcurrencia/
// archivarDirectamente). En vez de borrarse sin más, viven acá — y desde acá
// se pueden restaurar a la lista activa (TareaNotifier.restaurarDesdeArchivo)
// si se completaron/archivaron por error. Entrada solo desde Configuraciones
// (menú de tres puntos), a propósito: es una consulta ocasional, no algo que
// necesite un acceso fijo en la pantalla principal. No incluye borrado
// permanente (decisión de producto aparte).
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
                    'Todavía no hay tareas archivadas.\nUna tarea llega aquí cuando se completa y desaparece de la lista principal.',
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
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(Icons.inventory_2_outlined, color: colorPrincipal),
                      title: Text(tarea.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text([
                        tarea.grupo,
                        if (tarea.textoProgresoRecurrencia != null) tarea.textoProgresoRecurrencia!,
                      ].join(' · ')),
                      // Restaurar siempre disponible: TareaNotifier.restaurarDesdeArchivo
                      // sabe reconstruir tanto una recurrente (fecha/contador
                      // de vuelta a como estaban) como una tarea normal (solo
                      // desmarcarla), así que no hace falta distinguir acá.
                      trailing: TextButton.icon(
                        onPressed: () => ref.read(tareaProvider.notifier).restaurarDesdeArchivo(tarea.id),
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('Restaurar'),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
