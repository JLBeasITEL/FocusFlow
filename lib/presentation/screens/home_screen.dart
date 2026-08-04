import 'package:app_tareas/presentation/screens/gestor_rutinas_screen.dart';
import 'package:app_tareas/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart'; // Necesario para guardado offline

import '../../providers/tarea_provider.dart';
import '../../models/tarea.dart';
import '../../models/nota.dart';
import '../../providers/nota_provider.dart';
import '../widgets/add_tarea_modal.dart';
import '../widgets/ayuda_formulario_button.dart';
import '../../providers/rutina_provider.dart';
import '../widgets/rutina_card.dart';
import 'rutina_form_screen.dart';
import '../../providers/tema_provider.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'dart:async';
import '../widgets/onboarding_permisos.dart';
import '../../services/notificaciones_service.dart';
import '../widgets/progreso_rutinas_bar.dart';
import '../../core/app_messenger.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0; 
  //Memoria de los grupos que el usuario ha minimizado
  final Set<String> _gruposColapsados = {};
  
  // Paleta de 12 colores pastel
  final List<Color> _coloresPostIt = [
    const Color(0xFFFEF08A), const Color(0xFFFFF7D1),
    const Color(0xFFFECACA), const Color(0xFFFBCFE8),
    const Color(0xFFBFDBFE), const Color(0xFFBAE6FD),
    const Color(0xFFBBF7D0), const Color(0xFFA7F3D0),
    const Color(0xFFE9D5FF), const Color(0xFFDDD6FE),
    const Color(0xFFFED7AA), const Color(0xFFCCFBF1),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    _tabController.animation?.addListener(() {
      final int proximoIndex = _tabController.animation!.value.round();
      if (_currentIndex != proximoIndex) {
        setState(() => _currentIndex = proximoIndex);
      }
    });

    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _currentIndex != _tabController.index) {
        setState(() => _currentIndex = _tabController.index);
      }
    });

    // Nota: Si este método solo pedía lo de la batería, eventualmente podrías 
    // borrarlo, ya que el nuevo Onboarding lo pide en el "Paso 2". 
    // Por ahora lo puedes dejar sin problemas.
    _solicitarPermisosDeBateria();

    // --- SINCRONIZACIÓN AUTOMÁTICA AL ABRIR LA APP ---
    // addPostFrameCallback espera a que se dibuje el primer frame antes de ejecutar
    // esta función, para asegurarnos de que el árbol de widgets (y el context) ya existen.
    WidgetsBinding.instance.addPostFrameCallback((_) async { 
      // 1. LIMPIEZA NUCLEAR (Ejecución Única)
      // Esto cancela TODAS las alarmas/notificaciones que existan en el sistema Android
      // (cancelAll), pero SOLO la primera vez que el usuario abre la app después de
      // instalar este fix. Usamos una bandera guardada en SharedPreferences
      // ("fantasmas_borrados") para no repetir esta limpieza en cada apertura.
      final prefs = await SharedPreferences.getInstance();
      final borrado = prefs.getBool('fantasmas_borrados') ?? false;
      
      if (!borrado) {
        await NotificacionesService().limpiarTodasLasAlarmasDelSistema();
        await prefs.setBool('fantasmas_borrados', true);
        print('🧹 Limpieza nuclear ejecutada por única vez');
      }

      // ============================================================
      // FIX APLICADO: se eliminó la llamada a
      // ref.read(rutinaProvider.notifier).resincronizarTodasLasAlarmas();
      //
      // Motivo: RutinaNotifier.build() (en rutina_provider.dart) YA ejecuta
      // _cargarRutinas() automáticamente en cuanto el provider se crea al
      // abrir la app, y _cargarRutinas() ya reprograma las notificaciones
      // de todas las rutinas activas por su cuenta.
      //
      // Antes de este fix, este archivo llamaba OTRA VEZ a esa misma lógica
      // (resincronizarTodasLasAlarmas), lo que generaba dos procesos
      // corriendo en paralelo, cancelando y reprogramando las MISMAS
      // notificaciones al mismo tiempo. Esta condición de carrera podía
      // dejar alarmas "fantasma" o duplicadas cada vez que se abría la app,
      // incluso sin crear, editar, ni marcar ninguna rutina como completa.
      // ============================================================

      // 2. LIMPIEZA DE TAREAS: Borra las completadas de ayer
      ref.read(tareaProvider.notifier).limpiarTareasCompletadasAlCambiarDeDia();

      // 3. Lanzar el Onboarding interactivo de permisos
      // (Se retrasa 500ms para no interrumpir la animación de entrada de la app)
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          OnboardingPermisos.verificarYMostrar(context);
        }
      });
    });
  }

  // --- FUNCIÓN DE RESPALDO ANTI-BORRADO ---
  /*void _resincronizarRutinasSilenciosamente() {
    // 1. Leemos todas las rutinas de la memoria mediante Riverpod
    final rutinas = ref.read(rutinaProvider);
    
    // 2. Filtramos solo las que el usuario dejó encendidas (activas)
    final rutinasActivas = rutinas.where((r) => r.activa).toList();

    // 3. Reprogramamos las alarmas en el sistema Android
    for (var rutina in rutinasActivas) {
       // OJO: Aquí debes descomentar y ajustar la siguiente línea según 
       // cómo se llame la función que usas normalmente para programar alarmas:
       
       // NotificacionesService().programarRutina(rutina);
       
       print('🔄 Resincronizando rutina silenciosamente: ${rutina.titulo}');
    }
  } */

  // Solicita al sistema operativo los 3 permisos críticos para que las alarmas
  // de rutinas suenen de forma confiable: notificaciones, ignorar optimización
  // de batería (para que Android no "duerma" la app) y alarmas exactas.
  Future<void> _solicitarPermisosDeBateria() async {
    if (await Permission.notification.isDenied) await Permission.notification.request();
    if (await Permission.ignoreBatteryOptimizations.isDenied) await Permission.ignoreBatteryOptimizations.request();
    if (await Permission.scheduleExactAlarm.isDenied) await Permission.scheduleExactAlarm.request();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _labelOrden(TipoOrden tipo) {
    switch (tipo) {
      case TipoOrden.creacion:
        return 'Original';
      case TipoOrden.alfabetico:
        return 'Alfabético (A-Z)';
      case TipoOrden.urgencia:
        return 'Mayor urgencia';
      case TipoOrden.fecha:
        return 'Próximas a vencer';
    }
  }

  // --- VISTA DE NOTAS ESTILO TABLERO ---
  Widget _buildTabNotas(Color colorPrincipal, List<NotaPostIt> notasActuales) {
    if (notasActuales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            //Icon(Icons.sticky_note_2_outlined, size: 80, color: colorPrincipal.withValues(alpha: 0.2)),
            const SizedBox(height: 250),
            Text('Tu tablero está vacío.', style: TextStyle(color: colorPrincipal.withValues(alpha: 0.6), fontSize: 16)),
            Text('Agrega un post-it rápido.', style: TextStyle(color: colorPrincipal.withValues(alpha: 0.4), fontSize: 14)),
          ],
        ),
      );
    }

    int columnas = math.sqrt(notasActuales.length).ceil();
    if (columnas < 2) columnas = 2;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnas,
        crossAxisSpacing: 12,     
        mainAxisSpacing: 12,      
        childAspectRatio: 1.0,    
      ),
      itemCount: notasActuales.length,
      itemBuilder: (context, index) {
        final nota = notasActuales[index];
        return PostItCard(
          key: ValueKey(nota.id),
          nota: nota,
          index: index,
          columnasTotales: columnas,
          onTapEditar: () => _mostrarDialogoNota(indexAEditar: index),
          onDelete: () => _eliminarNota(nota),
        );
      },
    );
  }

  // Captura el notifier ANTES de mostrar el SnackBar: el callback de
  // "Deshacer" corre en diferido (hasta 5s después) y para entonces este
  // widget puede haberse reconstruido varias veces, así que no debe
  // depender de "ref" ni de "context" capturados en ese momento futuro.
  void _eliminarNota(NotaPostIt nota) {
    final notifier = ref.read(notaProvider.notifier);
    final datos = notifier.eliminarConDeshacer(nota.id);
    if (datos == null) return;
    final tema = ref.read(temaProvider);
    mostrarSnackBarDeshacer(
      mensaje: 'Nota eliminada',
      onDeshacer: () => notifier.restaurar(datos.elemento, datos.indice),
      colorFondo: tema.colorPrincipal,
      colorTexto: tema.colorSobrePrincipal,
    );
  }

  void _mostrarDialogoNota({int? indexAEditar}) {
    final List<NotaPostIt> notasActuales = ref.read(notaProvider);
    final bool esNueva = indexAEditar == null;
    final NotaPostIt? notaActual = esNueva ? null : notasActuales[indexAEditar];
    
    final controller = TextEditingController(text: esNueva ? '' : notaActual!.texto);
    // Usa tu paleta nativa del archivo original
    Color colorDialogo = esNueva ? const Color(0xFFFDFBF7) : Color(notaActual!.colorValue);
    // null = color aleatorio (solo aplica a notas nuevas); si el usuario elige uno manualmente, se guarda aquí.
    int? colorElegido = esNueva ? null : notaActual!.colorValue;

    bool modoEdicion = esNueva;
    TipoNota tipoActual = esNueva ? TipoNota.texto : notaActual!.tipo;
    
    List<ItemLista> itemsTemp = esNueva 
        ? [] 
        : notaActual!.elementosLista.map((e) => ItemLista(texto: e.texto, completado: e.completado)).toList();
    
    List<TextEditingController> controllersLista = itemsTemp.map((e) => TextEditingController(text: e.texto)).toList();
    List<FocusNode> focusNodesLista = itemsTemp.map((e) => FocusNode()).toList();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withOpacity(0.6), 
      transitionDuration: const Duration(milliseconds: 400), 
      pageBuilder: (context, animation, secondaryAnimation) {
        
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Center(
              child: SingleChildScrollView(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    clipBehavior: Clip.antiAlias, 
                    decoration: BoxDecoration(
                      color: colorDialogo,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8), topRight: Radius.circular(8),
                        bottomLeft: Radius.circular(8), bottomRight: Radius.circular(40), 
                      ),
                    ),
                    child: CustomPaint(
                      painter: HojaLibretaPainter(),
                      child: Stack(
                        children: [
                          
                          // ÁREA DE CONTENIDO (TEXTO O LISTA)
                          Padding(
                            padding: const EdgeInsets.only(top: 64.0, left: 54.0, right: 16.0, bottom: 80.0),
                            child: tipoActual == TipoNota.texto 
                              ? (modoEdicion
                                  ? TextField(
                                      controller: controller,
                                      autofocus: true, 
                                      maxLines: 8, minLines: 3,
                                      style: const TextStyle(fontSize: 20, color: Colors.black87, fontWeight: FontWeight.w500, height: 1.4),
                                      decoration: const InputDecoration(hintText: 'Escribe tu idea...', border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                                    )
                                  : Text(notaActual!.texto, style: const TextStyle(fontSize: 20, color: Colors.black87, fontWeight: FontWeight.w500, height: 1.4))
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (int i = 0; i < itemsTemp.length; i++)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              height: 24, width: 24,
                                              child: Checkbox(
                                                value: itemsTemp[i].completado,
                                                activeColor: Colors.black87,
                                                onChanged: (val) {
                                                  setStateDialog(() => itemsTemp[i].completado = val!);
                                                  if (!modoEdicion && !esNueva) {
                                                    ref.read(notaProvider.notifier).editarNota(
                                                      notaActual!.id, 
                                                      notaActual.texto, 
                                                      tipo: tipoActual, 
                                                      elementosLista: itemsTemp
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: modoEdicion
                                                ? TextField(
                                                    controller: controllersLista[i],
                                                    focusNode: focusNodesLista[i],
                                                    onChanged: (val) => itemsTemp[i].texto = val,
                                                    textInputAction: TextInputAction.next, // Configura el botón del teclado como "Siguiente"
                                                    onSubmitted: (val) {
                                                      // Si el usuario presiona Enter estando en el último elemento de la lista, crea uno nuevo automáticamente
                                                      if (i == itemsTemp.length - 1) {
                                                        final nuevoFocusNode = FocusNode();
                                                        setStateDialog(() {
                                                          itemsTemp.add(ItemLista(texto: ''));
                                                          controllersLista.add(TextEditingController());
                                                          focusNodesLista.add(nuevoFocusNode);
                                                        });
                                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                                          nuevoFocusNode.requestFocus();
                                                        });
                                                      } else {
                                                        focusNodesLista[i + 1].requestFocus();
                                                      }
                                                    },
                                                    style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.w500),
                                                    decoration: const InputDecoration(hintText: 'Elemento...', border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                                                  )
                                                : Text(
                                                    itemsTemp[i].texto,
                                                    style: TextStyle(
                                                      fontSize: 18, fontWeight: FontWeight.w500,
                                                      color: itemsTemp[i].completado ? Colors.black38 : Colors.black87,
                                                      decoration: itemsTemp[i].completado ? TextDecoration.lineThrough : null,
                                                    ),
                                                  ),
                                            ),
                                            if (modoEdicion)
                                              GestureDetector(
                                                onTap: () => setStateDialog(() { itemsTemp.removeAt(i); controllersLista.removeAt(i); focusNodesLista.removeAt(i); }),
                                                child: const Icon(Icons.close, size: 20, color: Colors.black38),
                                              )
                                          ],
                                        ),
                                      ),
                                    if (modoEdicion)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: InkWell(
                                          onTap: () {
                                            final nuevoFocusNode = FocusNode();
                                            setStateDialog(() {
                                              itemsTemp.add(ItemLista(texto: ''));
                                              controllersLista.add(TextEditingController());
                                              focusNodesLista.add(nuevoFocusNode);
                                            });
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              nuevoFocusNode.requestFocus();
                                            });
                                          },
                                          child: const Row(children: [Icon(Icons.add, color: Colors.black54), SizedBox(width: 8), Text('Agregar elemento', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold))]),
                                        ),
                                      )
                                  ],
                                ),
                          ),

                          // BOTONES EN ESQUINA SUPERIOR DERECHA
                          Positioned(
                            top: 8, right: 8,
                            child: Row(
                              children: [
                                AyudaFormularioButton(
                                  titulo: 'Ayuda: Nota',
                                  color: Colors.black54,
                                  puntos: const [
                                    'Texto: Escribe libremente tus ideas o pendientes.',
                                    'Convertir en Lista/Texto: El botón con las líneas cambia entre modo texto libre y modo lista de compras.',
                                    'Lista de compras: Agrega elementos con casillas que puedes marcar como completados.',
                                    'Lápiz: Permite editar una nota ya guardada.',
                                    'Color: Usa el ícono de paleta para elegir un color. Si no eliges ninguno, la nota nueva recibe uno aleatorio tipo post-it.',
                                  ],
                                ),
                                // SELECTOR DE COLOR (SIEMPRE VISIBLE, EN EDICIÓN Y EN VISTA PREVIA)
                                // Si el usuario no elige nada, se conserva el comportamiento
                                // original: color aleatorio para notas nuevas, o el color ya
                                // asignado para notas existentes.
                                IconButton(
                                    icon: const Icon(Icons.palette_outlined, color: Colors.black54),
                                    tooltip: 'Elegir color',
                                    onPressed: () async {
                                      final Color? seleccion = await showDialog<Color>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('Color de la nota'),
                                          content: Wrap(
                                            spacing: 12,
                                            runSpacing: 12,
                                            children: [
                                              for (final opcion in _coloresPostIt)
                                                GestureDetector(
                                                  onTap: () => Navigator.pop(dialogContext, opcion),
                                                  child: Container(
                                                    width: 36, height: 36,
                                                    decoration: BoxDecoration(
                                                      color: opcion,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: colorElegido == opcion.value ? Colors.black87 : Colors.black12,
                                                        width: colorElegido == opcion.value ? 2.5 : 1,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              // "Aleatorio" solo tiene sentido si la nota aún no tiene un color fijo (nota nueva)
                                              if (esNueva)
                                                GestureDetector(
                                                  onTap: () => Navigator.pop(dialogContext, const Color(0x00000000)),
                                                  child: Container(
                                                    width: 36, height: 36,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: colorElegido == null ? Colors.black87 : Colors.black12, width: colorElegido == null ? 2.5 : 1),
                                                      gradient: const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.red]),
                                                    ),
                                                    child: const Icon(Icons.shuffle_rounded, size: 16, color: Colors.white),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
                                          ],
                                        ),
                                      );

                                      if (seleccion == null) return; // Se cerró sin elegir
                                      setStateDialog(() {
                                        if (seleccion.value == 0x00000000) {
                                          // Opción "Aleatorio"
                                          colorElegido = null;
                                          colorDialogo = const Color(0xFFFDFBF7);
                                        } else {
                                          colorElegido = seleccion.value;
                                          colorDialogo = seleccion;
                                        }
                                      });

                                      // Fuera del modo edición (nota ya guardada en vista previa)
                                      // no hay botón "Guardar" visible, así que persistimos de una vez.
                                      if (!modoEdicion && !esNueva) {
                                        ref.read(notaProvider.notifier).editarNota(
                                          notaActual!.id, notaActual.texto,
                                          tipo: notaActual.tipo,
                                          elementosLista: notaActual.elementosLista,
                                          colorValue: colorElegido,
                                        );
                                      }
                                    },
                                  ),
                                // BOTÓN SOLICITADO: 3 bolitas en vertical y líneas paralelas (Icons.format_list_bulleted)
                                // Se muestra únicamente cuando el usuario está en modo de edición
                                if (modoEdicion)
                                  IconButton(
                                    icon: Icon(tipoActual == TipoNota.texto ? Icons.format_list_bulleted : Icons.notes_rounded, color: Colors.black54),
                                    tooltip: tipoActual == TipoNota.texto ? 'Convertir en Lista de Compras' : 'Convertir en Texto Libre',
                                    onPressed: () {
                                      setStateDialog(() {
                                        if (tipoActual == TipoNota.texto) {
                                          tipoActual = TipoNota.lista;
                                          if (itemsTemp.isEmpty && controller.text.trim().isNotEmpty) {
                                            final lineas = controller.text.split('\n').where((l) => l.trim().isNotEmpty);
                                            for (var linea in lineas) {
                                              itemsTemp.add(ItemLista(texto: linea.trim()));
                                              controllersLista.add(TextEditingController(text: linea.trim()));
                                              focusNodesLista.add(FocusNode());
                                            }
                                          } else if (itemsTemp.isEmpty) {
                                            itemsTemp.add(ItemLista(texto: ''));
                                            controllersLista.add(TextEditingController());
                                            focusNodesLista.add(FocusNode());
                                          }
                                        } else {
                                          tipoActual = TipoNota.texto;
                                          if (itemsTemp.isNotEmpty) {
                                            controller.text = itemsTemp.map((e) => e.texto).join('\n');
                                          }
                                        }
                                      });
                                    },
                                  ),
                                
                                // ICONO DE LÁPIZ (SOLO EN MODO PREVIEW EN NOTAS EXISTENTES)
                                if (!esNueva && !modoEdicion)
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, color: Colors.black54), 
                                    onPressed: () => setStateDialog(() => modoEdicion = true)
                                  ),
                              ],
                            ),
                          ),

                          // BOTONES INFERIORES (CANCELAR / GUARDAR)
                          Positioned(
                            bottom: 16, right: 16,
                            child: Row(
                              children: [
                                TextButton(
                                  onPressed: () {
                                    if (modoEdicion && !esNueva) {
                                      setStateDialog(() {
                                        modoEdicion = false;
                                        controller.text = notaActual!.texto;
                                        itemsTemp = notaActual.elementosLista.map((e) => ItemLista(texto: e.texto, completado: e.completado)).toList();
                                        controllersLista = itemsTemp.map((e) => TextEditingController(text: e.texto)).toList();
                                        focusNodesLista = itemsTemp.map((e) => FocusNode()).toList();
                                        tipoActual = notaActual.tipo;
                                        colorElegido = notaActual.colorValue;
                                        colorDialogo = Color(notaActual.colorValue);
                                      });
                                    } else { 
                                      Navigator.pop(context); 
                                    }
                                  }, 
                                  child: Text(modoEdicion ? 'Cancelar' : 'Cerrar', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 16))
                                ),
                                if (modoEdicion) ...[
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                    onPressed: () {
                                      itemsTemp.removeWhere((item) => item.texto.trim().isEmpty);
                                      
                                      if (!esNueva) {
                                        ref.read(notaProvider.notifier).editarNota(
                                          notaActual!.id, controller.text, tipo: tipoActual, elementosLista: itemsTemp, colorValue: colorElegido
                                        );
                                      } else {
                                        // Si el usuario no eligió color, se mantiene el comportamiento aleatorio original
                                        int colorFinal = colorElegido ?? _coloresPostIt[math.Random().nextInt(_coloresPostIt.length)].value;

                                        final nueva = NotaPostIt(
                                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                                          texto: controller.text,
                                          colorValue: colorFinal,
                                          rotacion: (math.Random().nextDouble() - 0.5) * 0.1,
                                          tipo: tipoActual,
                                          elementosLista: itemsTemp
                                        );
                                        ref.read(notaProvider.notifier).agregarNota(nueva);
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: Text(esNueva ? 'Guardar' : 'Guardar', style: const TextStyle(fontSize: 16)),
                                  ),
                                ],
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              )
            );
          }
        );
      },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
          return Transform.scale(
            scale: curve.value, 
            child: Opacity(opacity: animation.value, child: Transform.rotate(angle: (1.0 - animation.value) * (esNueva ? 0.1 : notaActual!.rotacion), child: child))
          );
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    final tareasOriginales = ref.watch(tareaProvider);
    final tipoOrden = ref.watch(ordenProvider);
    final temaActual = ref.watch(temaProvider);
    final notasGuardadas = ref.watch(notaProvider); 

    List<Tarea> tareas = List.from(tareasOriginales);

    // LÓGICA DE ORDENAMIENTO (Mantiene las completadas al final)
    tareas.sort((a, b) {
      if (a.esCompletada != b.esCompletada) {
        return a.esCompletada ? 1 : -1; 
      }
      switch (tipoOrden) {
        case TipoOrden.alfabetico: 
          return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
        case TipoOrden.urgencia: 
          return b.urgencia.compareTo(a.urgencia);
        case TipoOrden.fecha:
          if (a.fechaLimite == null && b.fechaLimite == null) return 0;
          if (a.fechaLimite == null) return 1; 
          if (b.fechaLimite == null) return -1;
          return a.fechaLimite!.compareTo(b.fechaLimite!); 
        case TipoOrden.creacion: 
          return 0; 
      }
    });

    final colorPrincipal = temaActual.colorPrincipal;
    final degradadoFondo = temaActual.degradadoFondo;
    final colorFondoAppBar = temaActual.colorFondo;

    // Lógica adaptativa para la marca de agua del loto
    final String imagenFondo = temaActual == TemaApp.clasico 
        ? 'assets/images/loto_gris.png' 
        : 'assets/images/loto_blanco.png';

    // Opacidad sutil ajustada para alta legibilidad
    final double opacidadLoto = temaActual == TemaApp.clasico ? 0.20 : 0.35;

    return Scaffold(
      backgroundColor: colorFondoAppBar, 
      
      appBar: AppBar(
        backgroundColor: colorFondoAppBar,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('FocusFlow', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        foregroundColor: colorPrincipal,
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: colorPrincipal),
            tooltip: 'Configuraciones',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorPrincipal,
          indicatorColor: colorPrincipal,
          unselectedLabelColor: colorPrincipal.withOpacity(0.5),
          tabs: const [
            Tab(icon: Icon(Icons.check_circle_outline), text: 'Tareas'),
            Tab(icon: Icon(Icons.repeat_rounded), text: 'Rutinas'),
            Tab(icon: Icon(Icons.sticky_note_2_rounded), text: 'Notas'), 
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_currentIndex == 0) {
            showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const AddTareaModal());
          } else if (_currentIndex == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const RutinaFormScreen()));
          } else {
            _mostrarDialogoNota();
          }
        },
        elevation: 4,
        backgroundColor: colorPrincipal,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            _currentIndex == 0 ? Icons.add_task_rounded : _currentIndex == 1 ? Icons.alarm_add_rounded : Icons.post_add_rounded,
            key: ValueKey<int>(_currentIndex),
            color: temaActual.colorSobrePrincipal,
          ),
        ),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: Text(
            _currentIndex == 0 ? 'Nueva Tarea' : _currentIndex == 1 ? 'Nuevo hábito' : 'Nueva Nota',
            key: ValueKey<int>(_currentIndex),
            style: TextStyle(color: temaActual.colorSobrePrincipal, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      
      body: Container(
        decoration: BoxDecoration(
          gradient: degradadoFondo, 
          image: DecorationImage(
            image: AssetImage(imagenFondo),
            fit: BoxFit.scaleDown, 
            alignment: Alignment.center,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(opacidadLoto), 
              BlendMode.dstIn,
            ),
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            Column(
              children: [
                // Selector de orden: debajo de la pestaña "Tareas" y encima de la lista
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<TipoOrden>(
                      tooltip: 'Ordenar',
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: (TipoOrden result) => ref.read(ordenProvider.notifier).cambiarOrden(result),
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<TipoOrden>>[
                        const PopupMenuItem<TipoOrden>(value: TipoOrden.creacion, child: Row(children: [Icon(Icons.format_list_bulleted, size: 20, color: Colors.grey), SizedBox(width: 12), Text('Orden original')])),
                        const PopupMenuItem<TipoOrden>(value: TipoOrden.alfabetico, child: Row(children: [Icon(Icons.sort_by_alpha, size: 20, color: Colors.blueGrey), SizedBox(width: 12), Text('Alfabético (A-Z)')])),
                        const PopupMenuItem<TipoOrden>(value: TipoOrden.urgencia, child: Row(children: [Icon(Icons.flag, size: 20, color: Colors.redAccent), SizedBox(width: 12), Text('Mayor urgencia')])),
                        const PopupMenuItem<TipoOrden>(value: TipoOrden.fecha, child: Row(children: [Icon(Icons.event_available, size: 20, color: Colors.orangeAccent), SizedBox(width: 12), Text('Próximas a vencer')])),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorPrincipal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sort_rounded, size: 18, color: colorPrincipal),
                            const SizedBox(width: 6),
                            Text(
                              'Orden: ${_labelOrden(tipoOrden)}',
                              style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Icon(Icons.arrow_drop_down_rounded, color: colorPrincipal),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: tareas.isEmpty
                      ? Center(child: Text('Todo al día', style: TextStyle(color: colorPrincipal.withOpacity(0.6))))
                      : () {
                          // 1. Agrupar las tareas
                          final mapaGrupos = <String, List<Tarea>>{};
                          for (var tarea in tareas) {
                            if (!mapaGrupos.containsKey(tarea.grupo)) mapaGrupos[tarea.grupo] = [];
                            mapaGrupos[tarea.grupo]!.add(tarea);
                          }

                          // 2. Ordenar los grupos (Asegurando que 'General' quede siempre hasta arriba)
                          final listaGrupos = mapaGrupos.keys.toList();
                          listaGrupos.sort((a, b) {
                            if (a == 'General') return -1;
                            if (b == 'General') return 1;
                            return a.compareTo(b);
                          });

                          // 3. Dibujar la lista con Animaciones y Colores Dinámicos
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                            itemCount: listaGrupos.length,
                            itemBuilder: (context, index) {
                              final grupo = listaGrupos[index];
                              final tareasDelGrupo = mapaGrupos[grupo]!;
                              final isColapsado = _gruposColapsados.contains(grupo);

                              // --- COLOR DINÁMICO DEL TEMA ---
                              // Extraemos el color de la interfaz de Flutter.
                              // (Si tu objeto 'temaActual' tiene una propiedad de color, por ejemplo 'temaActual.color',
                              // puedes reemplazar esta variable directamente por ese valor).
                              final colorTema = colorPrincipal;

                              return _GrupoTareasSection(
                                key: ValueKey(grupo),
                                grupo: grupo,
                                tareas: tareasDelGrupo,
                                isColapsado: isColapsado,
                                esPrimero: index == 0,
                                colorTema: colorTema,
                                temaActual: temaActual,
                                onToggle: () {
                                  setState(() {
                                    if (isColapsado) {
                                      _gruposColapsados.remove(grupo); // Abrir
                                    } else {
                                      _gruposColapsados.add(grupo); // Minimizar
                                    }
                                  });
                                },
                              );
                            },
                          );
                        }(),
                ),
              ],
            ),
            const _SeccionRutinasHoy(),
            _buildTabNotas(colorPrincipal, notasGuardadas),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// SECCIÓN DE GRUPO DE TAREAS CON ANIMACIÓN DE CASCADA (ABRIR Y CERRAR)
// =====================================================================

class _GrupoTareasSection extends StatefulWidget {
  final String grupo;
  final List<Tarea> tareas;
  final bool isColapsado;
  final bool esPrimero;
  final Color colorTema;
  final TemaApp temaActual;
  final VoidCallback onToggle;

  const _GrupoTareasSection({
    super.key,
    required this.grupo,
    required this.tareas,
    required this.isColapsado,
    required this.esPrimero,
    required this.colorTema,
    required this.temaActual,
    required this.onToggle,
  });

  @override
  State<_GrupoTareasSection> createState() => _GrupoTareasSectionState();
}

class _GrupoTareasSectionState extends State<_GrupoTareasSection> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: widget.isColapsado ? 0.0 : 1.0,
    );
  }

  @override
  void didUpdateWidget(covariant _GrupoTareasSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isColapsado != oldWidget.isColapsado) {
      if (widget.isColapsado) {
        _controller.reverse(); // Cierra con cascada ascendente
      } else {
        _controller.forward(); // Abre con cascada descendente
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tareas = widget.tareas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- CABECERA ANIMADA E INTERACTIVA ---
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: Padding(
            padding: EdgeInsets.only(bottom: 12, top: widget.esPrimero ? 0 : 24),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Icon(
                    _controller.value < 0.5 ? Icons.folder_rounded : Icons.folder_open_rounded,
                    size: 24,
                    color: widget.colorTema,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.grupo,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: widget.temaActual.colorTituloGrupo),
                ),
                const Spacer(),

                // Contador de tareas con fondo dinámico
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.colorTema.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${tareas.length}',
                    style: TextStyle(color: widget.colorTema, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),

                // Flecha con rotación animada (180 grados al abrir/cerrar)
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Transform.rotate(
                    angle: _controller.value * 3.14159265,
                    child: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),

        // --- LISTA DE TAREAS CON CASCADA ESCALONADA (ABRIR HACIA ABAJO / CERRAR HACIA ARRIBA) ---
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _controller.value.clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: Column(
            children: List.generate(tareas.length, (i) {
              final n = tareas.length;
              final start = (i / n) * 0.4;
              final end = (start + 0.6).clamp(0.0, 1.0);
              final itemCurve = CurvedAnimation(
                parent: _controller,
                curve: Interval(start, end, curve: Curves.easeOut),
              );
              return AnimatedBuilder(
                animation: itemCurve,
                builder: (context, child) => Opacity(
                  opacity: itemCurve.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - itemCurve.value) * 16),
                    child: child,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: TareaCard(tarea: tareas[i], tema: widget.temaActual),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// LÓGICA DE PERSISTENCIA (OFFLINE) Y MODELO INTEGRADO
// =====================================================================





// =====================================================================
// WIDGET INTERACTIVO DE POST-IT CON EL CLIP DE IMAGEN
// =====================================================================

class PostItCard extends StatefulWidget {
  final NotaPostIt nota;
  final int index;
  final int columnasTotales;
  final VoidCallback onTapEditar;
  final VoidCallback onDelete;

  const PostItCard({
    super.key,
    required this.nota,
    required this.index,
    required this.columnasTotales,
    required this.onTapEditar,
    required this.onDelete,
  });

  @override
  State<PostItCard> createState() => _PostItCardState();
}

class _PostItCardState extends State<PostItCard> {
  bool _clipLevantado = false;
  bool _isFading = false;

  void _activarBorrado() async {
    if (_clipLevantado) return; 
    
    setState(() => _clipLevantado = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _isFading = true);
  }

  @override
  Widget build(BuildContext context) {
    final bool clipAlaIzquierda = widget.index % 2 == 0;
    double factorEscala = 2 / widget.columnasTotales; 
    final int largoTexto = widget.nota.texto.length;
    
    double tamanoLetra;
    Alignment alineacionCaja;

    if (largoTexto < 15) {
      tamanoLetra = 22.0 * factorEscala;
      alineacionCaja = Alignment.center;
    } else if (largoTexto < 40) {
      tamanoLetra = 16.0 * factorEscala;
      alineacionCaja = Alignment.center;
    } else {
      tamanoLetra = 12.0 * factorEscala;
      alineacionCaja = Alignment.topLeft;
    }

    if (tamanoLetra < 8) tamanoLetra = 8;

    return AnimatedOpacity(
      opacity: _isFading ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      onEnd: () {
        if (_isFading) widget.onDelete(); 
      },
      child: Transform.rotate(
        angle: widget.nota.rotacion,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: widget.onTapEditar,
              child: Container(
                alignment: alineacionCaja,
                padding: EdgeInsets.fromLTRB(
                  8 * factorEscala + 4,
                  18 * factorEscala + 18,
                  8 * factorEscala + 4,
                  8 * factorEscala + 4
                ), 
                decoration: BoxDecoration(
                  color: widget.nota.color,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(2, 2)),
                  ],
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(2), topRight: const Radius.circular(2),
                    bottomLeft: const Radius.circular(2), bottomRight: Radius.circular(16 * factorEscala + 4), 
                  ),
                ),
                child: widget.nota.tipo == TipoNota.lista
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Dibuja los primeros 3 elementos de la lista
                        ...widget.nota.elementosLista.take(3).map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                item.completado ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                size: tamanoLetra + 2, // Ajusta el icono al tamaño de tu texto
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.texto,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: item.completado ? Colors.black38 : Colors.black87,
                                    fontSize: tamanoLetra, 
                                    height: 1.2, 
                                    fontWeight: FontWeight.w600,
                                    decoration: item.completado ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                        // Si hay más de 3 elementos, dibuja unos puntitos
                        if (widget.nota.elementosLista.length > 3)
                          Padding(
                            padding: const EdgeInsets.only(left: 18.0),
                            child: Text('...', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: tamanoLetra)),
                          ),
                      ],
                    )
                  // Si no es lista, dibuja el texto normal exactamente como tú lo tenías
                  : Text(
                      widget.nota.texto,
                      textAlign: tamanoLetra > 14 ? TextAlign.center : TextAlign.left,
                      style: TextStyle(color: Colors.black87, fontSize: tamanoLetra, height: 1.2, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.fade,
                    ),
              ),
            ),
            Positioned(
              top: 0, 
              left: clipAlaIzquierda ? 10 : null,
              right: !clipAlaIzquierda ? 10 : null,
              child: GestureDetector(
                onTap: _activarBorrado,
                behavior: HitTestBehavior.opaque, 
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack, 
                  transform: Matrix4.translationValues(0, _clipLevantado ? -15 : 0, 0),
                  child: Image.asset(
                    'assets/plastic_clip.png', 
                    width: 24 + (25 * factorEscala), 
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.warning_amber_rounded, 
                        size: 24 + (6 * factorEscala),
                        color: Colors.red.withValues(alpha: 0.5),
                      );
                    },
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

// --- TUS COMPONENTES ORIGINALES (_SeccionRutinasHoy y TareaCard) ---

// _SeccionRutinasHoy: pinta el contenido del tab "Rutinas" en la pantalla principal.
// Es un widget "de solo lectura" respecto a las notificaciones: únicamente
// observa (ref.watch) el estado actual de rutinaProvider y construye la lista
// de RutinaCard para HOY. Toda la lógica de cancelar/programar notificaciones
// vive en rutina_provider.dart y rutina_card.dart, NO aquí.
class _SeccionRutinasHoy extends ConsumerWidget {
  const _SeccionRutinasHoy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listaCompleta = ref.watch(rutinaProvider);
    final temaActual = ref.watch(temaProvider);
    final colorPrincipal = temaActual.colorPrincipal;
    final int diaActual = DateTime.now().weekday - 1; 
    final rutinasDeHoy = listaCompleta.where((r) => r.horarios.containsKey(diaActual) && r.activa).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hoy es ${DateFormat('EEEE', 'es_ES').format(DateTime.now())}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: colorPrincipal)),
                    const SizedBox(height: 4),
                    Text(rutinasDeHoy.isEmpty ? 'No hay hábitos programados.' : 'Tienes ${rutinasDeHoy.length} hábitos para hoy.', style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.mode_edit_outline_rounded, color: colorPrincipal),
                tooltip: 'Configurar Horario Semanal',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GestorRutinasScreen(colorTema: colorPrincipal))),
              ),
            ],
          ),
        ),
        
        
        Expanded(
          child: Column(
            children: [
              // 1. La barra de progreso inteligente: 
              // Solo se dibuja si la lista de rutinas de hoy NO está vacía.
              if (rutinasDeHoy.isNotEmpty) 
                ProgresoRutinasBar(
                  rutinasDeHoy: rutinasDeHoy,
                  colorTema: colorPrincipal, // Le inyectamos el color del tema actual
                ),

              // 2. El contenido principal (Mensaje motivacional o Lista de rutinas)
              Expanded(
                child: rutinasDeHoy.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center, 
                          children: [
                            // Este espacio empuja el texto hacia abajo del loto central.
                            const SizedBox(height: 120), 
                            
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32), 
                              child: Text(
                                'Cada que agregas un nuevo hábito a tu vida,\nte acercas más a la persona que quieres ser.', 
                                textAlign: TextAlign.center, 
                                style: TextStyle(
                                  color: colorPrincipal.withOpacity(0.6),
                                  fontSize: 15,
                                  height: 1.4, 
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 16, bottom: 100, left: 16, right: 16),
                        itemCount: rutinasDeHoy.length,
                        itemBuilder: (context, index) => RutinaCard(
                          rutina: rutinasDeHoy[index], 
                          colorTema: colorPrincipal
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TareaCard extends ConsumerStatefulWidget {
  final Tarea tarea;
  final TemaApp tema; 
  const TareaCard({super.key, required this.tarea, required this.tema});

  @override
  ConsumerState<TareaCard> createState() => _TareaCardState();
}

class _TareaCardState extends ConsumerState<TareaCard> {
  bool _isExpanded = false; 
  bool _showOverlayMenu = false;
  Timer? _timerAtraso; 

  @override
  void initState() {
    super.initState();
    _programarRevisarAtraso(); 
  }

  @override
  void didUpdateWidget(TareaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tarea.fechaLimite != widget.tarea.fechaLimite || oldWidget.tarea.esCompletada != widget.tarea.esCompletada) {
      _timerAtraso?.cancel(); _programarRevisarAtraso();
    }
  }

  void _programarRevisarAtraso() {
    final tarea = widget.tarea;
    if (!tarea.esCompletada && tarea.fechaLimite != null) {
      final ahora = DateTime.now();
      if (tarea.fechaLimite!.isAfter(ahora)) {
        final diferencia = tarea.fechaLimite!.difference(ahora);
        _timerAtraso = Timer(diferencia, () { if (mounted) setState(() {}); });
      }
    }
  }

  @override
  void dispose() { _timerAtraso?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final tarea = widget.tarea;
    final colorBase = _getColorUrgencia(tarea.urgencia, widget.tema);
    // Las tarjetas completadas siempre quedan claras (blanco @0.7) en los 5
    // temas, así que su texto oscuro sigue legible sin cambios. Solo las NO
    // completadas se tiñen con colorBase, lo que en Medianoche produce una
    // tarjeta oscura: por eso el texto de esa rama necesita volverse claro.
    final bool esMedianoche = widget.tema == TemaApp.medianoche;
    final colorTarjeta = tarea.esCompletada ? Colors.white.withValues(alpha: 0.7) : (widget.tema == TemaApp.clasico ? Colors.white : colorBase.withValues(alpha: 0.25));
    final bool estaAtrasada = !tarea.esCompletada && tarea.fechaLimite != null && tarea.fechaLimite!.isBefore(DateTime.now());
    final bool tieneSubtareas = tarea.subtareas.isNotEmpty;
    final bool tieneDescripcionVisible = tarea.descripcion != null && tarea.descripcion!.isNotEmpty;
    const Color colorTextoClaro = Color(0xFFF1F5F9);

    return Container(
      margin: const EdgeInsets.only(bottom: 16), 
      decoration: BoxDecoration(
        color: colorTarjeta,
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: tarea.esCompletada ? Colors.transparent : colorBase.withValues(alpha: widget.tema == TemaApp.clasico ? 0.6 : 0.4), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias, 
      child: Stack( 
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            onLongPress: () => setState(() => _showOverlayMenu = true),
            child: Padding(
              padding: const EdgeInsets.all(4), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: Checkbox(value: tarea.esCompletada, activeColor: colorBase, shape: const CircleBorder(), side: BorderSide(color: tarea.esCompletada ? colorBase : (esMedianoche ? Colors.white54 : Colors.black45), width: 1.5), onChanged: (_) => ref.read(tareaProvider.notifier).toggleTarea(tarea.id)),
                    title: Row(
                      children: [
                        Expanded(
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              tarea.titulo,
                              style: TextStyle(fontSize: 17, decoration: tarea.esCompletada ? TextDecoration.lineThrough : null, color: tarea.esCompletada ? Colors.black38 : (esMedianoche ? colorTextoClaro : Colors.black87), fontWeight: tarea.esCompletada ? FontWeight.normal : FontWeight.w600),
                              maxLines: _isExpanded ? null : 1,
                              overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (tieneSubtareas) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _isExpanded = !_isExpanded),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: colorBase.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${tarea.progresoSubtareas.$1}/${tarea.progresoSubtareas.$2}', style: TextStyle(color: colorBase, fontSize: 12, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 2),
                                  Icon(_isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: colorBase),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: (!tarea.esCompletada && tarea.fechaLimite != null) || tieneSubtareas
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!tarea.esCompletada && tarea.fechaLimite != null)
                                  Row(children: [
                                    Icon(Icons.access_time, size: 14, color: colorBase.withValues(alpha: 0.9)),
                                    const SizedBox(width: 4),
                                    Text(
                                      // 23:59 es el valor implícito cuando no se eligió hora (ver
                                      // add_tarea_modal._guardarTarea), así que no se muestra.
                                      DateFormat(
                                        (tarea.fechaLimite!.hour == 23 && tarea.fechaLimite!.minute == 59) ? 'EEEE, d MMM' : 'EEEE, d MMM • HH:mm',
                                        'es',
                                      ).format(tarea.fechaLimite!),
                                      style: TextStyle(color: colorBase.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ]),
                                if (tieneSubtareas) ...[
                                  if (!tarea.esCompletada && tarea.fechaLimite != null) const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(value: tarea.porcentajeSubtareas, minHeight: 4, backgroundColor: colorBase.withValues(alpha: 0.15), valueColor: AlwaysStoppedAnimation(colorBase)),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : null,
                    trailing: tarea.esCompletada ? null : Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: (widget.tema == TemaApp.clasico || esMedianoche) ? colorBase.withValues(alpha: 0.2) : colorBase, borderRadius: BorderRadius.circular(12)), child: Text(_getLabelUrgencia(tarea.urgencia), style: TextStyle(color: (widget.tema == TemaApp.clasico || esMedianoche) ? colorBase : Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _isExpanded && !tarea.esCompletada && (tieneDescripcionVisible || tieneSubtareas)
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(72, 0, 24, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (tieneDescripcionVisible) Text(tarea.descripcion!, style: TextStyle(fontSize: 14, color: esMedianoche ? colorTextoClaro.withValues(alpha: 0.75) : Colors.black54, height: 1.4)),
                                if (tieneDescripcionVisible && tieneSubtareas) const SizedBox(height: 12),
                                if (tieneSubtareas) ..._buildFilasSubtareas(tarea, colorBase, esMedianoche),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          if (estaAtrasada) Positioned(top: 12, right: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26, offset: Offset(0, 2))]), child: const Text('ATRASADO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)))),
          if (_showOverlayMenu) Positioned.fill(child: GestureDetector(onTap: () => setState(() => _showOverlayMenu = false), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), child: Container(color: Colors.white.withValues(alpha: 0.2), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildActionIcon(icon: tarea.esCompletada ? Icons.undo : Icons.check_rounded, color: const Color(0xFF4CAF50), onTap: () { ref.read(tareaProvider.notifier).toggleTarea(tarea.id); setState(() => _showOverlayMenu = false); }), _buildActionIcon(icon: Icons.edit_rounded, color: Colors.blueGrey, onTap: () { setState(() => _showOverlayMenu = false); showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => AddTareaModal(tareaAEditar: tarea)); }), _buildActionIcon(icon: Icons.delete_rounded, color: Colors.redAccent, onTap: () { setState(() => _showOverlayMenu = false); Future.delayed(const Duration(milliseconds: 150), () { if (!mounted) return; ref.read(tareaProvider.notifier).deleteTarea(tarea.id); mostrarSnackBarSimple(mensaje: 'Tarea eliminada', colorFondo: widget.tema.colorPrincipal, colorTexto: widget.tema.colorSobrePrincipal); }); })]))))),
        ],
      ),
    );
  }

  Widget _buildActionIcon({required IconData icon, required Color color, required VoidCallback onTap}) {
    return CircleAvatar(backgroundColor: Colors.white, radius: 28, child: IconButton(icon: Icon(icon, color: color, size: 28), onPressed: onTap));
  }

  // Aviso no bloqueante (SnackBar con acción) al completar el último paso
  // pendiente de la lista de subtareas. El usuario decide si marca la tarea
  // completa o la deja pendiente; no hay auto-completado ni diálogo modal.
  void _preguntarCompletarTarea(Tarea tarea) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Completaste todos los pasos. ¿Marcar la tarea como completada?'),
        action: SnackBarAction(
          label: 'Marcar',
          onPressed: () => ref.read(tareaProvider.notifier).toggleTarea(tarea.id),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // Checklist de subtareas dentro de la tarjeta expandida. El marcado se
  // delega siempre a toggleSubtarea del provider (sin lógica propia aquí).
  List<Widget> _buildFilasSubtareas(Tarea tarea, Color colorBase, bool esMedianoche) {
    const colorTextoClaro = Color(0xFFF1F5F9);
    return tarea.subtareas.map((sub) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            height: 22, width: 22,
            child: Checkbox(
              value: sub.completado,
              activeColor: colorBase,
              side: BorderSide(color: sub.completado ? colorBase : (esMedianoche ? Colors.white54 : Colors.black45), width: 1.5),
              onChanged: (_) {
                final estabaSinCompletar = !sub.completado;
                ref.read(tareaProvider.notifier).toggleSubtarea(tarea.id, sub.id);

                // Si este era el último paso pendiente, la tarea sigue "no completada"
                // por decisión de diseño (b): se le pregunta al usuario en vez de
                // auto-completarla o dejarla en 100% sin marcar.
                final tareaActualizada = ref.read(tareaProvider).firstWhere((t) => t.id == tarea.id);
                final (completadas, total) = tareaActualizada.progresoSubtareas;
                if (estabaSinCompletar && completadas == total && !tareaActualizada.esCompletada) {
                  _preguntarCompletarTarea(tareaActualizada);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sub.texto,
              style: TextStyle(
                fontSize: 14,
                decoration: sub.completado ? TextDecoration.lineThrough : null,
                color: sub.completado
                    ? (esMedianoche ? colorTextoClaro.withValues(alpha: 0.38) : Colors.black38)
                    : (esMedianoche ? colorTextoClaro : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    )).toList();
  }

  Color _getColorUrgencia(int urgencia, TemaApp tema) {
    if (tema == TemaApp.clasico) {
      switch (urgencia) { case 1: return Colors.teal; case 2: return Colors.blue; case 3: return Colors.orange; case 4: return Colors.red; default: return Colors.grey; }
    } else if (tema == TemaApp.zenClasico) {
      switch (urgencia) { case 1: return const Color(0xFFA5C4A6); case 2: return const Color(0xFF80A681); case 3: return const Color(0xFF5A855C); case 4: return const Color(0xFF3B633D); default: return Colors.grey; }
    } else if (tema == TemaApp.brisaMarina) {
      switch (urgencia) { case 1: return const Color(0xFF90CDF4); case 2: return const Color(0xFF63B3ED); case 3: return const Color(0xFF3182CE); case 4: return const Color(0xFF2B6CB0); default: return Colors.grey; }
    } else if (tema == TemaApp.medianoche) {
      // Escala morada (violeta claro -> violeta intenso) en vez de colores
      // dispares por nivel. Actúan como TEXTO sobre una tarjeta oscura
      // (colorBase@25% sobre fondo casi negro), no como relleno claro, así
      // que necesitan alta luminancia para mantener ≥4.5:1 de contraste;
      // el nivel 4 (#8B5CF6) es el más oscuro que aún cumple ese mínimo.
      switch (urgencia) { case 1: return const Color(0xFFDDD6FE); case 2: return const Color(0xFFC4B5FD); case 3: return const Color(0xFFA78BFA); case 4: return const Color(0xFF8B5CF6); default: return Colors.grey.shade400; }
    } else {
      switch (urgencia) { case 1: return const Color(0xFFFBD38D); case 2: return const Color(0xFFF6AD55); case 3: return const Color(0xFFDD6B20); case 4: return const Color(0xFFC05621); default: return Colors.grey; }
    }
  }

  String _getLabelUrgencia(int urgencia) {
    switch (urgencia) { case 1: return 'BAJO'; case 2: return 'MEDIO'; case 3: return 'ALTO'; case 4: return 'MUY ALTO'; default: return '???'; }
  }

  
}

// =========================================================================
// BLOQUE FINAL DE NOTAS: pintor decorativo de la libreta (modelo y
// provider de notas viven en models/nota.dart y providers/nota_provider.dart)
// =========================================================================

class HojaLibretaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLineas = Paint()..color = Colors.blueAccent.withOpacity(0.2)..strokeWidth = 1.5;
    final paintMargen = Paint()..color = Colors.redAccent.withOpacity(0.4)..strokeWidth = 2.0;
    const double margenIzquierdo = 44.0;
    canvas.drawLine(Offset(margenIzquierdo, 0), Offset(margenIzquierdo, size.height), paintMargen);
    const double interlineado = 28.0; 
    for (double y = 92.0; y < size.height; y += interlineado) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintLineas);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}