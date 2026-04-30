import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/rutina.dart';
import '../../providers/rutina_provider.dart';

class AddRutinaModal extends ConsumerStatefulWidget {
  const AddRutinaModal({Key? key}) : super(key: key);

  @override
  ConsumerState<AddRutinaModal> createState() => _AddRutinaModalState();
}

class _AddRutinaModalState extends ConsumerState<AddRutinaModal> {
  final _tituloController = TextEditingController();
  TimeOfDay _horaSeleccionada = TimeOfDay.now();
  final List<bool> _diasSeleccionados = [false, false, false, false, false, false, false];
  int _iconoSeleccionado = Icons.fitness_center.codePoint;

  final List<IconData> _opcionesIconos = [
    // Salud y Medicina
    Icons.medication,           // Pastillas / Suplementos / Vitaminas
    Icons.medical_services,     // Citas médicas / Chequeos
    Icons.monitor_heart,        // Salud cardiovascular
    Icons.water_drop,           // Tomar agua
    
    // Ejercicio y Bienestar
    Icons.fitness_center,       // Rutinas de gimnasio / Fuerza
    Icons.directions_run,       // Cardio / Correr
    Icons.self_improvement,     // Meditación / Yoga / Estiramientos
    Icons.nightlight_round,     // Rutina de sueño / Dormir temprano

    // Productividad y Conocimiento
    Icons.code,                 // Programar / Desarrollar
    Icons.computer,             // Trabajo general en PC
    Icons.menu_book,            // Lectura / Estudio de la universidad
    Icons.science,              // Química / Ciencias / Investigación
    
    // Hobbies y Entretenimiento
    Icons.piano,                // Práctica de instrumentos / Teoría musical
    Icons.videogame_asset,      // Sesión de videojuegos / Speedruns
    Icons.headphones,           // Escuchar música / Podcasts
    
    // Hogar y Vida Diaria
    Icons.cleaning_services,    // Limpieza de la casa / Cuarto
    Icons.local_laundry_service,// Día de lavado
    Icons.shopping_cart,        // Supermercado / Compras
    Icons.pets,                 // Alimentar / Pasear mascota

    // Nutrición y Suplementos
    Icons.blender,              // Preparar batidos / Licuados
    
    // Proyectos y Electrónica
    Icons.memory,               // Hardware / Ensamble de PC / Soldadura
    
    // Transporte y Vehículo
    Icons.directions_car,       // Trayectos / Mantenimiento del auto
    
    // Finanzas
    Icons.account_balance_wallet, // Revisar gastos / Presupuesto
    
    // Social
    Icons.diversity_3,          // Tiempo con familia o amigos
  ];
  

  void _seleccionarHora() async {
    final TimeOfDay? seleccion = await showTimePicker(
      context: context,
      initialTime: _horaSeleccionada,
    );
    if (seleccion != null) {
      setState(() => _horaSeleccionada = seleccion);
    }
  }

  void _guardarRutina() {
    if (_tituloController.text.trim().isEmpty) return;
    if (!_diasSeleccionados.contains(true)) return; // Debe elegir al menos un día

    final nuevaRutina = Rutina(
      id: const Uuid().v4(),
      titulo: _tituloController.text.trim(),
      horaDian: _horaSeleccionada,
      diasSemana: _diasSeleccionados,
      iconoCode: _iconoSeleccionado,
    );

    ref.read(rutinaProvider.notifier).addRutina(nuevaRutina);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nueva Rutina', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // Título
            TextField(
              controller: _tituloController,
              decoration: InputDecoration(
                labelText: '¿Qué hábito quieres construir?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                prefixIcon: const Icon(Icons.repeat),
              ),
            ),
            const SizedBox(height: 20),

            // Selector de Hora
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hora de la alarma', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: ElevatedButton.icon(
                onPressed: _seleccionarHora,
                icon: const Icon(Icons.access_time),
                label: Text(_horaSeleccionada.format(context)),
              ),
            ),
            const SizedBox(height: 10),

            // Selector de Días
            const Text('Días de la semana', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['L', 'M', 'M', 'J', 'V', 'S', 'D'].asMap().entries.map((entry) {
                int idx = entry.key;
                bool activo = _diasSeleccionados[idx];
                return GestureDetector(
                  onTap: () => setState(() => _diasSeleccionados[idx] = !activo),
                  child: CircleAvatar(
                    backgroundColor: activo ? Colors.deepPurple : Colors.grey.shade300,
                    foregroundColor: activo ? Colors.white : Colors.black87,
                    child: Text(entry.value),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Selector de Ícono Discreto (ExpansionTile)
            Theme(
              // Este Theme quita las líneas divisoras que Flutter le pone por defecto al expandirse
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                // Muestra el ícono que está actualmente seleccionado
                leading: CircleAvatar(
                  backgroundColor: Colors.deepPurple.withOpacity(0.1),
                  child: Icon(IconData(_iconoSeleccionado, fontFamily: 'MaterialIcons'), color: Colors.deepPurple),
                ),
                title: const Text('Ícono de la rutina', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Toca para cambiar'),
                childrenPadding: const EdgeInsets.only(bottom: 20, top: 10),
                children: [
                  Wrap(
                    spacing: 15,
                    runSpacing: 15, // Añadí espacio vertical por si agregas más íconos después
                    children: _opcionesIconos.map((icono) {
                      bool seleccionado = _iconoSeleccionado == icono.codePoint;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _iconoSeleccionado = icono.codePoint);
                          // Opcional: Podrías poner un Navigator.pop si quisieras que se cierre solo, 
                          // pero en este caso es mejor dejar que el usuario lo vea cambiar.
                        },
                        child: CircleAvatar(
                          backgroundColor: seleccionado ? Colors.deepPurple.withOpacity(0.2) : Colors.grey.shade100,
                          child: Icon(icono, color: seleccionado ? Colors.deepPurple : Colors.grey),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 30),

            // Botón Guardar
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _guardarRutina,
                child: const Text('Crear Rutina', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}