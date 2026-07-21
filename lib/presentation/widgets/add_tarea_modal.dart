import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/tarea_provider.dart';
import '../../models/tarea.dart';
import 'ayuda_formulario_button.dart';

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
  late String _grupoSeleccionado;
  late List<String> _gruposDisponibles;

  int _urgenciaBase = 1;
  DateTime? _fechaSeleccionada;
  TimeOfDay? _horaSeleccionada;
  bool _mostrarAvanzadas = false;

  // --- ESTADO LOCAL DE SUBTAREAS ---
  // Se editan en memoria (igual que título/descripción) y solo se
  // persisten al presionar "Guardar", junto con el resto del formulario.
  late List<ItemSubtarea> _subtareasTemp;
  final TextEditingController _nuevaSubtareaController = TextEditingController();
  bool _mostrarSubtareas = false;

  @override
  void initState() {
    super.initState();
    _tituloController = TextEditingController(text: widget.tareaAEditar?.titulo ?? '');
    _descripcionController = TextEditingController(text: widget.tareaAEditar?.descripcion ?? '');
    // Cargamos las horas estimadas si existen (sin ".0" sobrante si es un entero)
    final horasGuardadas = widget.tareaAEditar?.horasEstimadas;
    _horasController = TextEditingController(
      text: horasGuardadas == null
          ? ''
          : (horasGuardadas % 1 == 0 ? horasGuardadas.toInt().toString() : horasGuardadas.toString())
    );
    _grupoSeleccionado = widget.tareaAEditar?.grupo ?? 'General';
    _gruposDisponibles = ref.read(tareaProvider.notifier).obtenerGruposExistentes();
    if (!_gruposDisponibles.contains(_grupoSeleccionado)) {
      _gruposDisponibles = [..._gruposDisponibles, _grupoSeleccionado];
    }
    _urgenciaBase = widget.tareaAEditar?.urgenciaBase ?? 1;
    _fechaSeleccionada = widget.tareaAEditar?.fechaLimite;
    _subtareasTemp = widget.tareaAEditar?.subtareas
            .map((s) => ItemSubtarea(id: s.id, texto: s.texto, completado: s.completado))
            .toList() ??
        [];

    if (_fechaSeleccionada != null) {
      // 23:59 es el límite implícito que _guardarTarea asigna cuando no se
      // elige hora explícita, así que al reabrir para editar se trata igual:
      // el botón "Hora" queda vacío en vez de mostrar "11:59 PM".
      final huboHoraExplicita = !(_fechaSeleccionada!.hour == 23 && _fechaSeleccionada!.minute == 59);
      if (huboHoraExplicita) {
        _horaSeleccionada = TimeOfDay(hour: _fechaSeleccionada!.hour, minute: _fechaSeleccionada!.minute);
      }
      _mostrarAvanzadas = true;
    } else if (_descripcionController.text.isNotEmpty || _horasController.text.isNotEmpty) {
      _mostrarAvanzadas = true;
    }
    if (_subtareasTemp.isNotEmpty) _mostrarSubtareas = true;

    // Al escribir horas estimadas, la urgencia pasa a modo automático:
    // necesitamos reconstruir para deshabilitar el selector manual y
    // recalcular el nivel mostrado.
    _horasController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descripcionController.dispose();
    _horasController.dispose();
    _nuevaSubtareaController.dispose();
    super.dispose();
  }

  void _agregarSubtareaTemp() {
    final texto = _nuevaSubtareaController.text.trim();
    if (texto.isEmpty) return;
    setState(() {
      _subtareasTemp.add(ItemSubtarea(texto: texto));
      _nuevaSubtareaController.clear();
    });
  }

  // Deja solo la primera letra en mayúscula (Ej: "TRabAjo" -> "Trabajo").
  // Devuelve null si el valor queda vacío.
  String? _sanitizarGrupo(String? valor) {
    final limpio = (valor ?? '').trim();
    if (limpio.isEmpty) return null;
    return limpio[0].toUpperCase() + limpio.substring(1).toLowerCase();
  }

  void _refrescarGruposDisponibles() {
    setState(() {
      _gruposDisponibles = ref.read(tareaProvider.notifier).obtenerGruposExistentes();
      if (!_gruposDisponibles.contains(_grupoSeleccionado)) {
        _grupoSeleccionado = 'General';
      }
    });
  }

  Future<void> _crearNuevoGrupo() async {
    final controller = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo grupo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nombre del grupo'),
          onSubmitted: (val) => Navigator.pop(dialogContext, val),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Crear')),
        ],
      ),
    );

    final nombreLimpio = _sanitizarGrupo(nombre);
    if (nombreLimpio == null) return;

    await ref.read(tareaProvider.notifier).registrarGrupoPersistente(nombreLimpio);
    setState(() {
      _gruposDisponibles = ref.read(tareaProvider.notifier).obtenerGruposExistentes();
      _grupoSeleccionado = nombreLimpio;
    });
  }

  Future<void> _gestionarGrupos() async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            final grupos = ref.read(tareaProvider.notifier).obtenerGruposExistentes();
            return AlertDialog(
              title: const Text('Editar grupos'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: grupos.length,
                  itemBuilder: (context, index) {
                    final grupo = grupos[index];
                    final esGeneral = grupo == 'General';
                    return ListTile(
                      title: Text(grupo),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Renombrar',
                            onPressed: () async {
                              final renombreController = TextEditingController(text: grupo);
                              final nuevoNombre = await showDialog<String>(
                                context: dialogContext,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Renombrar grupo'),
                                  content: TextField(
                                    controller: renombreController,
                                    autofocus: true,
                                    textCapitalization: TextCapitalization.sentences,
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, renombreController.text), child: const Text('Guardar')),
                                  ],
                                ),
                              );
                              final nombreLimpio = _sanitizarGrupo(nuevoNombre);
                              if (nombreLimpio == null || nombreLimpio == grupo) return;
                              await ref.read(tareaProvider.notifier).renombrarGrupo(grupo, nombreLimpio);
                              setStateDialog(() {});
                              if (_grupoSeleccionado == grupo) {
                                setState(() => _grupoSeleccionado = nombreLimpio);
                              }
                            },
                          ),
                          if (!esGeneral)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              tooltip: 'Eliminar',
                              onPressed: () async {
                                final confirmar = await showDialog<bool>(
                                  context: dialogContext,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Eliminar grupo'),
                                    content: Text('Las tareas en "$grupo" pasarán al grupo "General". ¿Continuar?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
                                    ],
                                  ),
                                );
                                if (confirmar != true) return;
                                await ref.read(tareaProvider.notifier).eliminarGrupo(grupo);
                                setStateDialog(() {});
                                if (_grupoSeleccionado == grupo) {
                                  setState(() => _grupoSeleccionado = 'General');
                                }
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
              ],
            );
          },
        );
      },
    );
    _refrescarGruposDisponibles();
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (fecha != null) {
      // La hora se deja sin elegir a propósito: si el usuario no la toca,
      // _guardarTarea le asigna 23:59 como límite implícito sin mostrarlo.
      setState(() => _fechaSeleccionada = fecha);
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

  // Quita la fecha límite por completo. Sin fecha, una hora suelta no tiene
  // sentido como límite, así que también se limpia.
  void _limpiarFecha() {
    setState(() {
      _fechaSeleccionada = null;
      _horaSeleccionada = null;
    });
  }

  // Quita solo la hora. La fecha se conserva; al guardar, _guardarTarea usa
  // las 23:59 como hora límite implícita sin mostrarla en este botón.
  void _limpiarHora() {
    setState(() => _horaSeleccionada = null);
  }

  DateTime? get _fechaFinalActual {
    if (_fechaSeleccionada == null) return null;
    return DateTime(
      _fechaSeleccionada!.year,
      _fechaSeleccionada!.month,
      _fechaSeleccionada!.day,
      // Sin hora explícita, el límite real queda al final del día
      // (23:59) sin que el botón "Hora" llegue a mostrarla.
      _horaSeleccionada?.hour ?? 23,
      _horaSeleccionada?.minute ?? 59,
    );
  }

  // Con horas estimadas cargadas, la urgencia deja de elegirse a mano:
  // se calcula sola (igual que Tarea.urgencia) y el selector manual se bloquea.
  bool get _urgenciaEsAutomatica => double.tryParse(_horasController.text.trim()) != null;

  // Sin fecha límite, "horas estimadas" no tiene con qué calcular la urgencia
  // automática (Tarea.urgencia cae directo a urgenciaBase), así que no se
  // permite guardar hasta elegir una fecha o borrar las horas.
  bool get _horasSinFecha => _urgenciaEsAutomatica && _fechaSeleccionada == null;

  int get _urgenciaMostrada {
    final horas = double.tryParse(_horasController.text.trim());
    if (horas == null) return _urgenciaBase;

    final tareaTemporal = Tarea(
      titulo: '',
      urgenciaBase: _urgenciaBase,
      fechaLimite: _fechaFinalActual,
      horasEstimadas: horas,
    );
    return tareaTemporal.urgencia;
  }

  void _guardarTarea() {
    final titulo = _tituloController.text.trim();

    if (titulo.isEmpty || _horasSinFecha) return;

    final fechaFinal = _fechaFinalActual;

    // Convertimos el texto de horas a número (admite decimales, ej. "1.5")
    final double? horas = double.tryParse(_horasController.text.trim());
    final int urgenciaFinal = _urgenciaMostrada;
    final String descripcion = _descripcionController.text.trim();

    // El grupo ya viene sanitizado desde el desplegable; lo registramos
    // por si acaso para que no desaparezca en el futuro.
    final String grupoLimpio = _grupoSeleccionado;
    ref.read(tareaProvider.notifier).registrarGrupoPersistente(grupoLimpio);

    if (widget.tareaAEditar != null) {
      final tareaModificada = widget.tareaAEditar!.copyWith(
        titulo: titulo,
        descripcion: descripcion.isEmpty ? null : descripcion,
        fechaLimite: fechaFinal,
        horasEstimadas: horas,
        urgenciaBase: urgenciaFinal,
        grupo: grupoLimpio, // Usamos la variable ya limpia y sanitizada
        subtareas: _subtareasTemp,
      );
      ref.read(tareaProvider.notifier).updateTarea(tareaModificada);
    } else {
      final nuevaTarea = Tarea(
        titulo: titulo,
        descripcion: descripcion.isEmpty ? null : descripcion,
        fechaLimite: fechaFinal,
        horasEstimadas: horas,
        urgenciaBase: urgenciaFinal,
        grupo: grupoLimpio, // Se agrega para que la nueva tarea también tenga el grupo asignado
        subtareas: _subtareasTemp,
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
            Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  widget.tareaAEditar != null ? 'Editar Tarea' : 'Nueva Tarea',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AyudaFormularioButton(
                    titulo: 'Ayuda: Nueva Tarea',
                    puntos: const [
                      '¿Qué hay que hacer?: Título de la tarea, es obligatorio.',
                      'Grupo: Categoría para organizar tus tareas (ej. Trabajo, Casa). Elige una del listado; usa el ícono "+" para crear una nueva y el lápiz para renombrar o eliminar las existentes.',
                      'Descripción: Notas adicionales opcionales sobre la tarea.',
                      'Fecha y Hora: Fecha límite para completarla. Si no eliges hora, se usa las 23:59 por defecto.',
                      'Urgencia: Qué tan prioritaria es. Si defines horas estimadas, se calcula sola según el tiempo restante.',
                      'Horas estimadas: Tiempo que crees que tomará. Al definirlas, la urgencia deja de elegirse manualmente.',
                      'Subtareas: Pasos pequeños dentro de la tarea que puedes marcar como completados por separado.',
                    ],
                  ),
                ),
              ],
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

            // --- CAMPO DE GRUPO (LISTA DESPLEGABLE + ACCIONES) ---
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _grupoSeleccionado,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black54),
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: Colors.white,
                    elevation: 2,
                    style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      labelText: 'Grupo',
                      prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                      filled: true, fillColor: Colors.grey.shade100,
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400, width: 1.5)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black87, width: 2.0)),
                    ),
                    items: [
                      for (final grupo in _gruposDisponibles)
                        DropdownMenuItem(
                          value: grupo,
                          child: Text(grupo, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (valor) {
                      if (valor != null) setState(() => _grupoSeleccionado = valor);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _BotonAccionGrupo(
                  icon: Icons.add_rounded,
                  tooltip: 'Nuevo grupo',
                  onPressed: _crearNuevoGrupo,
                ),
                const SizedBox(width: 8),
                _BotonAccionGrupo(
                  icon: Icons.edit_rounded,
                  tooltip: 'Editar grupos',
                  onPressed: _gestionarGrupos,
                ),
              ],
            ),
            // --- FIN DEL CAMPO DE GRUPO ---

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
                    child: OutlinedButton.icon(
                      onPressed: _elegirFecha,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_fechaSeleccionada == null ? 'Fecha' : DateFormat('dd MMM').format(_fechaSeleccionada!)),
                    ),
                  ),
                  if (_fechaSeleccionada != null)
                    IconButton(
                      onPressed: _limpiarFecha,
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Quitar fecha',
                      visualDensity: VisualDensity.compact,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _elegirHora,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(_horaSeleccionada == null ? 'Hora' : _horaSeleccionada!.format(context)),
                    ),
                  ),
                  if (_horaSeleccionada != null)
                    IconButton(
                      onPressed: _limpiarHora,
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Quitar hora',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],

            const SizedBox(height: 24),
            Text(
              _urgenciaEsAutomatica ? 'Urgencia (automática por horas estimadas)' : 'Urgencia Manual / Base',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Opacity(
              opacity: _urgenciaEsAutomatica ? 0.5 : 1.0,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Bajo')),
                  ButtonSegment(value: 2, label: Text('Medio')),
                  ButtonSegment(value: 3, label: Text('Alto')),
                  ButtonSegment(value: 4, label: Text('Muy alto')),
                ],
                selected: {_urgenciaMostrada},
                onSelectionChanged: _urgenciaEsAutomatica
                    ? null
                    : (Set<int> sel) => setState(() => _urgenciaBase = sel.first),
              ),
            ),

            if (_mostrarAvanzadas) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _horasController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                decoration: InputDecoration(
                  labelText: 'Horas estimadas',
                  helperText: 'Si la defines, la urgencia se ajusta sola con el tiempo restante',
                  errorText: _horasSinFecha ? 'Elige una fecha límite para poder guardar' : null,
                  prefixIcon: const Icon(Icons.timer_outlined, size: 20),
                  filled: true, fillColor: Colors.grey.shade50,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5)),
                ),
              ),
            ],

            // --- SECCIÓN DE SUBTAREAS (COLAPSABLE) ---
            const SizedBox(height: 24),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _mostrarSubtareas = !_mostrarSubtareas),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.checklist_rounded, size: 18, color: Colors.black54),
                    const SizedBox(width: 8),
                    const Text('Subtareas', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    if (_subtareasTemp.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          '${_subtareasTemp.where((s) => s.completado).length}/${_subtareasTemp.length}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(_mostrarSubtareas ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: !_mostrarSubtareas
                  ? const SizedBox(width: double.infinity, height: 0)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        if (_subtareasTemp.isNotEmpty)
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: _subtareasTemp.length,
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                var destino = newIndex;
                                if (destino > oldIndex) destino -= 1;
                                final item = _subtareasTemp.removeAt(oldIndex);
                                _subtareasTemp.insert(destino, item);
                              });
                            },
                            itemBuilder: (context, index) {
                              final sub = _subtareasTemp[index];
                              return Dismissible(
                                key: ValueKey(sub.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
                                  child: const Icon(Icons.delete_outline, color: Colors.red),
                                ),
                                onDismissed: (_) => setState(() => _subtareasTemp.removeAt(index)),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.only(right: 4),
                                          child: Icon(Icons.drag_indicator, size: 20, color: Colors.black26),
                                        ),
                                      ),
                                      SizedBox(
                                        height: 24, width: 24,
                                        child: Checkbox(
                                          value: sub.completado,
                                          activeColor: Colors.black87,
                                          onChanged: (val) => setState(() => sub.completado = val ?? false),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          sub.texto,
                                          style: TextStyle(
                                            fontSize: 15,
                                            decoration: sub.completado ? TextDecoration.lineThrough : null,
                                            color: sub.completado ? Colors.black38 : Colors.black87,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => setState(() => _subtareasTemp.removeAt(index)),
                                        child: const Icon(Icons.close, size: 18, color: Colors.black38),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _nuevaSubtareaController,
                                decoration: InputDecoration(
                                  hintText: 'Agregar paso...',
                                  isDense: true,
                                  filled: true, fillColor: Colors.grey.shade50,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5)),
                                ),
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _agregarSubtareaTemp(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add_circle, size: 28, color: Colors.black87),
                              onPressed: _agregarSubtareaTemp,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _horasSinFecha ? null : _guardarTarea,
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

// Botón cuadrado junto al desplegable de grupo (crear / editar grupos),
// con el mismo trazo y radio que los campos de texto del formulario.
class _BotonAccionGrupo extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _BotonAccionGrupo({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade400, width: 1.5),
            ),
            child: Icon(icon, color: Colors.black87, size: 22),
          ),
        ),
      ),
    );
  }
}