import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/tema_provider.dart';
import '../../core/app_messenger.dart';
import 'rutina_form_screen.dart';

class GestorRutinasScreen extends ConsumerWidget {
  final Color colorTema;

  const GestorRutinasScreen({super.key, required this.colorTema});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutinas = ref.watch(rutinaProvider);
    // colorTema llega ya resuelto desde HomeScreen (temaActual.colorPrincipal),
    // pero el color de texto/ícono que va ENCIMA de ese relleno sí depende
    // del tema activo (blanco en los temas claros, tinta oscura en Medianoche).
    final colorSobreTema = ref.watch(temaProvider).colorSobrePrincipal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horario Semanal'),
        backgroundColor: colorTema,
        foregroundColor: colorSobreTema,
      ),
      body: rutinas.isEmpty
          ? const Center(child: Text('No hay rutinas configuradas'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rutinas.length,
              itemBuilder: (context, index) {
                final r = rutinas[index];
                // Aquí usamos un ListTile normal, ya que solo es para gestión, no para checklist
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(IconData(r.iconoCode, fontFamily: 'MaterialIcons'), color: colorTema),
                    title: Text(r.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      r.horarios.isEmpty
                          ? 'Sin horarios configurados'
                          : r.horarios.entries.map((e) {
                              // Mapeamos el índice del día a su nombre corto
                              final nombres = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
                              return '${nombres[e.key]} (${e.value.format(context)})';
                            }).join(' • '), // Los separamos con un punto medio
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () async {
                        // Aquí podrías agregar un diálogo de confirmación si gustas
                        await ref.read(rutinaProvider.notifier).eliminarRutina(r.id);
                        mostrarSnackBarSimple(
                          mensaje: 'Rutina eliminada',
                          colorFondo: colorTema,
                          colorTexto: colorSobreTema,
                        );
                      },
                    ),
                    onTap: () {
                      // Abre el formulario en modo "Edición"
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => RutinaFormScreen(rutinaAEditar: r),
                      ));
                    },
                  ),
                );
              },
            ),
      // Botón para crear una rutina completamente nueva
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => const RutinaFormScreen(),
          ));
        },
        backgroundColor: colorTema,
        icon: Icon(Icons.add, color: colorSobreTema),
        label: Text('Nueva Rutina', style: TextStyle(color: colorSobreTema)),
      ),
    );
  }
}