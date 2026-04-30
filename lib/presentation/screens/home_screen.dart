import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:ui'; 
import '../../providers/tarea_provider.dart';
import '../../models/tarea.dart';
import '../widgets/add_tarea_modal.dart';
import '../../providers/rutina_provider.dart';
import '../widgets/rutina_card.dart';
import '../widgets/add_rutina_modal.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // --- DEGRADADOS Y FONDOS ---
  Gradient _getDegradadoFondo(TemaApp tema) {
    if (tema == TemaApp.clasico) {
      // Fondo blanco puro para el tema original
      return const LinearGradient(
        colors: [Colors.white, Colors.white] 
      );
    } else if (tema == TemaApp.brisaMarina) {
      return const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter, 
        colors: [Color(0xFFF0F8FF), Color(0xFF9FB8D0)]
      );
    } else if (tema == TemaApp.atardecerMinimalista) {
      return const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter, 
        colors: [Color(0xFFFFF9F5), Color(0xFFE5B270)]
      );
    }
    // Zen Clásico
    return const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter, 
      colors: [Color(0xFFF2F7F2), Color(0xFF8BA888)]
    );
  }

  // --- COLORES PRINCIPALES ---
  Color _getColorPrincipal(TemaApp tema) {
    if (tema == TemaApp.clasico) return Colors.black87; // Negro original
    if (tema == TemaApp.brisaMarina) return const Color(0xFF1E3A8A); 
    if (tema == TemaApp.atardecerMinimalista) return const Color(0xFFC05621); 
    return const Color(0xFF276749); 
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return DefaultTabController(
  length: 2, // Le decimos que habrá 2 pestañas
  child: Scaffold(
    // El FAB se queda exactamente igual, flotando sobre todo
    floatingActionButton: Builder(
  builder: (fabContext) {
    // Usamos fabContext para leer la pestaña actual sin errores
    return FloatingActionButton.extended(
      onPressed: () {
        final int index = DefaultTabController.of(fabContext).index;
        
        showModalBottomSheet(
          context: context, // El context original para abrir el modal
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => index == 0 ? const AddTareaModal() : const AddRutinaModal(),
        );
      },
      elevation: 4,
      backgroundColor: colorPrincipal,
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: Text(
        // Cambia el texto del botón dependiendo de la pestaña
        DefaultTabController.of(fabContext).index == 0 ? 'Nueva Tarea' : 'Nueva Rutina', 
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
      ),
    );
  }
),
    
    // Mantenemos tu contenedor con el degradado de fondo
    body: Container(
      decoration: BoxDecoration(gradient: degradadoFondo),
      child: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return [
            SliverAppBar(
              floating: true,
              pinned: true, // Fijamos el AppBar para que las pestañas no desaparezcan al scrollear
              backgroundColor: Colors.transparent,
              elevation: 0,
              // Cambié "Mis Tareas" por el nombre de la app, ya que ahora engloba tareas y rutinas
              title: Text('FocusFlow', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5, color: colorPrincipal, fontSize: 24)),
              
              // Tus menús originales se quedan intactos
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
                const SizedBox(width: 8),
              ],
              
              bottom: TabBar(
                // 1. Hacemos que el texto inactivo se note más apagado en el tema clásico
                labelColor: colorPrincipal,
                unselectedLabelColor: temaActual == TemaApp.clasico 
                    ? Colors.grey.shade400 
                    : colorPrincipal.withOpacity(0.5),
                    
                indicatorSize: TabBarIndicatorSize.tab,
                
                // 2. Modificamos el diseño de la pestaña activa (Indicator)
                indicator: BoxDecoration(
                  // En el clásico usamos blanco puro, en los demás transparencia
                  color: temaActual == TemaApp.clasico 
                      ? Colors.white 
                      : Colors.white.withOpacity(0.6), 
                  
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(15),
                    topRight: Radius.circular(15),
                  ),
                  
                  // 3. EL TRUCO VISUAL: Un borde sutil solo para el tema clásico
                  border: temaActual == TemaApp.clasico
                      ? Border(
                          top: BorderSide(color: Colors.grey.shade300, width: 1.5),
                          left: BorderSide(color: Colors.grey.shade300, width: 1.5),
                          right: BorderSide(color: Colors.grey.shade300, width: 1.5),
                          // NO ponemos borde abajo para que se "fusione" con el contenido
                        )
                      : null, 
                  
                  // 4. Una sombra suave hacia arriba para darle relieve de carpeta real
                  boxShadow: temaActual == TemaApp.clasico
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 4,
                            offset: const Offset(0, -3), // Sombra apuntando hacia arriba
                          )
                        ]
                      : null,
                ),
                tabs: const [
                  Tab(icon: Icon(Icons.check_circle_outline), text: 'Tareas'),
                  Tab(icon: Icon(Icons.repeat_rounded), text: 'Rutinas'),
                ],
              ),
            ),
          ];
        },
        
        // EL CONTENIDO DE LAS PESTAÑAS
        body: TabBarView(
          children: [
            // --- PESTAÑA 1: TAREAS ---
            tareas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(temaActual == TemaApp.clasico ? Icons.task_alt : Icons.spa_outlined, size: 80, color: colorPrincipal.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        Text(temaActual == TemaApp.clasico ? 'Todo al día' : 'Mente en calma', style: TextStyle(fontSize: 18, color: colorPrincipal.withOpacity(0.6), fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: tareas.length,
                    itemBuilder: (context, index) {
                      return TareaCard(tarea: tareas[index], tema: temaActual);
                    },
                  ),

            // Busca el "Cascarón temporal" de Rutinas y cámbialo por esto:
            Consumer(
              builder: (context, ref, child) {
                final listaRutinas = ref.watch(rutinaProvider);
                return listaRutinas.isEmpty
                    ? Center(child: Text('No hay rutinas aún', style: TextStyle(color: colorPrincipal)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: listaRutinas.length,
                        itemBuilder: (context, index) => RutinaCard(
                          rutina: listaRutinas[index],
                          colorTema: colorPrincipal,
                        ),
                      );
              },
            ),
          ],
        ),
      ),
    ),
  ),
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