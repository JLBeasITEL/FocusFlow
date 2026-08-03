import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/rutina.dart';
import '../../providers/rutina_provider.dart';
import '../widgets/ayuda_formulario_button.dart';

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

  // Programar las notificaciones de una rutina puede tardar unos segundos
  // (hasta 4 semanas de colchón por cada día programado, ver
  // _resetCompletoNotificacionesRutina en rutina_provider.dart) — con más
  // días activos, más llamadas nativas a AlarmManager. Este flag maneja el
  // overlay de carga para que quede claro que la app sigue trabajando y no
  // se congeló, y evita que el usuario dispare un segundo guardado o
  // navegue hacia atrás mientras el primero sigue en curso.
  bool _guardando = false;

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
        for (var day in r.horarios.keys) {
          _diasFijos[day] = true;
        }
      }
    }
  }

  // MÉTODO DE GUARDADO CENTRALIZADO
  Future<void> _guardarRutina() async {
  if (_guardando) return; // Evita un segundo guardado mientras el primero sigue en curso.

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

  setState(() => _guardando = true);
  try {
    if (widget.rutinaAEditar == null) {
      await ref.read(rutinaProvider.notifier).addRutina(rutina);
    } else {
      await ref.read(rutinaProvider.notifier).editarRutina(rutina);
    }
    if (mounted) Navigator.pop(context);
  } catch (e) {
    if (mounted) {
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la rutina: $e')),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Evita salir del formulario a medias mientras se están programando
      // las notificaciones — no rompería nada (el guardado sigue corriendo
      // en el provider), pero es confuso ver la lista sin la rutina nueva
      // todavía mientras el proceso sigue en curso.
      canPop: !_guardando,
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.rutinaAEditar == null ? 'Crear hábito' : 'Editar Rutina'),
        actions: [
          AyudaFormularioButton(
            titulo: 'Ayuda: Hábito',
            puntos: const [
              'Título del hábito: Nombre de la rutina que quieres repetir.',
              'Descripción: Detalle opcional sobre el hábito.',
              'Horario personalizado por día: Actívalo para elegir una hora distinta cada día; desactívalo para usar siempre la misma hora.',
              'Hora general / Días de repetición: Hora fija y los días en que se repetirá (modo simple, sin horario personalizado).',
              'Horarios específicos: Hora individual para cada día que actives (modo horario personalizado).',
              'Ícono: Imagen que identifica al hábito en la lista.',
            ],
          ),
          // BOTÓN DE GUARDADO EN LA PARTE SUPERIOR (SIEMPRE VISIBLE)
          if (_guardando)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_rounded, size: 28),
              onPressed: _guardarRutina,
              tooltip: 'Guardar cambios',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
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
              activeThumbColor: Colors.deepPurple,
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
                      if (val!) {
                        _horarios[idx] = const TimeOfDay(hour: 8, minute: 0);
                      } else {
                        _horarios.remove(idx);
                      }
                    });
                  },
                );
              }),
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
                onPressed: _guardando ? null : _guardarRutina,
                child: _guardando
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        widget.rutinaAEditar == null ? 'Guardar Rutina' : 'Actualizar Rutina',
                        style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
          ),
          // Overlay de carga: bloquea el formulario y explica la demora
          // (programar notificaciones de varios días toma varios segundos).
          if (_guardando)
            Positioned.fill(
              child: AbsorbPointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.15),
                  child: Center(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text('Guardando y programando notificaciones...'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}