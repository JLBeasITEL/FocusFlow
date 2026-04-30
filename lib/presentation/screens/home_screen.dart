import 'package:app_tareas/presentation/screens/gestor_rutinas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:ui'; 
import '../../providers/tarea_provider.dart';
import '../../models/tarea.dart';
import '../widgets/add_tarea_modal.dart';
import '../../providers/rutina_provider.dart';
import '../widgets/rutina_card.dart';
import 'rutina_form_screen.dart';

// 1. Transformación a ConsumerStatefulWidget para manejar estado interno
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0; // Rastreador de la pestaña actual

  @override
  void initState() {
    super.initState();
    // 2. Inicialización del controlador con el TickerProvider
    _tabController = TabController(length: 2, vsync: this);
    
    // Escuchador de la animación para cambios instantáneos al deslizar
    _tabController.animation?.addListener(() {
      final int proximoIndex = _tabController.animation!.value.round();
      if (_currentIndex != proximoIndex) {
        setState(() {
          _currentIndex = proximoIndex;
        });
      }
    });

    // Escuchador extra para asegurar cambios al hacer clic en los nombres de las pestañas
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        if (_currentIndex != _tabController.index) {
          setState(() {
            _currentIndex = _tabController.index;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- MÉTODOS DE ESTILO (DEGRADADOS Y COLORES) ---
  Gradient _getDegradadoFondo(TemaApp tema) {
    if (tema == TemaApp.clasico) return const LinearGradient(colors: [Colors.white, Colors.white]);
    if (tema == TemaApp.brisaMarina) {
      return const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter, 
        colors: [Color(0xFFF0F8FF), Color(0xFF9FB8D0)]
      );
    }
    if (tema == TemaApp.atardecerMinimalista) {
      return const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter, 
        colors: [Color(0xFFFFF9F5), Color(0xFFE5B270)]
      );
    }
    return const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter, 
      colors: [Color(0xFFF2F7F2), Color(0xFF8BA888)]
    );
  }

  Color _getColorPrincipal(TemaApp tema) {
    if (tema == TemaApp.clasico) return Colors.black87; 
    if (tema == TemaApp.brisaMarina) return const Color(0xFF1E3A8A); 
    if (tema == TemaApp.atardecerMinimalista) return const Color(0xFFC05621); 
    return const Color(0xFF276749); 
  }

  // --- COLOR SÓLIDO PARA LA BARRA SUPERIOR ---
  Color _getColorFondoAppBar(TemaApp tema) {
    if (tema == TemaApp.clasico) return Colors.white;
    if (tema == TemaApp.brisaMarina) return const Color(0xFFF0F8FF);
    if (tema == TemaApp.atardecerMinimalista) return const Color(0xFFFFF9F5);
    return const Color(0xFFF2F7F2); // Zen
  }

  @override
  Widget build(BuildContext context) {
    final tareasOriginales = ref.watch(tareaProvider);
    final tipoOrden = ref.watch(ordenProvider);
    final temaActual = ref.watch(temaProvider);

    List<Tarea> tareas = List.from(tareasOriginales);

    switch (tipoOrden) {
      case TipoOrden.alfabetico:
        tareas.sort((a, b) => a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase()));
        break;
      case TipoOrden.urgencia:
        tareas.sort((a, b) => b.urgencia.compareTo(a.urgencia));
        break;
      case TipoOrden.fecha:
        tareas.sort((a, b) {
          if (a.fechaLimite == null && b.fechaLimite == null) return 0;
          if (a.fechaLimite == null) return 1; 
          if (b.fechaLimite == null) return -1;
          return a.fechaLimite!.compareTo(b.fechaLimite!); 
        });
        break;
      case TipoOrden.creacion:
      break;
    }

    final colorPrincipal = _getColorPrincipal(temaActual);
    final degradadoFondo = _getDegradadoFondo(temaActual);
    final colorFondoAppBar = _getColorFondoAppBar(temaActual); 

    return Scaffold(
      backgroundColor: colorFondoAppBar, // Base unificada para que combine con la hora y batería
      
      // 1. APPBAR TRADICIONAL (Ya no usamos SliverAppBar)
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
          ],
        ),
      ),

      // 2. BOTÓN FLOTANTE INTACTO
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_currentIndex == 0) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const AddTareaModal(),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RutinaFormScreen()),
            );
          }
        },
        elevation: 4,
        backgroundColor: colorPrincipal,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            _currentIndex == 0 ? Icons.add_task_rounded : Icons.alarm_add_rounded,
            key: ValueKey<int>(_currentIndex), 
            color: Colors.white,
          ),
        ),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: Text(
            _currentIndex == 0 ? 'Nueva Tarea' : 'Nuevo hábito',
            key: ValueKey<int>(_currentIndex), 
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      
      // 3. CUERPO PRINCIPAL LIMPIO (Sin NestedScrollView)
      body: Container(
        decoration: BoxDecoration(gradient: degradadoFondo),
        child: TabBarView(
          controller: _tabController,
          children: [
            // PESTAÑA TAREAS
            tareas.isEmpty
                ? Center(child: Text('Todo al día', style: TextStyle(color: colorPrincipal.withOpacity(0.6))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Ligero respiro superior
                    itemCount: tareas.length,
                    itemBuilder: (context, index) => TareaCard(tarea: tareas[index], tema: temaActual),
                  ),
            // PESTAÑA RUTINAS
            const _SeccionRutinasHoy(), 
          ],
        ),
      ),
    );
  }
}

