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

  final String descripcionIngresada = _descripcionController.text.trim();
  final Rutina? rutinaAEditar = widget.rutinaAEditar;

  // EDICIÓN: se deriva de la rutina existente (copyWith) para no perder
  // ningún campo que este formulario no conoce (omitida, fechaOmitida,
  // omisionesSeguidas, historialOmisiones, rachaPagadaHasta,
  // omisionesSeguidasAntesDeMarcar, idsPorOcurrencia, ultimaFechaProgramada,
  // notificacionesActivas, racha, completada, fechaCompletada) — antes se
  // reconstruía una Rutina desde cero y todos esos campos volvían a su valor
  // por defecto en cada edición (ver auditoría: reseteaba rachaPagadaHasta y
  // omisionesSeguidas, permitiendo cobrar monedas de más o abaratar el costo
  // de omitir con solo cambiar el título o el ícono).
  final Rutina rutina = rutinaAEditar != null
      ? rutinaAEditar.copyWith(
          titulo: _tituloController.text.trim(),
          horarios: _horarios,
          esFlexible: _esFlexible,
          iconoCode: _iconoSeleccionado,
          descripcion: descripcionIngresada.isEmpty ? null : descripcionIngresada,
          limpiarDescripcion: descripcionIngresada.isEmpty,
        )
      // CREACIÓN: sin cambios respecto al comportamiento anterior.
      : Rutina(
          id: const Uuid().v4(),
          titulo: _tituloController.text.trim(),
          descripcion: descripcionIngresada.isEmpty ? null : descripcionIngresada,
          horarios: _horarios,
          esFlexible: _esFlexible,
          iconoCode: _iconoSeleccionado,
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

  // Mismos puntos de ayuda para portrait y landscape — un solo lugar para
  // no tener que mantener dos copias sincronizadas.
  static const List<String> _puntosAyuda = [
    'Título del hábito: Nombre de la rutina que quieres repetir.',
    'Descripción: Detalle opcional sobre el hábito.',
    'Horario personalizado por día: Actívalo para elegir una hora distinta cada día; desactívalo para usar siempre la misma hora.',
    'Hora general / Días de repetición: Hora fija y los días en que se repetirá (modo simple, sin horario personalizado).',
    'Horarios específicos: Hora individual para cada día que actives (modo horario personalizado).',
    'Ícono: Imagen que identifica al hábito en la lista.',
  ];

  @override
  Widget build(BuildContext context) {
    // Este screen siempre se abre con Navigator.push (nunca como bottom
    // sheet, a diferencia de AddTareaModal), así que rotar con el
    // formulario abierto no tiene el problema de "contenedor equivocado":
    // el mismo Scaffold se queda montado y solo cambia qué body construye,
    // igual que ya hace home_screen.dart entre su vista portrait y
    // _buildBodyLandscape.
    final bool esLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      // Evita salir del formulario a medias mientras se están programando
      // las notificaciones — no rompería nada (el guardado sigue corriendo
      // en el provider), pero es confuso ver la lista sin la rutina nueva
      // todavía mientras el proceso sigue en curso.
      canPop: !_guardando,
      child: Scaffold(
      appBar: esLandscape ? null : AppBar(
        title: Text(widget.rutinaAEditar == null ? 'Crear hábito' : 'Editar Rutina'),
        actions: [
          AyudaFormularioButton(
            titulo: 'Ayuda: Hábito',
            puntos: _puntosAyuda,
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
      body: esLandscape ? _buildBodyLandscape(context) : _buildBodyPortrait(context),
      ),
    );
  }

  Widget _buildBodyPortrait(BuildContext context) {
    return Stack(
        children: [
          SafeArea(
            top: false,
            child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _tituloController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Título del hábito',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                prefixIcon: const Icon(Icons.repeat_rounded),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _descripcionController,
              textCapitalization: TextCapitalization.sentences,
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
      );
  }

  // =====================================================================
  // LAYOUT HORIZONTAL (landscape): encabezado propio (sin AppBar) + fila de
  // ícono/título/descripción + grilla de 7 días, con Guardar/Cancelar fijos
  // al pie. Reutiliza exactamente el mismo estado y los mismos handlers que
  // portrait (_esFlexible, _horarios, _diasFijos, _horaFija,
  // _iconoSeleccionado, _guardarRutina) — es 100% reacomodo visual.
  // =====================================================================

  static const List<String> _letrasDias = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const List<String> _abreviaturasDias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  bool _diaActivo(int idx) => _esFlexible ? _horarios.containsKey(idx) : _diasFijos[idx];

  void _alternarDia(int idx) {
    setState(() {
      if (_esFlexible) {
        if (_horarios.containsKey(idx)) {
          _horarios.remove(idx);
        } else {
          _horarios[idx] = const TimeOfDay(hour: 8, minute: 0);
        }
      } else {
        _diasFijos[idx] = !_diasFijos[idx];
      }
    });
  }

  Future<void> _elegirHoraDia(int idx) async {
    final actual = _horarios[idx] ?? const TimeOfDay(hour: 8, minute: 0);
    final elegida = await showTimePicker(context: context, initialTime: actual);
    if (elegida != null) setState(() => _horarios[idx] = elegida);
  }

  // Mismo Wrap de 24 íconos que ya vive dentro del ExpansionTile de
  // portrait, pero en un diálogo: en landscape no hay alto de sobra para
  // dejarlo expandido debajo del avatar (mismo patrón que "Nuevo grupo" /
  // "Guardar como plantilla" en el formulario de tareas).
  Future<void> _elegirIconoDialogo() async {
    final elegido = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elegir ícono'),
        content: SizedBox(
          width: 360,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _opcionesIconos.map((icono) {
              final bool seleccionado = _iconoSeleccionado == icono.codePoint;
              return GestureDetector(
                onTap: () => Navigator.pop(dialogContext, icono.codePoint),
                child: CircleAvatar(
                  backgroundColor: seleccionado ? Colors.deepPurple.withValues(alpha: 0.2) : Colors.grey.shade200,
                  child: Icon(icono, color: seleccionado ? Colors.deepPurple : Colors.grey),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
        ],
      ),
    );
    if (elegido != null) setState(() => _iconoSeleccionado = elegido);
  }

  Widget _buildBodyLandscape(BuildContext context) {
    final diasActivos = List.generate(7, _diaActivo);
    final resumenDias = diasActivos.contains(true)
        ? diasActivos.asMap().entries.where((e) => e.value).map((e) => _abreviaturasDias[e.key]).join(' · ')
        : 'Sin días seleccionados';

    return SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      visualDensity: VisualDensity.compact,
                      onPressed: _guardando ? null : () => Navigator.pop(context),
                    ),
                    Text(
                      widget.rutinaAEditar == null ? 'Crear hábito' : 'Editar Rutina',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        resumenDias,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                    AyudaFormularioButton(titulo: 'Ayuda: Hábito', puntos: _puntosAyuda),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _elegirIconoDialogo,
                              child: CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                                child: Icon(
                                  IconData(_iconoSeleccionado, fontFamily: 'MaterialIcons'),
                                  color: Colors.deepPurple,
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _tituloController,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: 'Título del hábito',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                                  prefixIcon: const Icon(Icons.repeat_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _descripcionController,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: 'Descripción (Opcional)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                                  prefixIcon: const Icon(Icons.description_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Text('Días de repetición', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            if (!_esFlexible) ...[
                              OutlinedButton.icon(
                                icon: const Icon(Icons.access_time, size: 18),
                                onPressed: () async {
                                  final select = await showTimePicker(context: context, initialTime: _horaFija);
                                  if (select != null) setState(() => _horaFija = select);
                                },
                                label: Text('Hora general: ${_horaFija.format(context)}'),
                              ),
                              const SizedBox(width: 16),
                            ],
                            const Text('Horario personalizado por día'),
                            Switch(
                              value: _esFlexible,
                              activeThumbColor: Colors.deepPurple,
                              onChanged: (val) => setState(() => _esFlexible = val),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(7, (idx) {
                            final bool activo = diasActivos[idx];
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => _alternarDia(idx),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activo ? Colors.deepPurple.withValues(alpha: 0.1) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: activo ? Colors.deepPurple : Colors.grey.shade300,
                                        foregroundColor: Colors.white,
                                        child: Text(_letrasDias[idx]),
                                      ),
                                      if (_esFlexible && activo) ...[
                                        const SizedBox(height: 8),
                                        GestureDetector(
                                          onTap: () => _elegirHoraDia(idx),
                                          child: Text(
                                            _horarios[idx]!.format(context),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.deepPurple,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Cancelar/Guardar fijos al pie (no scrollean con el resto):
                // pedido explícito, aunque con el teclado abierto el alto
                // disponible en landscape es poco — por eso el resto de los
                // controles (arriba) sí está en su propio scroll, para que
                // sea eso lo que se desplace y este footer nunca se mueva.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _guardando ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: _guardando ? null : _guardarRutina,
                      child: _guardando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              widget.rutinaAEditar == null ? 'Guardar Rutina' : 'Actualizar Rutina',
                              style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    );
  }
}