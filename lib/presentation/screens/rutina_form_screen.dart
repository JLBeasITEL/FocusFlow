import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/rutina.dart';
import '../../providers/rutina_provider.dart';

class RutinaFormScreen extends ConsumerStatefulWidget {
  final Rutina? rutinaAEditar;

  const RutinaFormScreen({super.key, this.rutinaAEditar});

  @override
  ConsumerState<RutinaFormScreen> createState() => _RutinaFormScreenState();
}

class _RutinaFormScreenState extends ConsumerState<RutinaFormScreen> {
  final _tituloController = TextEditingController();
  final _descripcionController = TextEditingController();
  
  bool _esFlexible = false; 
  Map<int, TimeOfDay> _horarios = {}; 
  
  TimeOfDay _horaFija = const TimeOfDay(hour: 8, minute: 0);
  final List<bool> _diasFijos = [false, false, false, false, false, false, false];

  int _iconoSeleccionado = Icons.fitness_center.codePoint;

  final List<IconData> _opcionesIconos = [
    Icons.medication, Icons.medical_services, Icons.monitor_heart, Icons.water_drop,
    Icons.fitness_center, Icons.directions_run, Icons.self_improvement, Icons.nightlight_round,
    Icons.code, Icons.computer, Icons.menu_book, Icons.science,
    Icons.piano, Icons.videogame_asset, Icons.headphones, Icons.cleaning_services,
    Icons.local_laundry_service, Icons.shopping_cart, Icons.pets, Icons.blender,
    Icons.memory, Icons.directions_car, Icons.account_balance_wallet, Icons.diversity_3,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.rutinaAEditar != null) {
      final r = widget.rutinaAEditar!;
      _tituloController.text = r.titulo;
      _descripcionController.text = r.descripcion ?? '';
      _iconoSeleccionado = r.iconoCode;
      _esFlexible = r.esFlexible;
      _horarios = Map.from(r.horarios);

      if (!_esFlexible && r.horarios.isNotEmpty) {
        _horaFija = r.horarios.values.first;
        r.horarios.keys.forEach((day) => _diasFijos[day] = true);
      }
    }
  }

  // MÉTODO DE GUARDADO CENTRALIZADO
  void _guardarRutina() {
    if (_tituloController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, asigne un título.')),
      );
      return;
    }

    if (!_esFlexible) {
      _horarios.clear();
      for (int i = 0; i < _diasFijos.length; i++) {
        if (_diasFijos[i]) _horarios[i] = _horaFija;
      }
    }

    if (_horarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione al menos un día.')),
      );
      return;
    }

    final rutina = Rutina(
      id: widget.rutinaAEditar?.id ?? const Uuid().v4(),
      titulo: _tituloController.text.trim(),
      descripcion: _descripcionController.text.trim().isEmpty ? null : _descripcionController.text.trim(),
      horarios: _horarios,
      esFlexible: _esFlexible,
      iconoCode: _iconoSeleccionado,
      racha: widget.rutinaAEditar?.racha ?? 0,
      activa: widget.rutinaAEditar?.activa ?? true,
      completada: widget.rutinaAEditar?.completada ?? false,
      fechaCompletada: widget.rutinaAEditar?.fechaCompletada,
    );

    if (widget.rutinaAEditar == null) {
      ref.read(rutinaProvider.notifier).addRutina(rutina);
    } else {
      ref.read(rutinaProvider.notifier).editarRutina(rutina);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rutinaAEditar == null ? 'Crear hábito' : 'Editar Rutina'),
        actions: [
          // BOTÓN DE GUARDADO EN LA PARTE SUPERIOR (SIEMPRE VISIBLE)
          IconButton(
            icon: const Icon(Icons.check_rounded, size: 28),
            onPressed: _guardarRutina,
            tooltip: 'Guardar cambios',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _tituloController,
              decoration: InputDecoration(
                labelText: 'Título del hábito',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                prefixIcon: const Icon(Icons.repeat_rounded),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _descripcionController,
              decoration: InputDecoration(
                labelText: 'Descripción (Opcional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                prefixIcon: const Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 20),

            SwitchListTile(
              title: const Text('Horario personalizado por día', 
                style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Desactiva para usar la misma hora siempre'),
              value: _esFlexible,
              activeColor: Colors.deepPurple,
              onChanged: (val) => setState(() => _esFlexible = val),
            ),
            const Divider(),

            if (!_esFlexible) ...[
              ListTile(
                title: const Text('Hora general'),
                trailing: ElevatedButton.icon(
                  icon: const Icon(Icons.access_time, size: 18),
                  onPressed: () async {
                    final select = await showTimePicker(context: context, initialTime: _horaFija);
                    if (select != null) setState(() => _horaFija = select);
                  },
                  label: Text(_horaFija.format(context)),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Días de repetición', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ['L', 'M', 'M', 'J', 'V', 'S', 'D'].asMap().entries.map((entry) {
                  int idx = entry.key;
                  bool activo = _diasFijos[idx];
                  return GestureDetector(
                    onTap: () => setState(() => _diasFijos[idx] = !activo),
                    child: CircleAvatar(
                      backgroundColor: activo ? Colors.deepPurple : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      child: Text(entry.value),
                    ),
                  );
                }).toList(),
              ),
            ] else ...[
              const Text('Horarios específicos', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'].asMap().entries.map((entry) {
                int idx = entry.key;
                bool activo = _horarios.containsKey(idx);
                return CheckboxListTile(
                  title: Text(entry.value, style: TextStyle(fontWeight: activo ? FontWeight.bold : FontWeight.normal)),
                  value: activo,
                  activeColor: Colors.deepPurple,
                  secondary: activo ? TextButton.icon(
                    icon: const Icon(Icons.access_time, size: 18),
                    onPressed: () async {
                      final select = await showTimePicker(context: context, initialTime: _horarios[idx]!);
                      if (select != null) setState(() => _horarios[idx] = select);
                    },
                    label: Text(_horarios[idx]!.format(context)),
                  ) : null,
                  onChanged: (val) {
                    setState(() {
                      if (val!) _horarios[idx] = const TimeOfDay(hour: 8, minute: 0);
                      else _horarios.remove(idx);
                    });
                  },
                );
              }).toList(),
            ],

            const SizedBox(height: 25),
            
            // Selector de íconos
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                  child: Icon(IconData(_iconoSeleccionado, fontFamily: 'MaterialIcons'), color: Colors.deepPurple),
                ),
                title: const Text('Ícono', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Toca para cambiar'),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _opcionesIconos.map((icono) {
                      bool seleccionado = _iconoSeleccionado == icono.codePoint;
                      return GestureDetector(
                        onTap: () => setState(() => _iconoSeleccionado = icono.codePoint),
                        child: CircleAvatar(
                          backgroundColor: seleccionado ? Colors.deepPurple.withValues(alpha: 0.2) : Colors.grey.shade200,
                          child: Icon(icono, color: seleccionado ? Colors.deepPurple : Colors.grey),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
            
            // BOTÓN DE GUARDADO AL FINAL (POR SI EL USUARIO SIGUE HACIENDO SCROLL)
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _guardarRutina,
                child: Text(
                  widget.rutinaAEditar == null ? 'Guardar Rutina' : 'Actualizar Rutina',
                  style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}