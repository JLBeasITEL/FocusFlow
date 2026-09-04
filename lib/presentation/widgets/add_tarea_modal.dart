import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/tarea_provider.dart';
import '../../providers/plantilla_provider.dart';
import '../../providers/tema_provider.dart';
import '../../models/tarea.dart';
import '../../models/plantilla.dart';
import '../../core/app_messenger.dart';
import 'ayuda_formulario_button.dart';
import '../../main.dart' show navigatorKey;

// Punto de entrada único para abrir "Nueva/Editar Tarea": en portrait sigue
// siendo el bottom sheet de siempre (sin cambios); en landscape, el
// formulario de dos columnas necesita más espacio del que un sheet puede
// dar, así que se empuja como pantalla completa. Los dos call sites
// (home_screen.dart y tarea_card_landscape.dart) usan este helper en vez de
// invocar showModalBottomSheet directamente para no duplicar esta rama.
//
// `borrador` es exclusivamente para _reabrirTrasCambioDeOrientacion: cuando
// el usuario rota el dispositivo con el formulario ya abierto, hay que
// cerrarlo y reabrirlo con el contenedor correcto (ver comentario ahí), y
// `borrador` lleva los valores que ya había escrito para no perderlos. A
// diferencia de `tareaAEditar`, nunca decide el modo guardar/actualizar.
//
// `orientacion`, si se pasa, se usa en vez de volver a leer
// MediaQuery.of(context).orientation. Solo lo usa
// _reabrirTrasCambioDeOrientacion: ahí `context` es el del Overlay (para que
// el nuevo contenido sí encuentre Theme/Material), pero justo por no ser el
// context del formulario, su MediaQuery puede ir un paso atrás del real —
// eligiendo por ejemplo Navigator.push (pantalla completa) mientras
// AddTareaModal, con SU PROPIO MediaQuery ya actualizado, construye el
// contenido de portrait. Portrait sin el Material que pone BottomSheet
// truena con "No Material widget found" (TextField/DropdownButton). Pasar
// la orientación ya conocida evita que estas dos lecturas se desincronicen.
void abrirFormularioTarea(BuildContext context, {Tarea? tareaAEditar, Tarea? borrador, Orientation? orientacion}) {
  final bool esLandscape = (orientacion ?? MediaQuery.of(context).orientation) == Orientation.landscape;
  if (esLandscape) {
    Navigator.push(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => AddTareaModal(tareaAEditar: tareaAEditar, borrador: borrador)),
    );
  } else {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTareaModal(tareaAEditar: tareaAEditar, borrador: borrador),
    );
  }
}

class AddTareaModal extends ConsumerStatefulWidget {
  final Tarea? tareaAEditar;
  final Tarea? borrador;

  const AddTareaModal({super.key, this.tareaAEditar, this.borrador});

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

  // --- RECURRENCIA POR INTERVALO ---
  // diaAncla no tiene control propio: se deriva del día de _fechaFinalActual
  // al guardar (ver _guardarTarea), así que acá solo hace falta rastrear
  // tipo + intervalo.
  TipoRecurrencia _tipoRecurrencia = TipoRecurrencia.ninguna;
  final TextEditingController _intervaloController = TextEditingController();

  // --- ESTADO LOCAL DE SUBTAREAS ---
  // Se editan en memoria (igual que título/descripción) y solo se
  // persisten al presionar "Guardar", junto con el resto del formulario.
  late List<ItemSubtarea> _subtareasTemp;
  final TextEditingController _nuevaSubtareaController = TextEditingController();
  bool _mostrarSubtareas = false;

  @override
  void initState() {
    super.initState();
    // widget.borrador solo llega desde _reabrirTrasCambioDeOrientacion (ver
    // más abajo): valores en progreso a restaurar tras rotar el dispositivo
    // con el formulario abierto. widget.tareaAEditar sigue siendo la única
    // fuente para decidir si _guardarTarea actualiza o crea.
    final datosIniciales = widget.tareaAEditar ?? widget.borrador;
    _tituloController = TextEditingController(text: datosIniciales?.titulo ?? '');
    _descripcionController = TextEditingController(text: datosIniciales?.descripcion ?? '');
    // Cargamos las horas estimadas si existen (sin ".0" sobrante si es un entero)
    final horasGuardadas = datosIniciales?.horasEstimadas;
    _horasController = TextEditingController(
      text: horasGuardadas == null
          ? ''
          : (horasGuardadas % 1 == 0 ? horasGuardadas.toInt().toString() : horasGuardadas.toString())
    );
    _grupoSeleccionado = datosIniciales?.grupo ?? 'General';
    _gruposDisponibles = ref.read(tareaProvider.notifier).obtenerGruposExistentes();
    if (!_gruposDisponibles.contains(_grupoSeleccionado)) {
      _gruposDisponibles = [..._gruposDisponibles, _grupoSeleccionado];
    }
    _urgenciaBase = datosIniciales?.urgenciaBase ?? 1;
    _fechaSeleccionada = datosIniciales?.fechaLimite;
    _tipoRecurrencia = datosIniciales?.tipoRecurrencia ?? TipoRecurrencia.ninguna;
    if (datosIniciales?.intervalo != null) {
      _intervaloController.text = datosIniciales!.intervalo.toString();
    }
    _subtareasTemp = datosIniciales?.subtareas
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
    }
    // Fecha/Hora ya no vive dentro de "Más opciones" (siempre visible, ver
    // _buildPortrait), así que tener fechaLimite ya no es motivo por sí solo
    // para auto-expandir: solo Descripción/Horas estimadas/Subtareas siguen
    // ahí, y son las que deciden si hace falta abrirlo de entrada.
    if (_descripcionController.text.isNotEmpty ||
        _horasController.text.isNotEmpty ||
        _subtareasTemp.isNotEmpty) {
      // Subtareas ahora vive dentro de "Más opciones": si la tarea que se
      // edita ya trae subtareas, hay que expandir la sección o quedarían
      // escondidas sin que el usuario sepa que existen.
      _mostrarAvanzadas = true;
    }
    if (_subtareasTemp.isNotEmpty) _mostrarSubtareas = true;

