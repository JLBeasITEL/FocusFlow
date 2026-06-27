import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/tarea_provider.dart';
import '../../models/tarea.dart';

class AddTareaModal extends ConsumerStatefulWidget {
  final Tarea? tareaAEditar;

  const AddTareaModal({super.key, this.tareaAEditar});

  @override
  ConsumerState<AddTareaModal> createState() => _AddTareaModalState();
}

class _AddTareaModalState extends ConsumerState<AddTareaModal> {
  late TextEditingController _tituloController;
  late TextEditingController _descripcionController;
  late TextEditingController _horasController;
  late TextEditingController _grupoController;
  
  int _urgenciaBase = 1;
  DateTime? _fechaSeleccionada;
  TimeOfDay? _horaSeleccionada;
  bool _mostrarAvanzadas = false;

  @override
  void initState() {
    super.initState();
    _tituloController = TextEditingController(text: widget.tareaAEditar?.titulo ?? '');
    _descripcionController = TextEditingController(text: widget.tareaAEditar?.descripcion ?? '');
    // Cargamos las horas estimadas si existen
    _horasController = TextEditingController(
      text: widget.tareaAEditar?.horasEstimadas?.toString() ?? ''
    );
    _grupoController = TextEditingController(text: widget.tareaAEditar?.grupo ?? 'General');
    _urgenciaBase = widget.tareaAEditar?.urgenciaBase ?? 1;
    _fechaSeleccionada = widget.tareaAEditar?.fechaLimite;
    
    if (_fechaSeleccionada != null) {
      _horaSeleccionada = TimeOfDay(hour: _fechaSeleccionada!.hour, minute: _fechaSeleccionada!.minute);
      _mostrarAvanzadas = true;
    } else if (_descripcionController.text.isNotEmpty || _horasController.text.isNotEmpty) {
      _mostrarAvanzadas = true;
    }
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descripcionController.dispose();
    _horasController.dispose();
    _grupoController.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (fecha != null) {
      setState(() {
        _fechaSeleccionada = fecha;
        _horaSeleccionada ??= const TimeOfDay(hour: 9, minute: 0);
      });
    }
  }

  Future<void> _elegirHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _horaSeleccionada ?? TimeOfDay.now(),
    );
    if (hora != null) {
      setState(() {
        _horaSeleccionada = hora;
        _fechaSeleccionada ??= DateTime.now();
      });
    }
  }

  void _guardarTarea() {
    final titulo = _tituloController.text.trim();

    if (titulo.isEmpty) return;

    DateTime? fechaFinal;
    if (_fechaSeleccionada != null) {
      fechaFinal = DateTime(
        _fechaSeleccionada!.year,
        _fechaSeleccionada!.month,
        _fechaSeleccionada!.day,
        _horaSeleccionada?.hour ?? 0,
        _horaSeleccionada?.minute ?? 0,
      );
    }

    // Convertimos el texto de horas a número
    final int? horas = int.tryParse(_horasController.text.trim());
    final String descripcion = _descripcionController.text.trim();

    // --- INICIO DE SANITIZACIÓN DEL GRUPO ---
    String grupoLimpio = _grupoController.text.trim();
    
    if (grupoLimpio.isEmpty) {
      grupoLimpio = 'General';
    } else {
      // Forzamos a que solo la primera letra sea mayúscula (Ej: "TRabAjo" -> "Trabajo")
      grupoLimpio = grupoLimpio[0].toUpperCase() + grupoLimpio.substring(1).toLowerCase();
    }

    //Registramos el grupo para que no desaparezca en el futuro
    ref.read(tareaProvider.notifier).registrarGrupoPersistente(grupoLimpio);
    // --- FIN DE SANITIZACIÓN ---

    if (widget.tareaAEditar != null) {
      final tareaModificada = widget.tareaAEditar!.copyWith(
        titulo: titulo,
        descripcion: descripcion.isEmpty ? null : descripcion,
        fechaLimite: fechaFinal,
        horasEstimadas: horas,
        urgenciaBase: _urgenciaBase, 
        grupo: grupoLimpio, // Usamos la variable ya limpia y sanitizada
      );
      ref.read(tareaProvider.notifier).updateTarea(tareaModificada);
    } else {
      final nuevaTarea = Tarea(
        titulo: titulo,
        descripcion: descripcion.isEmpty ? null : descripcion,
        fechaLimite: fechaFinal,
        horasEstimadas: horas,
        urgenciaBase: _urgenciaBase, // Cambio de nombre aquí
        grupo: grupoLimpio, // Se agrega para que la nueva tarea también tenga el grupo asignado
      );
      ref.read(tareaProvider.notifier).addTarea(nuevaTarea);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
            Text(
              widget.tareaAEditar != null ? 'Editar Tarea' : 'Nueva Tarea',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            TextField(
              controller: _tituloController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '¿Qué hay que hacer?',
                filled: true, fillColor: Colors.grey.shade100,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400, width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black87, width: 2.0)),
              ),
            ),

            // --- INICIO DEL NUEVO CAMPO DE GRUPO ---
            const SizedBox(height: 16),
            Consumer(
              builder: (context, ref, child) {
                // Le pedimos al provider la lista de grupos que ya existen
                final gruposSugeridos = ref.read(tareaProvider.notifier).obtenerGruposExistentes();

                return Autocomplete<String>(
                  initialValue: TextEditingValue(text: _grupoController.text),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return gruposSugeridos; // Muestra todos por defecto
                    }
                    return gruposSugeridos.where((String option) {
                      return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  onSelected: (String selection) {
                    _grupoController.text = selection;
                  },
                  fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                    // Mantener sincronizado el controlador interno
                    controller.addListener(() {
                      _grupoController.text = controller.text;
                    });
                    
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Grupo (Ej. Trabajo, Casa...)',
                        prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                        filled: true, fillColor: Colors.grey.shade100,
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400, width: 1.5)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black87, width: 2.0)),
                      ),
                    );
                  },
                );
              },
            ),
            // --- FIN DEL NUEVO CAMPO DE GRUPO ---

            if (_mostrarAvanzadas) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _descripcionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Descripción',
                  filled: true, fillColor: Colors.grey.shade50,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _horasController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Horas estimadas',
                        prefixIcon: const Icon(Icons.timer_outlined, size: 20),
                        filled: true, fillColor: Colors.grey.shade50,
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _elegirFecha,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_fechaSeleccionada == null ? 'Fecha' : DateFormat('dd MMM').format(_fechaSeleccionada!)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _elegirHora,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(_horaSeleccionada == null ? 'Hora' : _horaSeleccionada!.format(context)),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),
            const Text('Urgencia Manual / Base', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Bajo')),
                ButtonSegment(value: 2, label: Text('Medio')),
                ButtonSegment(value: 3, label: Text('Alto')),
                ButtonSegment(value: 4, label: Text('Muy alto')),
              ],
              selected: {_urgenciaBase},
              onSelectionChanged: (Set<int> sel) => setState(() => _urgenciaBase = sel.first),
            ),
            
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _guardarTarea,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Guardar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            
            if (!_mostrarAvanzadas)
              TextButton.icon(
                onPressed: () => setState(() => _mostrarAvanzadas = true),
                icon: const Icon(Icons.tune),
                label: const Text('Más opciones (Esfuerzo y Fecha)'),
              ),
          ],
        ),
      ),
    );
  }
}