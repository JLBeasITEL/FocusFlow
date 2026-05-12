import 'package:app_tareas/presentation/screens/gestor_rutinas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'dart:ui'; 
import 'dart:math' as math; 
import 'dart:convert'; // Necesario para guardar datos
import 'package:shared_preferences/shared_preferences.dart'; // Necesario para guardado offline

import '../../providers/tarea_provider.dart';
import '../../models/tarea.dart';
import '../widgets/add_tarea_modal.dart';
import '../../providers/rutina_provider.dart';
import '../widgets/rutina_card.dart';
import 'rutina_form_screen.dart';
import '../../providers/tema_provider.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'dart:async';
// IMPORTANTE: Ya no necesitamos importar nota_provider.dart porque lo integramos aquí mismo

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0; 
  
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

    _solicitarPermisosDeBateria();

    // NUEVO: Sincronización silenciosa de rutinas al abrir la app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resincronizarRutinasSilenciosamente();
    });
  }

  // --- FUNCIÓN DE RESPALDO ANTI-BORRADO ---
  void _resincronizarRutinasSilenciosamente() {
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
  }

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

  Gradient _getDegradadoFondo(TemaApp tema) {
    if (tema == TemaApp.clasico) return const LinearGradient(colors: [Colors.white, Colors.white]);
    if (tema == TemaApp.brisaMarina) return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF0F8FF), Color(0xFF9FB8D0)]);
    if (tema == TemaApp.atardecerMinimalista) return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF9F5), Color(0xFFE5B270)]);
    return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF2F7F2), Color(0xFF8BA888)]);
  }

  Color _getColorPrincipal(TemaApp tema) {
    if (tema == TemaApp.clasico) return Colors.black87; 
    if (tema == TemaApp.brisaMarina) return const Color(0xFF1E3A8A); 
    if (tema == TemaApp.atardecerMinimalista) return const Color(0xFFC05621); 
    return const Color(0xFF276749); 
  }

  Color _getColorFondoAppBar(TemaApp tema) {
    if (tema == TemaApp.clasico) return Colors.white;
    if (tema == TemaApp.brisaMarina) return const Color(0xFFF0F8FF);
    if (tema == TemaApp.atardecerMinimalista) return const Color(0xFFFFF9F5);
    return const Color(0xFFF2F7F2); 
  }

  // --- VISTA DE NOTAS ESTILO TABLERO ---
  Widget _buildTabNotas(Color colorPrincipal, List<NotaPostIt> notasActuales) {
    if (notasActuales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 80, color: colorPrincipal.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
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
          onDelete: () {
            // Le pedimos al Provider que elimine la nota permanentemente
            ref.read(notaProvider.notifier).eliminarNota(nota.id);
          },
        );
      },
    );
  }

  // DIÁLOGO ANIMADO PARA CREAR/EDITAR
  void _mostrarDialogoNota({int? indexAEditar}) {
    final notasActuales = ref.read(notaProvider);
    final bool esNueva = indexAEditar == null;
    final notaActual = esNueva ? null : notasActuales[indexAEditar];
    final controller = TextEditingController(text: esNueva ? '' : notaActual!.texto);
    final Color colorDialogo = esNueva ? const Color(0xFFFFF7D1) : notaActual!.color;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withValues(alpha: 0.6), 
      transitionDuration: const Duration(milliseconds: 400), 
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: SingleChildScrollView(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorDialogo,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8), topRight: Radius.circular(8),
                    bottomLeft: Radius.circular(8), bottomRight: Radius.circular(40), 
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true, maxLines: 8, minLines: 3,
                      style: const TextStyle(fontSize: 20, color: Colors.black87, fontWeight: FontWeight.w500, height: 1.4),
                      decoration: const InputDecoration(hintText: 'Escribe tu idea...', border: InputBorder.none),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 16))),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87, foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            if (controller.text.trim().isNotEmpty) {
                              if (!esNueva) {
                                // Editar nota existente
                                ref.read(notaProvider.notifier).editarNota(notaActual!.id, controller.text);
                              } else {
                                // Crear nueva nota con color aleatorio
                                final math.Random random = math.Random();
                                final colorAleatorio = _coloresPostIt[random.nextInt(_coloresPostIt.length)];
                                final rotacionAleatoria = (random.nextDouble() - 0.5) * 0.1; 
                                
                                final nueva = NotaPostIt(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(), // ID Único
                                  texto: controller.text, 
                                  colorValue: colorAleatorio.value, // Guardamos el valor numérico del color
                                  rotacion: rotacionAleatoria
                                );
                                ref.read(notaProvider.notifier).agregarNota(nueva);
                              }
                            }
                            Navigator.pop(context);
                          },
                          child: Text(esNueva ? 'Pegar Nota' : 'Guardar', style: const TextStyle(fontSize: 16)),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return Transform.scale(
          scale: curve.value, 
          child: Opacity(
            opacity: animation.value, 
            child: Transform.rotate(
              angle: (1.0 - animation.value) * (esNueva ? 0.1 : notaActual!.rotacion), 
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tareasOriginales = ref.watch(tareaProvider);
    final tipoOrden = ref.watch(ordenProvider);
    final temaActual = ref.watch(temaProvider);
    final notasGuardadas = ref.watch(notaProvider); // Obtenemos las notas de la memoria

    List<Tarea> tareas = List.from(tareasOriginales);

    switch (tipoOrden) {
      case TipoOrden.alfabetico: tareas.sort((a, b) => a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase())); break;
      case TipoOrden.urgencia: tareas.sort((a, b) => b.urgencia.compareTo(a.urgencia)); break;
      case TipoOrden.fecha:
        tareas.sort((a, b) {
          if (a.fechaLimite == null && b.fechaLimite == null) return 0;
          if (a.fechaLimite == null) return 1; 
          if (b.fechaLimite == null) return -1;
          return a.fechaLimite!.compareTo(b.fechaLimite!); 
        });
        break;
      case TipoOrden.creacion: break;
    }

    final colorPrincipal = _getColorPrincipal(temaActual);
    final degradadoFondo = _getDegradadoFondo(temaActual);
    final colorFondoAppBar = _getColorFondoAppBar(temaActual); 

    return Scaffold(
      backgroundColor: colorFondoAppBar, 
      
      appBar: AppBar(
        backgroundColor: colorFondoAppBar,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('FocusFlow', style: TextStyle(fontWeight: FontWeight.bold, color: colorPrincipal, fontSize: 24)),
        actions: [
          PopupMenuButton<TemaApp>(
            icon: Icon(Icons.palette_rounded, color: colorPrincipal),
            tooltip: 'Cambiar Tema',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (TemaApp result) => ref.read(temaProvider.notifier).cambiarTema(result),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<TemaApp>>[
              const PopupMenuItem<TemaApp>(value: TemaApp.clasico, child: Row(children: [Icon(Icons.format_paint, size: 20, color: Colors.black87), SizedBox(width: 12), Text('Original (Blanco)')])),
              const PopupMenuItem<TemaApp>(value: TemaApp.zenClasico, child: Row(children: [Icon(Icons.spa, size: 20, color: Color(0xFF5A855C)), SizedBox(width: 12), Text('Zen Clásico (Verde)')])),
              const PopupMenuItem<TemaApp>(value: TemaApp.brisaMarina, child: Row(children: [Icon(Icons.water_drop, size: 20, color: Color(0xFF3182CE)), SizedBox(width: 12), Text('Brisa Marina (Azul)')])),
              const PopupMenuItem<TemaApp>(value: TemaApp.atardecerMinimalista, child: Row(children: [Icon(Icons.wb_twilight, size: 20, color: Color(0xFFDD6B20)), SizedBox(width: 12), Text('Atardecer (Naranja)')])),
            ],
          ),
          PopupMenuButton<TipoOrden>(
            icon: Icon(Icons.sort_rounded, color: colorPrincipal),
            tooltip: 'Ordenar',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (TipoOrden result) => ref.read(ordenProvider.notifier).cambiarOrden(result),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<TipoOrden>>[
              const PopupMenuItem<TipoOrden>(value: TipoOrden.creacion, child: Row(children: [Icon(Icons.format_list_bulleted, size: 20, color: Colors.grey), SizedBox(width: 12), Text('Orden original')])),
              const PopupMenuItem<TipoOrden>(value: TipoOrden.alfabetico, child: Row(children: [Icon(Icons.sort_by_alpha, size: 20, color: Colors.blueGrey), SizedBox(width: 12), Text('Alfabético (A-Z)')])),
              const PopupMenuItem<TipoOrden>(value: TipoOrden.urgencia, child: Row(children: [Icon(Icons.flag, size: 20, color: Colors.redAccent), SizedBox(width: 12), Text('Mayor urgencia')])),
              const PopupMenuItem<TipoOrden>(value: TipoOrden.fecha, child: Row(children: [Icon(Icons.event_available, size: 20, color: Colors.orangeAccent), SizedBox(width: 12), Text('Próximas a vencer')])),
            ],
          ),
          IconButton(
            icon: Icon(Icons.mode_edit_outline_rounded, color: colorPrincipal),
            tooltip: 'Configurar Horario Semanal',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GestorRutinasScreen(colorTema: colorPrincipal))),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorPrincipal,
          indicatorColor: colorPrincipal,
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
            color: Colors.white,
          ),
        ),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: Text(
            _currentIndex == 0 ? 'Nueva Tarea' : _currentIndex == 1 ? 'Nuevo hábito' : 'Nueva Nota',
            key: ValueKey<int>(_currentIndex), 
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      
      body: Container(
        decoration: BoxDecoration(gradient: degradadoFondo),
        child: TabBarView(
          controller: _tabController,
          children: [
            tareas.isEmpty
                ? Center(child: Text('Todo al día', style: TextStyle(color: colorPrincipal.withValues(alpha: 0.6))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), 
                    itemCount: tareas.length,
                    itemBuilder: (context, index) => TareaCard(tarea: tareas[index], tema: temaActual),
                  ),
            const _SeccionRutinasHoy(), 
            _buildTabNotas(colorPrincipal, notasGuardadas), // Le pasamos la lista segura
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// LÓGICA DE PERSISTENCIA (OFFLINE) Y MODELO INTEGRADO
// =====================================================================

class NotaPostIt {
  final String id; 
  String texto;
  int colorValue; // Ahora guardamos el valor numérico
  double rotacion;

  NotaPostIt({required this.id, required this.texto, required this.colorValue, required this.rotacion});

  // Para poder usarlo en Flutter como Color
  Color get color => Color(colorValue);

  // Convierte la nota en un formato de texto que se pueda guardar en el teléfono
  Map<String, dynamic> toMap() => {
    'id': id,
    'texto': texto,
    'colorValue': colorValue,
    'rotacion': rotacion,
  };

  // Reconstruye la nota desde el archivo del teléfono
  factory NotaPostIt.fromMap(Map<String, dynamic> map) => NotaPostIt(
    id: map['id'],
    texto: map['texto'],
    colorValue: map['colorValue'],
    rotacion: map['rotacion'],
  );
}

// EL "CEREBRO" QUE GUARDA Y CARGA
class NotaNotifier extends StateNotifier<List<NotaPostIt>> {
  NotaNotifier() : super([]) {
    _cargarNotas(); // Cargar automáticamente al abrir la app
  }

  Future<void> _cargarNotas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? notasString = prefs.getString('mis_notas_guardadas');
    if (notasString != null) {
      final List<dynamic> decoded = jsonDecode(notasString);
      state = decoded.map((item) => NotaPostIt.fromMap(item)).toList();
    }
  }

  Future<void> _guardarEnDisco() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(state.map((n) => n.toMap()).toList());
    await prefs.setString('mis_notas_guardadas', encoded);
  }

  void agregarNota(NotaPostIt nueva) {
    state = [nueva, ...state];
    _guardarEnDisco();
  }

  void eliminarNota(String id) {
    state = state.where((n) => n.id != id).toList();
    _guardarEnDisco();
  }

  void editarNota(String id, String nuevoTexto) {
    state = [
      for (final n in state)
        if (n.id == id) NotaPostIt(id: n.id, texto: nuevoTexto, colorValue: n.colorValue, rotacion: n.rotacion)
        else n
    ];
    _guardarEnDisco();
  }
}

// EL PROVEEDOR GLOBAL
final notaProvider = StateNotifierProvider<NotaNotifier, List<NotaPostIt>>((ref) => NotaNotifier());

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
                child: Text(
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

class _SeccionRutinasHoy extends ConsumerWidget {
  const _SeccionRutinasHoy();

  Color _getPrimaryColor(TemaApp tema) {
    switch (tema) {
      case TemaApp.clasico: return Colors.black87;
      case TemaApp.brisaMarina: return const Color(0xFF1E3A8A); 
      case TemaApp.atardecerMinimalista: return const Color(0xFFC05621); 
      case TemaApp.zenClasico: return const Color(0xFF276749); 
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listaCompleta = ref.watch(rutinaProvider);
    final temaActual = ref.watch(temaProvider);
    final colorPrincipal = _getPrimaryColor(temaActual);
    final int diaActual = DateTime.now().weekday - 1; 
    final rutinasDeHoy = listaCompleta.where((r) => r.horarios.containsKey(diaActual) && r.activa).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hoy es ${DateFormat('EEEE', 'es_ES').format(DateTime.now())}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: colorPrincipal)),
              const SizedBox(height: 4),
              Text(rutinasDeHoy.isEmpty ? 'No hay hábitos programados.' : 'Tienes ${rutinasDeHoy.length} hábitos para hoy.', style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Expanded(
          child: rutinasDeHoy.isEmpty
              ? Center(child: Icon(Icons.event_available_rounded, size: 80, color: colorPrincipal.withValues(alpha: 0.15)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rutinasDeHoy.length,
                  itemBuilder: (context, index) => RutinaCard(rutina: rutinasDeHoy[index], colorTema: colorPrincipal),
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
    final colorTarjeta = tarea.esCompletada ? Colors.white.withValues(alpha: 0.7) : (widget.tema == TemaApp.clasico ? Colors.white : colorBase.withValues(alpha: 0.25)); 
    final bool estaAtrasada = !tarea.esCompletada && tarea.fechaLimite != null && tarea.fechaLimite!.isBefore(DateTime.now());

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
                    leading: Checkbox(value: tarea.esCompletada, activeColor: colorBase, shape: const CircleBorder(), side: BorderSide(color: tarea.esCompletada ? colorBase : Colors.black45, width: 1.5), onChanged: (_) => ref.read(tareaProvider.notifier).toggleTarea(tarea.id)),
                    title: Text(tarea.titulo, style: TextStyle(fontSize: 17, decoration: tarea.esCompletada ? TextDecoration.lineThrough : null, color: tarea.esCompletada ? Colors.black38 : Colors.black87, fontWeight: tarea.esCompletada ? FontWeight.normal : FontWeight.w600)),
                    subtitle: !tarea.esCompletada && tarea.fechaLimite != null ? Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [Icon(Icons.access_time, size: 14, color: colorBase.withValues(alpha: 0.9)), const SizedBox(width: 4), Text(DateFormat('EEEE, d MMM • HH:mm', 'es').format(tarea.fechaLimite!), style: TextStyle(color: colorBase.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w600))])) : null,
                    trailing: tarea.esCompletada ? null : Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: widget.tema == TemaApp.clasico ? colorBase.withValues(alpha: 0.2) : colorBase, borderRadius: BorderRadius.circular(12)), child: Text(_getLabelUrgencia(tarea.urgencia), style: TextStyle(color: widget.tema == TemaApp.clasico ? colorBase : Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                  ),
                  AnimatedSize(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, child: _isExpanded && tarea.descripcion != null && tarea.descripcion!.isNotEmpty && !tarea.esCompletada ? Padding(padding: const EdgeInsets.fromLTRB(72, 0, 24, 16), child: Align(alignment: Alignment.centerLeft, child: Text(tarea.descripcion!, style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.4)))) : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
          if (estaAtrasada) Positioned(top: 12, right: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26, offset: Offset(0, 2))]), child: const Text('ATRASADO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)))),
          if (_showOverlayMenu) Positioned.fill(child: GestureDetector(onTap: () => setState(() => _showOverlayMenu = false), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), child: Container(color: Colors.white.withValues(alpha: 0.2), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildActionIcon(icon: tarea.esCompletada ? Icons.undo : Icons.check_rounded, color: const Color(0xFF4CAF50), onTap: () { ref.read(tareaProvider.notifier).toggleTarea(tarea.id); setState(() => _showOverlayMenu = false); }), _buildActionIcon(icon: Icons.edit_rounded, color: Colors.blueGrey, onTap: () { setState(() => _showOverlayMenu = false); showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => AddTareaModal(tareaAEditar: tarea)); }), _buildActionIcon(icon: Icons.delete_rounded, color: Colors.redAccent, onTap: () { setState(() => _showOverlayMenu = false); Future.delayed(const Duration(milliseconds: 150), () { ref.read(tareaProvider.notifier).deleteTarea(tarea.id); }); })]))))),
        ],
      ),
    );
  }

  Widget _buildActionIcon({required IconData icon, required Color color, required VoidCallback onTap}) {
    return CircleAvatar(backgroundColor: Colors.white, radius: 28, child: IconButton(icon: Icon(icon, color: color, size: 28), onPressed: onTap));
  }

  Color _getColorUrgencia(int urgencia, TemaApp tema) {
    if (tema == TemaApp.clasico) {
      switch (urgencia) { case 1: return Colors.teal; case 2: return Colors.blue; case 3: return Colors.orange; case 4: return Colors.red; default: return Colors.grey; }
    } else if (tema == TemaApp.zenClasico) {
      switch (urgencia) { case 1: return const Color(0xFFA5C4A6); case 2: return const Color(0xFF80A681); case 3: return const Color(0xFF5A855C); case 4: return const Color(0xFF3B633D); default: return Colors.grey; }
    } else if (tema == TemaApp.brisaMarina) {
      switch (urgencia) { case 1: return const Color(0xFF90CDF4); case 2: return const Color(0xFF63B3ED); case 3: return const Color(0xFF3182CE); case 4: return const Color(0xFF2B6CB0); default: return Colors.grey; }
    } else { 
      switch (urgencia) { case 1: return const Color(0xFFFBD38D); case 2: return const Color(0xFFF6AD55); case 3: return const Color(0xFFDD6B20); case 4: return const Color(0xFFC05621); default: return Colors.grey; }
    }
  }

  String _getLabelUrgencia(int urgencia) {
    switch (urgencia) { case 1: return 'BAJO'; case 2: return 'MEDIO'; case 3: return 'ALTO'; case 4: return 'MUY ALTO'; default: return '???'; }
  }
}