    // Al escribir horas estimadas, la urgencia pasa a modo automático:
    // necesitamos reconstruir para deshabilitar el selector manual y
    // recalcular el nivel mostrado.
    _horasController.addListener(() => setState(() {}));
  }

  // Orientación con la que se abrió este formulario. abrirFormularioTarea ya
  // elige bottom sheet (portrait) o pantalla completa (landscape) al abrir,
  // pero si el usuario ROTA el dispositivo con el formulario ya abierto esa
  // elección queda vieja: seguiría siendo, por ejemplo, un bottom sheet con
  // el contenido de landscape adentro, sin ancho para nada (justo el bug
  // reportado). didChangeDependencies corre en cada cambio de MediaQuery
  // (también por el teclado), así que solo actuamos si la orientación en sí
  // cambió.
  Orientation? _orientacionAlAbrir;
  bool _reabriendoPorRotacion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery.orientationOf (no MediaQuery.of(context).orientation): este
    // último se suscribe a todo el MediaQueryData completo, así que cualquier cambio de
    // viewInsets (p. ej. el teclado abriéndose/cerrándose) también dispara
    // este didChangeDependencies y, con él, un rebuild completo del
    // formulario landscape en cada frame de la animación del teclado — eso
    // era el "proceso pesado" que hacía verse lenta la apertura del teclado.
    // orientationOf solo redispara cuando la orientación en sí cambia.
    final actual = MediaQuery.orientationOf(context);
    _orientacionAlAbrir ??= actual;
    if (!_reabriendoPorRotacion && actual != _orientacionAlAbrir) {
      _reabriendoPorRotacion = true;
      _reabrirTrasCambioDeOrientacion(actual);
    }
  }

  // Cierra este formulario y lo vuelve a abrir con el contenedor correcto
  // para la nueva orientación, pasando un borrador con lo que el usuario ya
  // había escrito para no perderlo. navigatorKey (no `context`) porque tras
  // el pop este State se desmonta y su contexto deja de ser válido.
  //
  // El pop y el reabrir van en DOS addPostFrameCallback anidados, no uno
  // solo: hacerlo todo en el mismo frame reabre el formulario antes de que
  // el Overlay termine de acomodarse tras el pop.
  //
  // `nuevaOrientacion` se pasa tal cual a abrirFormularioTarea en vez de
  // dejar que la vuelva a leer sola, para no depender de qué tan al día
  // esté el MediaQuery del context del Overlay en ese instante.
  void _reabrirTrasCambioDeOrientacion(Orientation nuevaOrientacion) {
    final tareaOriginal = widget.tareaAEditar;
    final borrador = _construirBorrador();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentState?.overlay?.context;
        if (ctx != null) {
          abrirFormularioTarea(ctx, tareaAEditar: tareaOriginal, borrador: borrador, orientacion: nuevaOrientacion);
        }
      });
    });
  }

  // Misma construcción que _guardarTarea, pero sin persistir nada: solo para
  // pasar los valores en progreso a la instancia que se abre después de
  // rotar. Mantiene el id/tipo (nueva vs. edición) del widget original.
  Tarea _construirBorrador() {
    final descripcion = _descripcionController.text.trim();
    final horas = double.tryParse(_horasController.text.trim());
    final base = widget.tareaAEditar;
    if (base != null) {
      return base.copyWith(
        titulo: _tituloController.text,
        descripcion: descripcion.isEmpty ? null : descripcion,
        fechaLimite: _fechaFinalActual,
        horasEstimadas: horas,
        urgenciaBase: _urgenciaBase,
        grupo: _grupoSeleccionado,
        subtareas: _subtareasTemp,
        tipoRecurrencia: _tipoRecurrencia,
        intervalo: _tipoRecurrencia == TipoRecurrencia.ninguna ? null : int.tryParse(_intervaloController.text.trim()),
      );
    }
    return Tarea(
      titulo: _tituloController.text,
      descripcion: descripcion.isEmpty ? null : descripcion,
      fechaLimite: _fechaFinalActual,
      horasEstimadas: horas,
      urgenciaBase: _urgenciaBase,
      grupo: _grupoSeleccionado,
      subtareas: _subtareasTemp,
      tipoRecurrencia: _tipoRecurrencia,
      intervalo: _tipoRecurrencia == TipoRecurrencia.ninguna ? null : int.tryParse(_intervaloController.text.trim()),
    );
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descripcionController.dispose();
    _horasController.dispose();
    _nuevaSubtareaController.dispose();
    _intervaloController.dispose();
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

  // Mismo patrón que home_screen.dart/gestor_rutinas_screen.dart: los avisos
  // llevan los colores del tema elegido en vez del color por defecto de
  // Flutter, para no verse "fuera de lugar" frente al resto de la app.
  void _avisar(String mensaje) {
    final tema = ref.read(temaProvider);
    mostrarSnackBarSimple(mensaje: mensaje, colorFondo: tema.colorPrincipal, colorTexto: tema.colorSobrePrincipal);
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

  // Guarda el estado actual del formulario (título, subtareas, grupo y
  // urgencia; NO fecha/horas, que son propias de cada ocasión) como una
  // plantilla reutilizable.
  Future<void> _guardarComoPlantilla() async {
    final titulo = _tituloController.text.trim();
    if (titulo.isEmpty) {
      _avisar('Escribe un título antes de guardar la plantilla');
      return;
    }

    final controller = TextEditingController(text: titulo);
    final nombre = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Guardar como plantilla'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nombre de la plantilla'),
          onSubmitted: (val) => Navigator.pop(dialogContext, val),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Guardar')),
        ],
      ),
    );

    final nombreLimpio = nombre?.trim();
    if (nombreLimpio == null || nombreLimpio.isEmpty) return;

    final plantilla = Plantilla(
      nombre: nombreLimpio,
      titulo: titulo,
      grupo: _grupoSeleccionado,
      urgenciaBase: _urgenciaMostrada,
      // Copiamos solo el texto: una plantilla siempre arranca "sin marcar".
      subtareas: _subtareasTemp.map((s) => ItemSubtarea(texto: s.texto)).toList(),
    );
    await ref.read(plantillaProvider.notifier).agregarPlantilla(plantilla);
    if (!mounted) return;
    _avisar('Plantilla "$nombreLimpio" guardada');
  }

  // Rellena el formulario con los datos de una plantilla guardada. La fecha,
  // hora, descripción y horas estimadas no se tocan: son propias de cada
  // ocasión y quedan tal como el usuario las haya dejado.
  void _aplicarPlantilla(Plantilla plantilla) {
    setState(() {
      _tituloController.text = plantilla.titulo;
      _grupoSeleccionado = plantilla.grupo;
      if (!_gruposDisponibles.contains(_grupoSeleccionado)) {
        _gruposDisponibles = [..._gruposDisponibles, _grupoSeleccionado];
      }
      _urgenciaBase = plantilla.urgenciaBase;
      _subtareasTemp = plantilla.subtareas.map((s) => ItemSubtarea(texto: s.texto)).toList();
      if (_subtareasTemp.isNotEmpty) _mostrarSubtareas = true;
    });
    _avisar('Plantilla "${plantilla.nombre}" aplicada');
  }

  // Selector de plantillas: tocar una fila la aplica al formulario actual y
  // cierra el diálogo. Solo para elegir; renombrar/eliminar vive en
  // _gestionarPlantillas (el lápiz).
  Future<void> _usarPlantilla() async {
    final plantillas = ref.read(plantillaProvider);
    if (plantillas.isEmpty) {
      _avisar('Todavía no tienes plantillas guardadas');
      return;
    }

    final plantillaElegida = await showDialog<Plantilla>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usar plantilla'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: plantillas.length,
            itemBuilder: (context, index) {
              final plantilla = plantillas[index];
              return ListTile(
                title: Text(plantilla.nombre),
                subtitle: Text(plantilla.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(dialogContext, plantilla),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        ],
      ),
    );

    if (plantillaElegida != null) _aplicarPlantilla(plantillaElegida);
  }

  // Diálogo para renombrar/eliminar plantillas existentes (mismo patrón que
  // "Editar grupos" en _gestionarGrupos). Aplicar una plantilla al
  // formulario se hace desde el botón "Usar plantilla", no desde acá.
  Future<void> _gestionarPlantillas() async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            final plantillas = ref.read(plantillaProvider);
            return AlertDialog(
              title: const Text('Editar plantillas'),
              content: SizedBox(
                width: double.maxFinite,
                child: plantillas.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Todavía no tienes plantillas guardadas.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: plantillas.length,
                        itemBuilder: (context, index) {
                          final plantilla = plantillas[index];
                          return ListTile(
                            title: Text(plantilla.nombre),
                            subtitle: Text(plantilla.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  tooltip: 'Renombrar',
                                  onPressed: () async {
                                    final renombreController = TextEditingController(text: plantilla.nombre);
                                    final nuevoNombre = await showDialog<String>(
                                      context: dialogContext,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Renombrar plantilla'),
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
                                    final nombreLimpio = nuevoNombre?.trim();
                                    if (nombreLimpio == null || nombreLimpio.isEmpty || nombreLimpio == plantilla.nombre) return;
                                    await ref.read(plantillaProvider.notifier).renombrarPlantilla(plantilla.id, nombreLimpio);
                                    setStateDialog(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                  tooltip: 'Eliminar',
                                  onPressed: () async {
                                    final confirmar = await showDialog<bool>(
                                      context: dialogContext,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Eliminar plantilla'),
                                        content: Text('¿Eliminar la plantilla "${plantilla.nombre}"?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
                                        ],
                                      ),
                                    );
                                    if (confirmar != true) return;
                                    await ref.read(plantillaProvider.notifier).eliminarPlantilla(plantilla.id);
                                    setStateDialog(() {});
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
      // Recurrencia solo tiene sentido con fecha límite (ver _guardarTarea).
      _tipoRecurrencia = TipoRecurrencia.ninguna;
      _intervaloController.clear();
    });
  }

  // Quita solo la hora. La fecha se conserva; al guardar, _guardarTarea usa
  // las 23:59 como hora límite implícita sin mostrarla en este botón.
  void _limpiarHora() {
    setState(() => _horaSeleccionada = null);
  }

  // Selector de recurrencia (ninguna/días/meses + intervalo numérico),
  // compartido entre portrait y landscape. Solo tiene sentido con fecha
  // límite elegida (ver _guardarTarea y _limpiarFecha); el llamador es
  // responsable de no mostrarlo sin _fechaSeleccionada.
  Widget _buildSelectorRecurrencia() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<TipoRecurrencia>(
            initialValue: _tipoRecurrencia,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black54),
            style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              labelText: 'Repetir',
              prefixIcon: const Icon(Icons.repeat, size: 20),
              filled: true, fillColor: Colors.grey.shade50,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5)),
            ),
            items: const [
              DropdownMenuItem(value: TipoRecurrencia.ninguna, child: Text('No se repite')),
              DropdownMenuItem(value: TipoRecurrencia.dias, child: Text('Cada N días')),
              DropdownMenuItem(value: TipoRecurrencia.meses, child: Text('Cada N meses')),
            ],
            onChanged: (valor) {
              if (valor != null) setState(() => _tipoRecurrencia = valor);
            },
          ),
        ),
        if (_tipoRecurrencia != TipoRecurrencia.ninguna) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _intervaloController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _tipoRecurrencia == TipoRecurrencia.dias ? 'Días' : 'Meses',
                errorText: _recurrenciaSinIntervalo ? 'Mínimo 1' : null,
                filled: true, fillColor: Colors.grey.shade50,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5)),
              ),
            ),
          ),
        ],
      ],
    );
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
  bool get _urgenciaAutomaticaPorHoras => double.tryParse(_horasController.text.trim()) != null;

  // Sin horas, pero con recurrencia + intervalo válido: la urgencia también
  // se calcula sola, en base a qué tan cerca está la fecha del próximo ciclo
  // (ver Tarea.urgencia). No hace falta chequear la fecha acá: el selector de
  // recurrencia solo aparece con _fechaSeleccionada ya elegida.
  bool get _urgenciaAutomaticaPorRecurrencia =>
      !_urgenciaAutomaticaPorHoras &&
      _tipoRecurrencia != TipoRecurrencia.ninguna &&
      int.tryParse(_intervaloController.text.trim()) != null;

  bool get _urgenciaEsAutomatica => _urgenciaAutomaticaPorHoras || _urgenciaAutomaticaPorRecurrencia;

  // Sin fecha límite, "horas estimadas" no tiene con qué calcular la urgencia
  // automática (Tarea.urgencia cae directo a urgenciaBase), así que no se
  // permite guardar hasta elegir una fecha o borrar las horas.
  bool get _horasSinFecha => _urgenciaAutomaticaPorHoras && _fechaSeleccionada == null;

  // Con recurrencia elegida (días o meses) hace falta un intervalo válido
  // (entero >= 1) para poder guardar.
  bool get _recurrenciaSinIntervalo {
    if (_tipoRecurrencia == TipoRecurrencia.ninguna) return false;
    final valor = int.tryParse(_intervaloController.text.trim());
    return valor == null || valor < 1;
  }

  int get _urgenciaMostrada {
    if (!_urgenciaEsAutomatica) return _urgenciaBase;

    final horas = double.tryParse(_horasController.text.trim());
    final tareaTemporal = Tarea(
      titulo: '',
      urgenciaBase: _urgenciaBase,
      fechaLimite: _fechaFinalActual,
      horasEstimadas: horas,
      tipoRecurrencia: _urgenciaAutomaticaPorRecurrencia ? _tipoRecurrencia : TipoRecurrencia.ninguna,
      intervalo: _urgenciaAutomaticaPorRecurrencia ? int.tryParse(_intervaloController.text.trim()) : null,
    );
    return tareaTemporal.urgencia;
  }

  void _guardarTarea() {
    final titulo = _tituloController.text.trim();

    if (titulo.isEmpty || _horasSinFecha || _recurrenciaSinIntervalo) return;

    final fechaFinal = _fechaFinalActual;

    // Convertimos el texto de horas a número (admite decimales, ej. "1.5")
    final double? horas = double.tryParse(_horasController.text.trim());
    final int urgenciaFinal = _urgenciaMostrada;
    final String descripcion = _descripcionController.text.trim();

    // El grupo ya viene sanitizado desde el desplegable; lo registramos
    // por si acaso para que no desaparezca en el futuro.
    final String grupoLimpio = _grupoSeleccionado;
    ref.read(tareaProvider.notifier).registrarGrupoPersistente(grupoLimpio);

    // Recurrencia solo tiene sentido con fecha límite: sin fecha, siempre
    // se guarda como "ninguna" sin importar lo que se haya elegido antes de
    // borrar la fecha. diaAncla se deriva del día de fechaFinal (no es un
    // control visible propio).
    final TipoRecurrencia tipoRecurrenciaFinal = fechaFinal == null ? TipoRecurrencia.ninguna : _tipoRecurrencia;
    final int? intervaloFinal = tipoRecurrenciaFinal == TipoRecurrencia.ninguna ? null : int.tryParse(_intervaloController.text.trim());
    final int? diaAnclaFinal = tipoRecurrenciaFinal == TipoRecurrencia.meses ? fechaFinal!.day : null;

    if (widget.tareaAEditar != null) {
      final tareaModificada = widget.tareaAEditar!.copyWith(
        titulo: titulo,
        descripcion: descripcion.isEmpty ? null : descripcion,
        fechaLimite: fechaFinal,
        horasEstimadas: horas,
        urgenciaBase: urgenciaFinal,
        grupo: grupoLimpio, // Usamos la variable ya limpia y sanitizada
        subtareas: _subtareasTemp,
        tipoRecurrencia: tipoRecurrenciaFinal,
        intervalo: intervaloFinal,
        diaAncla: diaAnclaFinal,
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
        tipoRecurrencia: tipoRecurrenciaFinal,
        intervalo: intervaloFinal,
        diaAncla: diaAnclaFinal,
      );
      ref.read(tareaProvider.notifier).addTarea(nuevaTarea);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Dos layouts completamente separados (no interpolación): mismo patrón
    // que home_screen.dart usa para decidir entre su Scaffold portrait y
    // _buildBodyLandscape. Portrait no se toca; landscape es un widget
    // nuevo que reutiliza el mismo estado y los mismos handlers.
    //
    // _reabriendoPorRotacion congela esta lectura en la orientación con la
    // que se abrió (_orientacionAlAbrir) en vez de volver a mirar
    // MediaQuery: apenas didChangeDependencies detecta la rotación, ESTE
    // build() también reacciona al mismo cambio de MediaQuery y, sin este
    // freeze, intenta dibujar el layout nuevo (p. ej. portrait) mientras la
    // instancia sigue montada dentro de su contenedor viejo (p. ej. el
    // MaterialPageRoute de landscape, que no trae su propio Material como
    // sí lo hace el BottomSheet) — eso es lo que tronaba con "No Material
    // widget found" en TextField/DropdownButton, ANTES de que el pop y el
    // reabrir programados en _reabrirTrasCambioDeOrientacion llegaran a
    // ejecutarse. Mientras se está por cerrar, sigue mostrando el layout
    // original hasta que la instancia nueva (ya en el contenedor correcto)
    // la reemplaza.
    // orientationOf (no MediaQuery.of(context).orientation) por la misma
    // razón que en didChangeDependencies: evita que el teclado abriéndose
    // dispare un rebuild completo de este formulario en cada frame.
    final bool esLandscape = _reabriendoPorRotacion
        ? _orientacionAlAbrir == Orientation.landscape
        : MediaQuery.orientationOf(context) == Orientation.landscape;
    return esLandscape ? _buildLandscape(context) : _buildPortrait(context);
  }

  Widget _buildPortrait(BuildContext context) {
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
                      'Subtareas: Pasos pequeños dentro de la tarea que puedes marcar como completados por separado. Está dentro de "Más opciones".',
                      'Plantillas: Para tareas que repites seguido (pero no todos los días). También dentro de "Más opciones". Guarda el título, las subtareas, el grupo y la urgencia con "Guardar como plantilla"; usa "Usar plantilla" para aplicar una ya guardada (puedes seguir ajustando cualquier campo a mano después); y el lápiz para renombrarlas o eliminarlas.',
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _tituloController,
              textCapitalization: TextCapitalization.sentences,
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
                _BotonAccionCuadrado(
                  icon: Icons.add_rounded,
                  tooltip: 'Nuevo grupo',
                  onPressed: _crearNuevoGrupo,
                ),
                const SizedBox(width: 8),
                _BotonAccionCuadrado(
                  icon: Icons.edit_rounded,
                  tooltip: 'Editar grupos',
                  onPressed: _gestionarGrupos,
                ),
              ],
            ),
            // --- FIN DEL CAMPO DE GRUPO ---

            // Fecha/Hora (y, con fecha elegida, Recurrencia) viven fuera del
            // toggle "Más opciones": a diferencia de Descripción/Subtareas/
            // Plantillas (secundarias, colapsadas por defecto), la fecha
            // límite es un dato de primer nivel que antes solo aparecía tras
            // expandir "Más opciones" — invisible por defecto en creación
            // (sin datos previos que la auto-expandan, a diferencia de
            // editar una tarea que ya trae fechaLimite). Mostrarla siempre
            // deja creación y edición con el mismo número de pasos para
            // llegar a Recurrencia.
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _elegirFecha,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_fechaSeleccionada == null ? 'Fecha' : DateFormat('dd MMM').format(_fechaSeleccionada!)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
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
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
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
            if (_fechaSeleccionada != null) ...[
              const SizedBox(height: 16),
              _buildSelectorRecurrencia(),
            ],

            if (_mostrarAvanzadas) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _descripcionController,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Descripción',
                  filled: true, fillColor: Colors.grey.shade50,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5)),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Text(
              _urgenciaAutomaticaPorHoras
                  ? 'Urgencia (automática por horas estimadas)'
                  : _urgenciaAutomaticaPorRecurrencia
                      ? 'Urgencia (automática por repetición)'
                      : 'Urgencia Manual / Base',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Opacity(
              opacity: _urgenciaEsAutomatica ? 0.5 : 1.0,
              child: SegmentedButton<int>(
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                ),
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

            // Subtareas y Plantillas viven dentro de "Más opciones": son
            // funciones secundarias que no todas las tareas necesitan, así
            // que no ocupan espacio en el formulario simple por defecto.
            // Con AnimatedSize (mismo patrón que ya usa Subtareas más abajo)
            // el bloque completo aparece con una animación de ~250ms en vez
            // de saltar de golpe: al mover Subtareas y Plantillas adentro de
            // "Más opciones" el salto instantáneo se volvió bastante más
            // grande (más widgets aparecen en el mismo frame) y se sentía
            // como un tirón al tocar el botón.
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: !_mostrarAvanzadas
                  ? const SizedBox(width: double.infinity, height: 0)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
              // --- SECCIÓN DE SUBTAREAS (COLAPSABLE) ---
              const SizedBox(height: 16),
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
                                  textCapitalization: TextCapitalization.sentences,
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

              // --- SECCIÓN DE PLANTILLAS ---
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _guardarComoPlantilla,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                      label: const Text(
                        'Guardar como plantilla',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: Colors.grey.shade400, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _usarPlantilla,
                      icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                      label: const Text(
                        'Usar plantilla',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: Colors.grey.shade400, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BotonAccionCuadrado(
                    icon: Icons.edit_rounded,
                    tooltip: 'Editar plantillas',
                    onPressed: _gestionarPlantillas,
                  ),
                ],
              ),
              // --- FIN DE LA SECCIÓN DE PLANTILLAS ---
                      ],
                    ),
            ),

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: (_horasSinFecha || _recurrenciaSinIntervalo) ? null : _guardarTarea,
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
                label: const Text('Más opciones (Descripción y Esfuerzo)'),
              ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // LAYOUT HORIZONTAL (landscape): dos columnas + riel de subtareas fijo a
  // la derecha, en vez del formulario vertical de una sola columna con
  // "Más opciones" colapsado. Reutiliza exactamente los mismos
  // controllers/handlers/providers que _buildPortrait — no hay estado
  // nuevo. A diferencia de portrait, acá descripción/fecha/hora/horas
  // estimadas/plantillas se muestran siempre (sin el toggle "Más
  // opciones": con dos columnas de espacio no tiene sentido esconderlas).
  // =====================================================================

  Widget _buildLandscape(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // false a propósito: con resize automático, el teclado empuja/encoge
      // todo el body y con él el pie fijo de cada columna (Fecha/Hora,
      // Plantillas, Guardar/Cancelar) — pedido explícito del usuario: esos
      // botones deben quedarse exactamente donde están, sin moverse por el
      // teclado. Que el título/descripción y "Agregar paso" sigan visibles
      // por encima del teclado ya NO depende de este flag: cada columna lo
      // resuelve por su cuenta acotando solo su propio scroll de texto (ver
      // los Builder dentro de _buildColumnaIzquierdaLandscape y
      // _buildColumnaSubtareasLandscape).
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 6, 28, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mismo flex en las 3 (tercio de pantalla cada una), en vez de
              // los anchos dispares de antes (4 / 5 / fijo 260) que dejaban
              // a Subtareas visiblemente más angosta que las otras dos.
              Expanded(child: _buildColumnaIzquierdaLandscape(context)),
              const SizedBox(width: 24),
              Expanded(child: _buildColumnaCentralLandscape(context)),
              const SizedBox(width: 20),
              Container(width: 1, color: Colors.grey.shade300),
              const SizedBox(width: 20),
              Expanded(child: _buildColumnaSubtareasLandscape(context)),
            ],
          ),
        ),
      ),
    );
  }

  // Columna izquierda: título de la pantalla + ayuda, campo de título de
  // tarea y descripción arriba (en su propio scroll), Fecha/Hora SIEMPRE
  // fijos exactamente al pie (Stack + Positioned, no Expanded/Flexible): a
  // diferencia del reparto por flex que se probó antes, acá Fecha/Hora no
  // "flota" a una altura que depende de cuánto espacio sobre — su posición
  // es siempre la misma, pegada al borde inferior. La forma del árbol es
  // SIEMPRE la misma (nunca cambia según el teclado), porque alternar entre
  // dos formas distintas hacía que Flutter destruyera y recreara el
  // TextField (perdiendo el foco) apenas el teclado empezaba a abrirse. Si
  // el teclado deja muy poco alto, Stack recorta (clipea) el contenido en
  // vez de tirar un "RenderFlex overflow".
  Widget _buildColumnaIzquierdaLandscape(BuildContext context) {
    // Encabezado ("Nueva Tarea" + ayuda) separado del contenido con scroll:
    // viviendo dentro del SingleChildScrollView, el auto-scroll que trae el
    // campo enfocado por encima del teclado podía desplazar este encabezado
    // fuera de vista, dejando un hueco blanco donde estaba. Al ser un
    // Positioned fijo aparte, nunca se desplaza y ese hueco no aparece.
    final Widget encabezado = Row(
      children: [
        Text(
          widget.tareaAEditar != null ? 'Editar Tarea' : 'Nueva Tarea',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        const SizedBox(width: 8),
        AyudaFormularioButton(
          titulo: 'Ayuda: Nueva Tarea',
          puntos: const [
            '¿Qué hay que hacer?: Título de la tarea, es obligatorio.',
            'Grupo: Categoría para organizar tus tareas (ej. Trabajo, Casa). Elige una del listado; usa el ícono "+" para crear una nueva y el lápiz para renombrar o eliminar las existentes.',
            'Descripción: Notas adicionales opcionales sobre la tarea.',
            'Fecha y Hora: Fecha límite para completarla. Si no eliges hora, se usa las 23:59 por defecto.',
            'Urgencia: Qué tan prioritaria es. Si defines horas estimadas, se calcula sola según el tiempo restante.',
            'Horas estimadas: Tiempo que crees que tomará. Al definirlas, la urgencia deja de elegirse manualmente.',
            'Subtareas: Pasos pequeños dentro de la tarea que puedes marcar como completados por separado.',
            'Plantillas: Para tareas que repites seguido (pero no todos los días). Guarda el título, las subtareas, el grupo y la urgencia con "Guardar como plantilla"; usa "Usar plantilla" para aplicar una ya guardada; y el lápiz para renombrarlas o eliminarlas.',
          ],
        ),
      ],
    );

    final Widget tituloYDescripcion = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _tituloController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: '¿Qué hay que hacer?',
            filled: true, fillColor: Colors.grey.shade100,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400, width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black87, width: 2.0)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descripcionController,
          minLines: 3,
          maxLines: 5,
          textAlignVertical: TextAlignVertical.top,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Descripción',
            alignLabelWithHint: true,
            filled: true, fillColor: Colors.grey.shade50,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5)),
          ),
        ),
      ],
    );

    // Antes vivían acá los botones de Plantillas; se movieron al riel de la
    // derecha (arriba de Guardar/Cancelar) y Fecha/Hora (que antes estaban
    // en la columna central) ocuparon su lugar.
    final Widget fechaYHora = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _elegirFecha,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_fechaSeleccionada == null ? 'Fecha' : DateFormat('dd MMM').format(_fechaSeleccionada!), maxLines: 1),
            ),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), visualDensity: VisualDensity.compact),
          ),
        ),
        if (_fechaSeleccionada != null)
          IconButton(onPressed: _limpiarFecha, icon: const Icon(Icons.close, size: 18), tooltip: 'Quitar fecha', visualDensity: VisualDensity.compact),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _elegirHora,
            icon: const Icon(Icons.access_time, size: 16),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_horaSeleccionada == null ? 'Hora' : _horaSeleccionada!.format(context), maxLines: 1),
            ),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), visualDensity: VisualDensity.compact),
          ),
        ),
        if (_horaSeleccionada != null)
          IconButton(onPressed: _limpiarHora, icon: const Icon(Icons.close, size: 18), tooltip: 'Quitar hora', visualDensity: VisualDensity.compact),
      ],
    );

    return Stack(
      children: [
        // Encabezado fijo (48 ≈ alto del IconButton de ayuda, el más alto
        // de la fila): nunca se mueve ni se desplaza, así que no puede
        // dejar un hueco en blanco donde estaba.
        Positioned(top: 0, left: 0, right: 0, height: 48, child: encabezado),
        // top+bottom fijos (68 = 48 del encabezado + 20 de separación, 60
        // para Fecha/Hora): el padding extra que antes se sumaba acá para
        // encoger este scroll según el alto del teclado dejaba un hueco en
        // blanco visible entre Descripción y Fecha/Hora — se quita, a
        // costa de que el campo enfocado ya no se auto-ajusta al alto
        // exacto del teclado (pedido explícito del usuario).
        Positioned(
          top: 68, left: 0, right: 0, bottom: 60,
          child: SingleChildScrollView(child: tituloYDescripcion),
        ),
        // Nunca depende de MediaQuery/teclado, así que jamás se mueve por
        // él — pedido explícito del usuario.
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: ColoredBox(color: Colors.white, child: fechaYHora),
        ),
      ],
    );
  }

  // Columna central: grupo, fecha/hora, urgencia manual/base y horas
  // estimadas — siempre visibles, sin el toggle "Más opciones" de portrait.
  Widget _buildColumnaCentralLandscape(BuildContext context) {
    final tema = ref.watch(temaProvider);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _grupoSeleccionado,
            isExpanded: true,
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
                DropdownMenuItem(value: grupo, child: Text(grupo, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (valor) {
              if (valor != null) setState(() => _grupoSeleccionado = valor);
            },
          ),
          const SizedBox(height: 16),
          // Antes vivían acá Fecha/Hora (movidos a la columna izquierda);
          // estos dos botones ocupan su lugar, relocalizados desde la fila
          // del desplegable de Grupo de arriba.
          Row(
            children: [
              _BotonAccionCuadrado(icon: Icons.add_rounded, tooltip: 'Nuevo grupo', onPressed: _crearNuevoGrupo),
              const SizedBox(width: 8),
              _BotonAccionCuadrado(icon: Icons.edit_rounded, tooltip: 'Editar grupos', onPressed: _gestionarGrupos),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            _urgenciaAutomaticaPorHoras
                ? 'Urgencia (automática por horas estimadas)'
                : _urgenciaAutomaticaPorRecurrencia
                    ? 'Urgencia (automática por repetición)'
                    : 'Urgencia Manual / Base',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: _urgenciaEsAutomatica ? 0.5 : 1.0,
            child: SegmentedButton<int>(
              // Sin el check de selección: en 4 segmentos angostos ese ícono
              // le robaba casi todo el ancho al texto, obligando a
              // FittedBox a encogerlo hasta ilegible. El nivel elegido se
              // distingue ahora por el relleno con el color del tema.
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                selectedBackgroundColor: tema.colorPrincipal,
                selectedForegroundColor: tema.colorSobrePrincipal,
              ),
              segments: const [
                ButtonSegment(value: 1, label: FittedBox(fit: BoxFit.scaleDown, child: Text('Bajo', maxLines: 1))),
                ButtonSegment(value: 2, label: FittedBox(fit: BoxFit.scaleDown, child: Text('Medio', maxLines: 1))),
                ButtonSegment(value: 3, label: FittedBox(fit: BoxFit.scaleDown, child: Text('Alto', maxLines: 1))),
                ButtonSegment(value: 4, label: FittedBox(fit: BoxFit.scaleDown, child: Text('Muy alto', maxLines: 1))),
              ],
              selected: {_urgenciaMostrada},
              onSelectionChanged: _urgenciaEsAutomatica ? null : (Set<int> sel) => setState(() => _urgenciaBase = sel.first),
            ),
          ),
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
          if (_fechaSeleccionada != null) ...[
            const SizedBox(height: 16),
            _buildSelectorRecurrencia(),
          ],
        ],
      ),
    );
  }

  // Riel derecho: subtareas arriba (su propio scroll) y, fijos SIEMPRE al
  // pie (Stack + Positioned, mismo criterio que _buildColumnaIzquierdaLandscape
  // — ver ese comentario), Plantillas + Guardar/Cancelar. Su posición no
  // depende de cuánto contenido tenga Subtareas ni de cuánto espacio sobre:
  // siempre pegados al borde inferior. Forma de árbol fija (nunca cambia
  // según el teclado) para no perder el foco del campo "Agregar paso"; si el
  // teclado deja muy poco alto, Stack recorta en vez de desbordar.
  Widget _buildColumnaSubtareasLandscape(BuildContext context) {
    final Widget subtareasContenido = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _mostrarSubtareas = !_mostrarSubtareas),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.checklist_rounded, size: 18, color: Colors.black54),
                  const SizedBox(width: 8),
                  const Text('SUBTAREAS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5)),
                  if (_subtareasTemp.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        '${_subtareasTemp.length}',
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
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_mostrarSubtareas
                ? const SizedBox(width: double.infinity, height: 0)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                                      child: const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.drag_indicator, size: 20, color: Colors.black26)),
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
                              textCapitalization: TextCapitalization.sentences,
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
                          IconButton(icon: const Icon(Icons.add_circle, size: 28, color: Colors.black87), onPressed: _agregarSubtareaTemp),
                        ],
                      ),
                    ],
                  ),
          ),
      ],
    );

    // Movidas acá desde la columna izquierda, arriba de Guardar/Cancelar. El
    // botón de editar plantillas se quita de momento (sin reemplazo aún
    // visible en este layout).
    final Widget botonesPie = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _guardarComoPlantilla,
          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          label: const Text('Guardar plantilla', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: Colors.grey.shade400, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _usarPlantilla,
          icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
          label: const Text('Usar plantilla', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: Colors.grey.shade400, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: (_horasSinFecha || _recurrenciaSinIntervalo) ? null : _guardarTarea,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Guardar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );

    return Stack(
      children: [
        // El padding extra que antes se sumaba acá para encoger este scroll
        // según el alto del teclado dejaba un hueco en blanco visible entre
        // Subtareas y Guardar/Cancelar — se quita (mismo ajuste que ya se
        // hizo en _buildColumnaIzquierdaLandscape).
        Positioned(
          top: 0, left: 0, right: 0, bottom: 168,
          child: SingleChildScrollView(child: subtareasContenido),
        ),
        // Nunca depende de MediaQuery/teclado, así que jamás se mueve por
        // él — pedido explícito del usuario.
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: ColoredBox(color: Colors.white, child: botonesPie),
        ),
      ],
    );
  }
}

// Botón cuadrado junto al desplegable de grupo (crear / editar grupos) y a
// la fila de plantillas (editar plantillas), con el mismo trazo y radio que
// los campos de texto del formulario.
class _BotonAccionCuadrado extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _BotonAccionCuadrado({
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
            width: 44, height: 44,
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