// Widget extraído para mantener limpio el build principal
class _SeccionRutinasHoy extends ConsumerWidget {
  const _SeccionRutinasHoy();

  // Función de apoyo para obtener el color según el tema (Igual a la de HomeScreen)
  Color _getPrimaryColor(TemaApp tema) {
    switch (tema) {
      case TemaApp.clasico:
        return Colors.black87;
      case TemaApp.brisaMarina:
        return const Color(0xFF1E3A8A); // Azul
      case TemaApp.atardecerMinimalista:
        return const Color(0xFFC05621); // Naranja
      case TemaApp.zenClasico:
      default:
        return const Color(0xFF276749); // Verde
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listaCompleta = ref.watch(rutinaProvider);
    final temaActual = ref.watch(temaProvider);
    
    // Ahora el color principal se adapta dinámicamente a los 4 temas
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
              Text(
                'Hoy es ${DateFormat('EEEE', 'es_ES').format(DateTime.now())}', 
                style: TextStyle(
                  fontSize: 26, 
                  fontWeight: FontWeight.bold, 
                  color: colorPrincipal // Aplicado al título "Hoy es..."
                ),
              ),
              const SizedBox(height: 4),
              Text(
                rutinasDeHoy.isEmpty 
                    ? 'No hay hábitos programados.' 
                    : 'Tienes ${rutinasDeHoy.length} hábitos para hoy.',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Expanded(
          child: rutinasDeHoy.isEmpty
              ? Center(
                  child: Icon(
                    Icons.event_available_rounded, 
                    size: 80, 
                    color: colorPrincipal.withOpacity(0.15) // Aplicado al icono de fondo vacío
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rutinasDeHoy.length,
                  itemBuilder: (context, index) => RutinaCard(
                    rutina: rutinasDeHoy[index], 
                    colorTema: colorPrincipal // Pasado a la tarjeta para iconos y checkbox
                  ),
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

  @override
  Widget build(BuildContext context) {
    final tarea = widget.tarea;
    final colorBase = _getColorUrgencia(tarea.urgencia, widget.tema);
    
    // Si es el tema clásico, las tareas son blancas puro. Si no, toman el tinte pastel del tema.
    final colorTarjeta = tarea.esCompletada 
        ? Colors.white.withOpacity(0.7) 
        : (widget.tema == TemaApp.clasico ? Colors.white : colorBase.withOpacity(0.25)); 

    // --- NUEVA LÓGICA: Evaluamos si está atrasada en tiempo real ---
    final bool estaAtrasada = !tarea.esCompletada && 
                              tarea.fechaLimite != null && 
                              tarea.fechaLimite!.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 16), 
      decoration: BoxDecoration(
        color: colorTarjeta,
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(
          // En el tema clásico los bordes son un poco más sutiles si no hay urgencia alta
          color: tarea.esCompletada ? Colors.transparent : colorBase.withOpacity(widget.tema == TemaApp.clasico ? 0.6 : 0.4),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias, 
      child: Stack( // ESTE STACK YA EXISTÍA EN TU CÓDIGO
        children: [
          // 1. TU DISEÑO PRINCIPAL (InkWell)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            onLongPress: () => setState(() => _showOverlayMenu = true),
            child: Padding(
              padding: const EdgeInsets.all(4), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: Checkbox(
                      value: tarea.esCompletada,
                      activeColor: colorBase,
                      shape: const CircleBorder(), 
                      side: BorderSide(color: tarea.esCompletada ? colorBase : Colors.black45, width: 1.5),
                      onChanged: (_) => ref.read(tareaProvider.notifier).toggleTarea(tarea.id),
                    ),
                    title: Text(
                      tarea.titulo,
                      style: TextStyle(
                        fontSize: 17,
                        decoration: tarea.esCompletada ? TextDecoration.lineThrough : null,
                        color: tarea.esCompletada ? Colors.black38 : Colors.black87,
                        fontWeight: tarea.esCompletada ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                    subtitle: !tarea.esCompletada && tarea.fechaLimite != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.access_time, size: 14, color: colorBase.withOpacity(0.9)),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('EEEE, d MMM • HH:mm', 'es').format(tarea.fechaLimite!), 
                                  style: TextStyle(color: colorBase.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600)
                                ),
                              ],
                            ),
                          )
                        : null,
                    trailing: tarea.esCompletada 
                        ? null 
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            // En el tema clásico, agregamos un poco de transparencia a la píldora de urgencia
                            decoration: BoxDecoration(color: widget.tema == TemaApp.clasico ? colorBase.withOpacity(0.2) : colorBase, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              _getLabelUrgencia(tarea.urgencia), 
                              style: TextStyle(color: widget.tema == TemaApp.clasico ? colorBase : Colors.white, fontSize: 11, fontWeight: FontWeight.bold)
                            ),
                          ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _isExpanded && tarea.descripcion != null && tarea.descripcion!.isNotEmpty && !tarea.esCompletada
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(72, 0, 24, 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                tarea.descripcion!, 
                                style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.4)
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          // --- 2. NUEVO: LETRERO DE "ATRASADO" ---
          if (estaAtrasada)
            Positioned(
              top: 12,
              right: 12, // Se posiciona justo arriba de la píldora de urgencia
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(blurRadius: 4, color: Colors.black26, offset: Offset(0, 2))
                  ],
                ),
                child: const Text(
                  'ATRASADO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

          // --- 3. MENÚ OVERLAY (Tu código original) ---
          if (_showOverlayMenu)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showOverlayMenu = false),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), 
                  child: Container(
                    color: Colors.white.withOpacity(0.2), 
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildActionIcon(
                          icon: tarea.esCompletada ? Icons.undo : Icons.check_rounded,
                          color: const Color(0xFF4CAF50), 
                          onTap: () {
                            ref.read(tareaProvider.notifier).toggleTarea(tarea.id);
                            setState(() => _showOverlayMenu = false);
                          },
                        ),
                        _buildActionIcon(
                          icon: Icons.edit_rounded,
                          color: Colors.blueGrey,
                          onTap: () {
                            setState(() => _showOverlayMenu = false);
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => AddTareaModal(tareaAEditar: tarea),
                            );
                          },
                        ),
                        _buildActionIcon(
                          icon: Icons.delete_rounded,
                          color: Colors.redAccent,
                          onTap: () {
                            setState(() => _showOverlayMenu = false);
                            Future.delayed(const Duration(milliseconds: 150), () {
                              ref.read(tareaProvider.notifier).deleteTarea(tarea.id);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionIcon({required IconData icon, required Color color, required VoidCallback onTap}) {
    return CircleAvatar(
      backgroundColor: Colors.white,
      radius: 28,
      child: IconButton(
        icon: Icon(icon, color: color, size: 28), 
        onPressed: onTap
      ),
    );
  }

  Color _getColorUrgencia(int urgencia, TemaApp tema) {
    if (tema == TemaApp.clasico) {
      // PALETA ORIGINAL
      switch (urgencia) {
        case 1: return Colors.teal; 
        case 2: return Colors.blue; 
        case 3: return Colors.orange; 
        case 4: return Colors.red; 
        default: return Colors.grey;
      }
    } else if (tema == TemaApp.zenClasico) {
      switch (urgencia) {
        case 1: return const Color(0xFFA5C4A6); 
        case 2: return const Color(0xFF80A681); 
        case 3: return const Color(0xFF5A855C); 
        case 4: return const Color(0xFF3B633D); 
        default: return Colors.grey;
      }
    } else if (tema == TemaApp.brisaMarina) {
      switch (urgencia) {
        case 1: return const Color(0xFF90CDF4); 
        case 2: return const Color(0xFF63B3ED); 
        case 3: return const Color(0xFF3182CE); 
        case 4: return const Color(0xFF2B6CB0); 
        default: return Colors.grey;
      }
    } else { 
      switch (urgencia) {
        case 1: return const Color(0xFFFBD38D); 
        case 2: return const Color(0xFFF6AD55); 
        case 3: return const Color(0xFFDD6B20); 
        case 4: return const Color(0xFFC05621); 
        default: return Colors.grey;
      }
    }
  }

  String _getLabelUrgencia(int urgencia) {
    switch (urgencia) {
      case 1: return 'BAJO';
      case 2: return 'MEDIO';
      case 3: return 'ALTO';
      case 4: return 'MUY ALTO';
      default: return '???';
    }
  }
}