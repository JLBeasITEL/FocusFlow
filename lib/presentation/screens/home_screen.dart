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
import '../../models/rutina.dart';
import '../../providers/nota_provider.dart';
import '../widgets/add_tarea_modal.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/monedas_provider.dart';
import '../widgets/rutina_card.dart';
import 'rutina_form_screen.dart';
import '../../providers/tema_provider.dart';
import 'dart:async';
import '../widgets/onboarding_permisos.dart';
import '../../services/notificaciones_service.dart';
import '../widgets/progreso_rutinas_bar.dart';
import '../../core/app_messenger.dart';
import '../../core/colores_estado_rutina.dart';
import '../widgets/nota_dialog.dart';
import '../widgets/grupo_notas_card.dart';
import '../widgets/post_it_card.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../core/colores_estado_tarea.dart';
import '../widgets/tarea_card_landscape.dart';
import '../widgets/rutina_card_landscape.dart';
import '../widgets/home_sidebar_landscape.dart';
import '../widgets/overflow_scrollbar.dart';
import '../../core/temporizador_rutina_dialogo.dart';

// Puente para pedirle a HomeScreen que cambie de pestaña desde fuera del
// árbol de widgets (el handler de clicks del widget de Rutinas en
// main.dart, que no tiene un BuildContext propio). _HomeScreenState lo
// escucha en initState y lo vuelve a null en cuanto lo consume, así que es
// un "comando" de un solo uso, no un estado persistente de la pestaña
// actual (eso lo sigue siendo _currentIndex).
class TabSolicitadaWidgetNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void solicitar(int indice) => state = indice;
  void limpiar() => state = null;
}

final tabSolicitadaWidgetProvider = NotifierProvider<TabSolicitadaWidgetNotifier, int?>(
  TabSolicitadaWidgetNotifier.new,
);

// Pestaña activa, persistida en el ProviderContainer (que sobrevive aunque
// HomeScreen se destruya y se vuelva a montar — cosa que puede pasar, por
// ejemplo, cuando el widget de Rutinas trae la app al frente mientras ya
// estaba corriendo: se observó que en ese momento HomeScreen a veces se
// remonta de cero, perdiendo _currentIndex y el TabController local, y
// volviendo siempre a la pestaña 0 aunque tabSolicitadaWidgetProvider ya
// hubiera pedido correctamente la pestaña de Rutinas un instante antes).
// _HomeScreenState arranca su TabController leyendo este valor en vez de
// hardcodear 0, así que un remont sigue mostrando la pestaña correcta.
class CurrentTabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void actualizar(int indice) => state = indice;
}

final currentTabIndexProvider = NotifierProvider<CurrentTabIndexNotifier, int>(
  CurrentTabIndexNotifier.new,
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

// Un ítem del tablero de notas: o una nota suelta, o un grupo de notas
// (ver _buildTabNotas). notasGrupo es la misma lista referenciada en el
// mapa gruposPorNombre mientras se arma el tablero, así que se completa
// sola a medida que se recorren las notas de ese grupo.
class _ItemTablero {
  final NotaPostIt? notaSuelta;
  final String? nombreGrupo;
  final List<NotaPostIt>? notasGrupo;

  _ItemTablero.suelta(NotaPostIt nota)
      : notaSuelta = nota,
        nombreGrupo = null,
        notasGrupo = null;

  _ItemTablero.grupo(String nombre, List<NotaPostIt> notas)
      : notaSuelta = null,
        nombreGrupo = nombre,
        notasGrupo = notas;

  bool get esGrupo => nombreGrupo != null;
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;
  // Grupo que se está arrastrando en este momento para reordenarlo (o null
  // si no hay ningún arrastre en curso). Se usa para colapsarlo mientras
  // se mueve y devolverlo a su estado previo al soltarlo.
  String? _grupoEnArrastre;

  // Modo de selección múltiple de notas para armar un grupo (ver
  // _buildTabNotas / mostrarDialogoNota en widgets/nota_dialog.dart).
  bool _modoSeleccionNotas = false;
  final Set<String> _notasSeleccionadas = {};

  // Rutina cuyo detalle (título completo + descripción) se muestra en el
  // panel superpuesto al grid landscape (ver _buildContenidoRutinasLandscape
  // más abajo). Solo tiene sentido en esa orientación: portrait resuelve lo
  // mismo expandiendo la tarjeta in-place, sin este estado.
  Rutina? _rutinaLandscapeSeleccionada;

  // Un controller propio por sección (Tareas/Rutinas/Notas), reutilizado
  // entre sus variantes portrait/landscape (nunca están montadas al mismo
  // tiempo). Sin esto, cada ListView/GridView sin "controller" explícito se
  // registra como scrollable "primary" del PrimaryScrollController que
  // Scaffold comparte para toda esta pantalla; como el TabBarView de
  // portrait mantiene las 3 pestañas montadas a la vez (no son lazy), las 3
  // terminaban "primary" al mismo tiempo sobre ESE MISMO controller. Antes
  // de agregar los Scrollbar nadie leía esa posición ambigua, así que no se
  // notaba: Scrollbar sí la lee en cada frame para dibujar el thumb, y con
  // 3 posiciones peleando por un solo controller el hilo de UI se colgaba
  // (ANR real, confirmado en logcat: "Input dispatching timed out... MOVE").
  final ScrollController _scrollTareas = ScrollController();
  final ScrollController _scrollRutinas = ScrollController();
  final ScrollController _scrollNotas = ScrollController();

  // Suscripción manual (fuera de build()) a tabSolicitadaWidgetProvider: el
  // handler de clicks del widget de Rutinas en main.dart la usa para pedir
  // "andá a la pestaña de Rutinas" sin tener un BuildContext propio.
  late final ProviderSubscription<int?> _tabSolicitadaWidgetSub;

  @override
  void initState() {
    super.initState();
    // initialIndex viene de currentTabIndexProvider (no un 0 fijo) para que
    // esta pestaña sobreviva a un remount de HomeScreen — ver el comentario
    // de currentTabIndexProvider más arriba.
    _currentIndex = ref.read(currentTabIndexProvider);
    _tabController = TabController(length: 3, vsync: this, initialIndex: _currentIndex);

    _tabSolicitadaWidgetSub = ref.listenManual<int?>(tabSolicitadaWidgetProvider, (previo, indice) {
      if (indice != null) {
        _tabController.animateTo(indice);
        ref.read(tabSolicitadaWidgetProvider.notifier).limpiar();
      }
    });

    _tabController.animation?.addListener(() {
      final int proximoIndex = _tabController.animation!.value.round();
      if (_currentIndex != proximoIndex) {
        setState(() => _currentIndex = proximoIndex);
        ref.read(currentTabIndexProvider.notifier).actualizar(proximoIndex);
      }
    });

    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _currentIndex != _tabController.index) {
        setState(() => _currentIndex = _tabController.index);
        ref.read(currentTabIndexProvider.notifier).actualizar(_tabController.index);
      }
    });

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

        // A diferencia de las rutinas (que RutinaNotifier.build() ya
        // reprograma por su cuenta al abrir la app, ver el comentario de
        // "FIX APLICADO" abajo), nada más vuelve a programar las alertas de
        // las tareas tras este cancelAll(): sin esto, todas las tareas con
        // fecha límite se quedaban sin ninguna alarma (incluidas las de
        // cambio de nivel de urgencia) hasta que el usuario editara o
        // marcara/desmarcara cada una manualmente.
        await ref.read(tareaProvider.notifier).resincronizarTodasLasAlarmas();
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

  @override
  void dispose() {
    _tabSolicitadaWidgetSub.close();
    _tabController.dispose();
    _scrollTareas.dispose();
    _scrollRutinas.dispose();
    _scrollNotas.dispose();
    super.dispose();
  }

  String _labelOrden(TipoOrden tipo) => tipo.label;

  // =====================================================================
  // LAYOUT HORIZONTAL (landscape): header propio + sidebar + grilla, en
  // vez del AppBar+TabBar / TabBarView de portrait. Reutiliza el mismo
  // estado (_currentIndex, _tabController) y, para Notas, el mismo
  // _buildTabNotas de arriba — solo Tareas y Rutinas necesitan un
  // contenido nuevo porque su tarjeta compacta no existe en portrait.
  // =====================================================================

  Widget _buildBodyLandscape({
    required TemaApp temaActual,
    required Color colorPrincipal,
    required List<Tarea> tareas,
    required bool vistaAgrupada,
    required List<String> ordenGrupos,
    required List<NotaPostIt> notasGuardadas,
  }) {
    return Column(
      children: [
        _buildHeaderLandscape(temaActual, colorPrincipal, notasGuardadas.length),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeSidebarLandscape(currentIndex: _currentIndex, tema: temaActual),
                const SizedBox(width: 16),
                Expanded(
                  child: switch (_currentIndex) {
                    0 => _buildContenidoTareasLandscape(tareas, vistaAgrupada, ordenGrupos, temaActual, colorPrincipal),
                    1 => _buildContenidoRutinasLandscape(temaActual, colorPrincipal),
                    _ => _buildTabNotas(colorPrincipal, notasGuardadas, esLandscape: true),
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderLandscape(TemaApp temaActual, Color colorPrincipal, int totalNotas) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Text('FocusFlow', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: colorPrincipal)),
          const SizedBox(width: 20),
          _PildoraTab(icon: Icons.check_circle_outline, label: 'Tareas', seleccionado: _currentIndex == 0, tema: temaActual, onTap: () => _tabController.animateTo(0)),
          const SizedBox(width: 8),
          _PildoraTab(icon: Icons.repeat_rounded, label: 'Rutinas', seleccionado: _currentIndex == 1, tema: temaActual, onTap: () => _tabController.animateTo(1)),
          const SizedBox(width: 8),
          _PildoraTab(icon: Icons.sticky_note_2_rounded, label: 'Notas', seleccionado: _currentIndex == 2, tema: temaActual, onTap: () => _tabController.animateTo(2)),
          const Spacer(),
          if (_currentIndex == 1) ...[
            const _BadgeMonedasRacha(),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GestorRutinasScreen(colorTema: colorPrincipal))),
              icon: Icon(Icons.mode_edit_outline_rounded, size: 16, color: colorPrincipal),
              label: Text('Editar rutina', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorPrincipal.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (_currentIndex == 2 && !_modoSeleccionNotas && totalNotas > 4) ...[
            GestureDetector(
              onTap: () => setState(() => _modoSeleccionNotas = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: colorPrincipal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.style_rounded, size: 18, color: colorPrincipal),
                    const SizedBox(width: 6),
                    Text('Agrupar notas', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: colorPrincipal),
            tooltip: 'Configuraciones',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildContenidoTareasLandscape(List<Tarea> tareas, bool vistaAgrupada, List<String> ordenGrupos, TemaApp temaActual, Color colorPrincipal) {
    if (tareas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Nada por aquí, disfruta de tu día.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorPrincipal.withValues(alpha: 0.6), fontSize: 15, height: 1.4),
          ),
        ),
      );
    }

    if (!vistaAgrupada) {
      return _gridTareasLandscape(tareas, temaActual, controller: _scrollTareas);
    }

    // Mismo agrupado y orden de carpetas que la vista agrupada de portrait
    // (ver _GrupoTareasSection más abajo), simplificado sin colapsar ni
    // reordenar por arrastre: en landscape hay poco alto disponible como
    // para que valga la pena esa interacción.
    final mapaGrupos = <String, List<Tarea>>{};
    for (var tarea in tareas) {
      mapaGrupos.putIfAbsent(tarea.grupo, () => []).add(tarea);
    }
    final listaGrupos = mapaGrupos.keys.toList()
      ..sort((a, b) {
        final ia = ordenGrupos.indexOf(a);
        final ib = ordenGrupos.indexOf(b);
        if (ia == -1 && ib == -1) return a.compareTo(b);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });

    return OverflowScrollbar(
      controller: _scrollTareas,
      child: ListView.builder(
      controller: _scrollTareas,
      padding: EdgeInsets.only(bottom: 100 + MediaQuery.of(context).padding.bottom),
      itemCount: listaGrupos.length,
      itemBuilder: (context, index) {
        final grupo = listaGrupos[index];
        final tareasDelGrupo = mapaGrupos[grupo]!;
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_rounded, size: 20, color: colorPrincipal),
                  const SizedBox(width: 8),
                  Text(grupo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: temaActual.colorTituloGrupo ?? temaActual.colorTextoSuperficie)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: colorPrincipal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: Text('${tareasDelGrupo.length}', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _gridTareasLandscape(tareasDelGrupo, temaActual, shrinkWrap: true),
            ],
          ),
        );
      },
      ),
    );
  }

  Widget _gridTareasLandscape(List<Tarea> tareas, TemaApp temaActual, {bool shrinkWrap = false, ScrollController? controller}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double anchoTarget = 260;
        const double espaciado = 12;
        final int columnas = math.max(2, ((constraints.maxWidth + espaciado) / (anchoTarget + espaciado)).floor());
        final grid = GridView.builder(
          controller: shrinkWrap ? null : controller,
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: shrinkWrap ? EdgeInsets.zero : EdgeInsets.only(bottom: 100 + MediaQuery.of(context).padding.bottom),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            mainAxisSpacing: espaciado,
            crossAxisSpacing: espaciado,
            childAspectRatio: 2.9,
          ),
          itemCount: tareas.length,
          itemBuilder: (context, index) => TareaLandscapeCard(tarea: tareas[index], tema: temaActual),
        );
        return shrinkWrap ? grid : OverflowScrollbar(controller: controller!, child: grid);
      },
    );
  }

  Widget _buildContenidoRutinasLandscape(TemaApp temaActual, Color colorPrincipal) {
    final listaCompleta = ref.watch(rutinaProvider);
    final int diaActual = DateTime.now().weekday - 1;
    final rutinasDeHoy = listaCompleta.where((r) => r.horarios.containsKey(diaActual) && r.activa).toList();

    // Re-resuelve la selección contra la lista fresca de este build (por
    // id, no por la referencia guardada): si la rutina se editó desde
    // "Editar rutina" mientras el panel estaba abierto, el panel muestra el
    // dato actualizado en vez de quedarse con la instancia vieja. Si ya no
    // aparece hoy (se desactivó, se borró, o cambió el día), la selección
    // se limpia sola sin necesidad de que el usuario cierre el panel a mano.
    Rutina? rutinaSeleccionada;
    if (_rutinaLandscapeSeleccionada != null) {
      for (final r in rutinasDeHoy) {
        if (r.id == _rutinaLandscapeSeleccionada!.id) {
          rutinaSeleccionada = r;
          break;
        }
      }
      if (rutinaSeleccionada == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _rutinaLandscapeSeleccionada = null);
        });
      }
    }

    if (rutinasDeHoy.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Cada que agregas un nuevo hábito a tu vida,\nte acercas más a la persona que quieres ser.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorPrincipal.withValues(alpha: 0.6), fontSize: 15, height: 1.4),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tarjeta compacta (RutinaLandscapeCard usa mainAxisSize.min, ~130px
        // de alto real de contenido): childAspectRatio 1.05 forzaba celdas
        // casi cuadradas con mucho espacio vacío debajo del texto, dejando
        // ver solo 1-2 tarjetas por pantalla. mainAxisExtent fija el alto de
        // celda directamente en vez de derivarlo del ancho (que varía con
        // columnas/dispositivo), así el margen sobre el contenido real es
        // predecible y no se desborda en pantallas angostas.
        const double anchoTarget = 140;
        const double espaciado = 12;
        final int columnas = math.max(2, ((constraints.maxWidth + espaciado) / (anchoTarget + espaciado)).floor());
        // El grid queda siempre montado como capa base (conserva la
        // posición de scroll al abrir/cerrar el panel); el panel de detalle
        // se superpone encima con un AnimatedSwitcher cuando hay selección,
        // key'eado por id de rutina para que tocar OTRA tarjeta con el
        // panel ya abierto haga un crossfade al contenido nuevo en vez de
        // cerrar y reabrir.
        return Stack(
          children: [
            // Se mantiene montado (conserva scroll) mientras el panel está
            // abierto, pero deja de pintarse y de recibir toques: sin esto
            // las tarjetas de atrás asomaban por las esquinas redondeadas
            // del panel. Se oculta del todo (no se atenúa) porque dejarlo
            // semi-visible sugeriría que sigue siendo tocable cuando en
            // realidad el IgnorePointer ya se lo impide — una promesa falsa.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: rutinaSeleccionada == null ? 1 : 0,
              child: IgnorePointer(
                ignoring: rutinaSeleccionada != null,
                child: OverflowScrollbar(
                  controller: _scrollRutinas,
                  child: GridView.builder(
                    controller: _scrollRutinas,
                    padding: EdgeInsets.only(bottom: 100 + MediaQuery.of(context).padding.bottom),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columnas,
                      mainAxisSpacing: espaciado,
                      crossAxisSpacing: espaciado,
                      mainAxisExtent: 148,
                    ),
                    itemCount: rutinasDeHoy.length,
                    itemBuilder: (context, index) {
                      final rutina = rutinasDeHoy[index];
                      return RutinaLandscapeCard(
                        rutina: rutina,
                        tema: temaActual,
                        onTap: () => setState(() {
                          _rutinaLandscapeSeleccionada = _rutinaLandscapeSeleccionada?.id == rutina.id ? null : rutina;
                        }),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: rutinaSeleccionada == null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: rutinaSeleccionada == null
                      ? const SizedBox.shrink(key: ValueKey('sin-seleccion'))
                      : _PanelDetalleRutinaLandscape(
                          key: ValueKey(rutinaSeleccionada.id),
                          rutina: rutinaSeleccionada,
                          tema: temaActual,
                          onCerrar: () => setState(() => _rutinaLandscapeSeleccionada = null),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- VISTA DE NOTAS ESTILO TABLERO ---
  Widget _buildTabNotas(Color colorPrincipal, List<NotaPostIt> notasActuales, {bool esLandscape = false}) {
    if (notasActuales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Este espacio empuja el texto hacia abajo del loto central (solo vertical).
            // Notas no tiene la barra de filtros que sí tiene Tareas, así que
            // necesita un poco más de empuje para quedar a la misma altura.
            if (!esLandscape) const SizedBox(height: 156),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Tu tablero está vacío.\nAgrega un post-it rápido.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorPrincipal.withValues(alpha: 0.6), fontSize: 15, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    // Junta las notas de un mismo grupo en un solo ítem del tablero
    // (colocado donde apareció la primera nota de ese grupo) y deja las
    // demás sueltas. Las listas dentro de gruposPorNombre son las mismas
    // instancias referenciadas por cada _ItemTablero.grupo, así que se
    // van llenando a medida que se recorren las notas.
    final Map<String, List<NotaPostIt>> gruposPorNombre = {};
    final List<_ItemTablero> items = [];
    for (final nota in notasActuales) {
      if (nota.grupoNombre.isEmpty) {
        items.add(_ItemTablero.suelta(nota));
      } else {
        final notasDelGrupo = gruposPorNombre.putIfAbsent(nota.grupoNombre, () {
          final lista = <NotaPostIt>[];
          items.add(_ItemTablero.grupo(nota.grupoNombre, lista));
          return lista;
        });
        notasDelGrupo.add(nota);
      }
    }

    // Cada ítem (nota suelta o grupo) pesa 1 celda unitaria: los grupos se
    // dibujan del mismo tamaño que una nota suelta. Con eso,
    // _calcularColumnasOptimas elige cuántas columnas usar para que las
    // notas llenen el ancho y el alto disponibles (que cambian con el
    // tamaño de pantalla y la orientación, ya que vienen del LayoutBuilder)
    // dejando el mínimo espacio vacío.
    final int totalCeldas = items.length;
    const double espaciado = 12;
    const double padHorizontal = 20;
    const double padTop = 8;
    // 100 deja libre el área que tapa el FAB; se le suma el inset real del
    // sistema (barra de gestos) para que en edge-to-edge tampoco quede tapado.
    final double padBottom = 100 + MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        _buildBarraSeleccionNotas(colorPrincipal, notasActuales.length, mostrarBotonAgrupar: !esLandscape),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double anchoDisponible = constraints.maxWidth - padHorizontal * 2;
              final double altoDisponible = constraints.maxHeight - padTop - padBottom;

              final int columnas = _calcularColumnasOptimas(
                totalCeldas: totalCeldas,
                anchoDisponible: anchoDisponible,
                altoDisponible: altoDisponible,
                espaciado: espaciado,
              );
              final double tamanoCelda = columnas > 0 ? (anchoDisponible - espaciado * (columnas - 1)) / columnas : anchoDisponible;

              return OverflowScrollbar(
                controller: _scrollNotas,
                child: SingleChildScrollView(
                controller: _scrollNotas,
                padding: EdgeInsets.fromLTRB(padHorizontal, padTop, padHorizontal, padBottom),
                child: StaggeredGrid.count(
                  crossAxisCount: columnas,
                  mainAxisSpacing: espaciado,
                  crossAxisSpacing: espaciado,
                  children: [
                    for (final item in items)
                      if (item.esGrupo)
                        StaggeredGridTile.count(
                          key: ValueKey('grupo_${item.nombreGrupo}'),
                          crossAxisCellCount: 1,
                          mainAxisCellCount: 1,
                          child: DragTarget<String>(
                            onWillAcceptWithDetails: (details) => !_modoSeleccionNotas,
                            onAcceptWithDetails: (details) =>
                                ref.read(notaProvider.notifier).agruparNotas([details.data], item.nombreGrupo!),
                            builder: (context, candidateData, rejectedData) => TarjetaGrupoNotas(
                              nombreGrupo: item.nombreGrupo!,
                              notas: item.notasGrupo!,
                              columnasTotales: columnas,
                              deshabilitada: _modoSeleccionNotas,
                              resaltada: candidateData.isNotEmpty,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => GrupoNotasDetalleScreen(nombreGrupo: item.nombreGrupo!)),
                              ),
                            ),
                          ),
                        )
                      else
                        StaggeredGridTile.count(
                          key: ValueKey(item.notaSuelta!.id),
                          crossAxisCellCount: 1,
                          mainAxisCellCount: 1,
                          child: _buildNotaArrastrable(item.notaSuelta!, notasActuales, columnas, tamanoCelda),
                        ),
                  ],
                ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Nota suelta arrastrable del tablero: mantener presionada e iniciar el
  // arrastre permite soltarla sobre otra nota (cambia de posición en la
  // lista) o sobre una tarjeta de grupo (se suma a ese grupo). Deshabilitado
  // en modo selección para no pelear con el toggle de checkbox.
  Widget _buildNotaArrastrable(NotaPostIt nota, List<NotaPostIt> notasActuales, int columnas, double tamanoCelda) {
    final Widget tarjeta = PostItCard(
      nota: nota,
      index: notasActuales.indexOf(nota),
      columnasTotales: columnas,
      modoSeleccion: _modoSeleccionNotas,
      seleccionada: _notasSeleccionadas.contains(nota.id),
      onToggleSeleccion: () => _alternarSeleccionNota(nota.id),
      onTapEditar: () => mostrarDialogoNota(context, ref, idAEditar: nota.id),
      onDelete: () => _eliminarNota(nota),
      onToggleDestacada: () => alternarDestacadaConFeedback(context, ref, nota.id),
    );

    if (_modoSeleccionNotas) return tarjeta;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != nota.id,
      onAcceptWithDetails: (details) => ref.read(notaProvider.notifier).moverNota(details.data, nota.id),
      builder: (context, candidateData, rejectedData) {
        final bool resaltada = candidateData.isNotEmpty;
        return LongPressDraggable<String>(
          data: nota.id,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: tamanoCelda, height: tamanoCelda, child: Opacity(opacity: 0.85, child: tarjeta)),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: tarjeta),
          child: AnimatedScale(
            scale: resaltada ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: tarjeta,
          ),
        );
      },
    );
  }

  // Tamaño mínimo de celda (dp): por debajo de esto una nota deja de ser
  // usable (texto ilegible, clip de borrado imposible de tocar, contenido
  // desbordado). PostItCard escala su fuente con columnasTotales pero la
  // clampea en 8pt y tiene paddings fijos que no encogen más allá de
  // cierto punto, así que celdas por debajo de ~140dp ya no alcanzan para
  // título + 3 renglones de checklist sin desbordar (visto en landscape,
  // donde el alto disponible es chico y el algoritmo agregaba columnas de
  // más para evitar el scroll). Si hay demasiadas notas para entrar todas
  // sin cruzar este piso, se prioriza el tamaño mínimo y el resto se
  // alcanza haciendo scroll (el grid ya vive en un SingleChildScrollView).
  static const double _tamanoMinimoCelda = 140.0;

  // Prueba cada cantidad de columnas viable y elige la que produce las
  // celdas cuadradas más grandes sin que el total de filas necesite más
  // alto del disponible: así las notas se ajustan al tamaño de pantalla y
  // a la orientación del dispositivo dejando el mínimo espacio vacío.
  int _calcularColumnasOptimas({
    required int totalCeldas,
    required double anchoDisponible,
    required double altoDisponible,
    required double espaciado,
  }) {
    if (totalCeldas <= 0 || anchoDisponible <= 0) return 1;
    const int minColumnas = 1;
    final int columnasPorAncho = ((anchoDisponible + espaciado) / (_tamanoMinimoCelda + espaciado)).floor();
    final int maxColumnas = math.max(minColumnas, math.min(totalCeldas, columnasPorAncho));

    int mejorColumnas = minColumnas;
    double mejorTamanoCelda = 0;

    for (int c = minColumnas; c <= maxColumnas; c++) {
      final double tamanoCelda = (anchoDisponible - espaciado * (c - 1)) / c;
      if (tamanoCelda <= 0) continue;
      final int filas = (totalCeldas / c).ceil();
      final double altoNecesario = filas * tamanoCelda + espaciado * (filas - 1);

      if (altoNecesario <= altoDisponible && tamanoCelda > mejorTamanoCelda) {
        mejorColumnas = c;
        mejorTamanoCelda = tamanoCelda;
      }
    }

    // Si ninguna combinación entra sin scroll (pantalla chica o muchas
    // notas), nos quedamos con la que exige más columnas: son las celdas
    // más chicas, pero las que menos alto ocupan.
    if (mejorTamanoCelda == 0) mejorColumnas = maxColumnas;

    return mejorColumnas;
  }

  // Barra sobre el tablero: fuera de modo selección, solo aparece el botón
  // "Agrupar notas" y solo cuando ya hay más de 4 notas creadas (umbral
  // pedido para no saturar tableros chicos con una opción que no hace
  // falta todavía). En modo selección, se reemplaza por el contador y las
  // acciones de cancelar/crear grupo.
  // mostrarBotonAgrupar en false: en landscape el botón vive en el header
  // (junto a los 3 puntos) para no quitarle alto al tablero, así que este
  // widget solo debe dibujar la barra de selección activa, no el trigger.
  Widget _buildBarraSeleccionNotas(Color colorPrincipal, int totalNotas, {bool mostrarBotonAgrupar = true}) {
    if (_modoSeleccionNotas) {
      final puedeCrear = _notasSeleccionadas.length >= 2;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            TextButton(onPressed: _cancelarSeleccionNotas, child: const Text('Cancelar')),
            Expanded(
              child: Text(
                '${_notasSeleccionadas.length} seleccionada${_notasSeleccionadas.length == 1 ? '' : 's'}',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: colorPrincipal),
              ),
            ),
            TextButton(
              onPressed: puedeCrear ? _confirmarCrearGrupoNotas : null,
              child: const Text('Crear grupo'),
            ),
          ],
        ),
      );
    }

    if (!mostrarBotonAgrupar || totalNotas <= 4) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () => setState(() => _modoSeleccionNotas = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: colorPrincipal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.style_rounded, size: 18, color: colorPrincipal),
                const SizedBox(width: 6),
                Text('Agrupar notas', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _alternarSeleccionNota(String id) {
    setState(() {
      if (_notasSeleccionadas.contains(id)) {
        _notasSeleccionadas.remove(id);
      } else {
        _notasSeleccionadas.add(id);
      }
    });
  }

  void _cancelarSeleccionNotas() {
    setState(() {
      _modoSeleccionNotas = false;
      _notasSeleccionadas.clear();
    });
  }

  // Punto de entrada del botón "Crear grupo": si ya existen grupos, primero
  // deja elegir entre sumar las notas seleccionadas a uno existente o armar
  // uno nuevo. Si todavía no hay ninguno, va directo al diálogo de nombre
  // (no tiene sentido mostrar una lista vacía).
  Future<void> _confirmarCrearGrupoNotas() async {
    final gruposExistentes = ref.read(notaProvider).map((n) => n.grupoNombre).where((g) => g.isNotEmpty).toSet().toList()..sort();

    String? nombreElegido;
    if (gruposExistentes.isEmpty) {
      nombreElegido = await _pedirNombreGrupoNuevo();
    } else {
      final opcion = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Agregar a grupo'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('Crear grupo nuevo'),
                  onTap: () => Navigator.pop(dialogContext, '__nuevo__'),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: gruposExistentes.length,
                    itemBuilder: (context, index) {
                      final nombre = gruposExistentes[index];
                      return ListTile(
                        leading: const Icon(Icons.folder_copy_rounded),
                        title: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(dialogContext, nombre),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          ],
        ),
      );

      if (opcion == null) return;
      nombreElegido = opcion == '__nuevo__' ? await _pedirNombreGrupoNuevo() : opcion;
    }

    final nombreLimpio = nombreElegido?.trim() ?? '';
    if (nombreLimpio.isEmpty) return;

    ref.read(notaProvider.notifier).agruparNotas(_notasSeleccionadas.toList(), nombreLimpio);
    _cancelarSeleccionNotas();
  }

  Future<String?> _pedirNombreGrupoNuevo() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombre del grupo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ej. Recetas, Ideas...'),
          onSubmitted: (val) => Navigator.pop(dialogContext, val),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Crear')),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final tareasOriginales = ref.watch(tareaProvider);
    final tipoOrden = ref.watch(ordenProvider);
    final vistaAgrupada = ref.watch(vistaAgrupadaProvider);
    final ordenGrupos = ref.watch(ordenGruposProvider);
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

    // El layout horizontal (sidebar + grilla) solo se usa con el dispositivo
    // apaisado; en vertical la app se ve exactamente igual que siempre.
    final bool esLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: colorFondoAppBar,

      appBar: esLandscape ? null : AppBar(
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

      // Oculto mientras se seleccionan notas para armar un grupo (agregar
      // una nota nueva en ese momento no tiene sentido y estorba el flujo)
      // o mientras el panel de detalle de rutina landscape está abierto (el
      // panel ocupa la misma zona donde el usuario esperaría tocar "Nuevo
      // hábito", y abrir el formulario ahí encima sería confuso). Scaffold
      // ya anima la aparición/desaparición del FAB al pasar a null — mismo
      // mecanismo que ya usaba el modo selección de notas, sin necesidad de
      // envolverlo en un AnimatedSwitcher propio.
      floatingActionButton: (_currentIndex == 2 && _modoSeleccionNotas) || _rutinaLandscapeSeleccionada != null
          ? null
          : FloatingActionButton.extended(
        onPressed: () {
          if (_currentIndex == 0) {
            abrirFormularioTarea(context);
          } else if (_currentIndex == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const RutinaFormScreen()));
          } else {
            mostrarDialogoNota(context, ref);
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
        child: esLandscape
            ? SafeArea(
                child: _buildBodyLandscape(
                  temaActual: temaActual,
                  colorPrincipal: colorPrincipal,
                  tareas: tareas,
                  vistaAgrupada: vistaAgrupada,
                  ordenGrupos: ordenGrupos,
                  notasGuardadas: notasGuardadas,
                ),
              )
            : SafeArea(
          top: false,
          bottom: false,
          child: TabBarView(
          controller: _tabController,
          children: [
            Column(
              children: [
                // Selector de orden y de vista (agrupada / todas juntas):
                // debajo de la pestaña "Tareas" y encima de la lista
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        PopupMenuButton<TipoOrden>(
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
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => ref.read(vistaAgrupadaProvider.notifier).cambiarVista(!vistaAgrupada),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: colorPrincipal.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(vistaAgrupada ? Icons.folder_rounded : Icons.view_agenda_rounded, size: 18, color: colorPrincipal),
                                const SizedBox(width: 6),
                                Text(
                                  vistaAgrupada ? 'Agrupadas' : 'Todas juntas',
                                  style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: tareas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Este espacio empuja el texto hacia abajo del loto central.
                              const SizedBox(height: 120),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  'Nada por aquí, disfruta de tu día.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: colorPrincipal.withOpacity(0.6), fontSize: 15, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        )
                      : !vistaAgrupada
                      ? OverflowScrollbar(
                          controller: _scrollTareas,
                          child: ListView.builder(
                          controller: _scrollTareas,
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 100 + MediaQuery.of(context).padding.bottom),
                          itemCount: tareas.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: TareaCard(tarea: tareas[index], tema: temaActual),
                          ),
                          ),
                        )
                      : () {
                          // 1. Agrupar las tareas
                          final mapaGrupos = <String, List<Tarea>>{};
                          for (var tarea in tareas) {
                            if (!mapaGrupos.containsKey(tarea.grupo)) mapaGrupos[tarea.grupo] = [];
                            mapaGrupos[tarea.grupo]!.add(tarea);
                          }

                          // 2. Ordenar los grupos según el orden que el usuario definió
                          // arrastrándolos (ordenGruposProvider). Un grupo que aún no
                          // esté registrado ahí (caso raro) queda al final, alfabético.
                          final listaGrupos = mapaGrupos.keys.toList();
                          listaGrupos.sort((a, b) {
                            final ia = ordenGrupos.indexOf(a);
                            final ib = ordenGrupos.indexOf(b);
                            if (ia == -1 && ib == -1) return a.compareTo(b);
                            if (ia == -1) return 1;
                            if (ib == -1) return -1;
                            return ia.compareTo(ib);
                          });

                          // 3. Dibujar la lista con Animaciones y Colores Dinámicos.
                          // Es reordenable: el usuario puede arrastrar la cabecera de
                          // cada carpeta para cambiar el orden de los grupos.
                          return OverflowScrollbar(
                            controller: _scrollTareas,
                            child: ReorderableListView.builder(
                            scrollController: _scrollTareas,
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 100 + MediaQuery.of(context).padding.bottom),
                            buildDefaultDragHandles: false,
                            itemCount: listaGrupos.length,
                            onReorderStart: (index) {
                              setState(() => _grupoEnArrastre = listaGrupos[index]);
                            },
                            onReorderEnd: (_) {
                              setState(() => _grupoEnArrastre = null);
                            },
                            onReorder: (oldIndex, newIndex) {
                              ref.read(ordenGruposProvider.notifier).reordenarVisibles(listaGrupos, oldIndex, newIndex);
                            },
                            // Recuadro que se ve mientras se arrastra una carpeta:
                            // en vez de reusar "child" (que puede traer todas sus
                            // tareas visibles y tapar la pantalla en grupos grandes),
                            // se dibuja solo la cabecera de la carpeta —el mismo
                            // contenido colapsado—, con esquinas redondeadas y la
                            // elevación animada que ReorderableListView usa por
                            // defecto para su recuadro de arrastre.
                            proxyDecorator: (child, index, animation) {
                              final grupoArrastrado = listaGrupos[index];
                              final cantidadTareas = mapaGrupos[grupoArrastrado]!.length;
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (context, _) {
                                  final double t = Curves.easeInOut.transform(animation.value);
                                  final double elevacion = lerpDouble(0, 6, t)!;
                                  return Material(
                                    elevation: elevacion,
                                    borderRadius: BorderRadius.circular(16),
                                    clipBehavior: Clip.antiAlias,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      child: Row(
                                        children: [
                                          Icon(Icons.folder_rounded, size: 24, color: colorPrincipal),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              grupoArrastrado,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: temaActual.colorTituloGrupo),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colorPrincipal.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$cantidadTareas',
                                              style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(Icons.drag_indicator_rounded, size: 20, color: colorPrincipal.withOpacity(0.4)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            itemBuilder: (context, index) {
                              final grupo = listaGrupos[index];
                              final tareasDelGrupo = mapaGrupos[grupo]!;
                              final isColapsado = ref.watch(gruposColapsadosProvider).contains(grupo);

                              // --- COLOR DINÁMICO DEL TEMA ---
                              // Extraemos el color de la interfaz de Flutter.
                              // (Si tu objeto 'temaActual' tiene una propiedad de color, por ejemplo 'temaActual.color',
                              // puedes reemplazar esta variable directamente por ese valor).
                              final colorTema = colorPrincipal;

                              return _GrupoTareasSection(
                                key: ValueKey(grupo),
                                indice: index,
                                grupo: grupo,
                                tareas: tareasDelGrupo,
                                isColapsado: isColapsado,
                                arrastrando: _grupoEnArrastre == grupo,
                                esPrimero: index == 0,
                                colorTema: colorTema,
                                temaActual: temaActual,
                                onToggle: () {
                                  ref.read(gruposColapsadosProvider.notifier).toggle(grupo);
                                },
                              );
                            },
                            ),
                          );
                        }(),
                ),
              ],
            ),
            _SeccionRutinasHoy(scrollController: _scrollRutinas),
            _buildTabNotas(colorPrincipal, notasGuardadas),
          ],
        ),
        ),
      ),
    );
  }
}

// =====================================================================
// SECCIÓN DE GRUPO DE TAREAS CON ANIMACIÓN DE CASCADA (ABRIR Y CERRAR)
// =====================================================================

class _GrupoTareasSection extends StatefulWidget {
  final int indice;
  final String grupo;
  final List<Tarea> tareas;
  final bool isColapsado;
  // true mientras el usuario arrastra esta carpeta para reordenarla: fuerza
  // el colapso temporalmente sin tocar la preferencia manual (isColapsado).
  final bool arrastrando;
  final bool esPrimero;
  final Color colorTema;
  final TemaApp temaActual;
  final VoidCallback onToggle;

  const _GrupoTareasSection({
    super.key,
    required this.indice,
    required this.grupo,
    required this.tareas,
    required this.isColapsado,
    required this.arrastrando,
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

  bool _colapsadoEfectivo(_GrupoTareasSection w) => w.isColapsado || w.arrastrando;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: _colapsadoEfectivo(widget) ? 0.0 : 1.0,
    );
  }

  @override
  void didUpdateWidget(covariant _GrupoTareasSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final eraColapsado = _colapsadoEfectivo(oldWidget);
    final esColapsado = _colapsadoEfectivo(widget);
    if (eraColapsado != esColapsado) {
      if (esColapsado) {
        _controller.reverse(); // Cierra con cascada ascendente (manual o por arrastre)
      } else {
        _controller.forward(); // Abre con cascada descendente (manual o al soltar el arrastre)
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
        // El tap en cualquier parte de la cabecera sigue abriendo/cerrando
        // la carpeta. Arrastrar (para reordenar) solo se activa desde el
        // ícono de 6 puntos, envuelto abajo en ReorderableDragStartListener.
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
                const SizedBox(width: 4),

                // Ícono de arrastre (única zona que inicia el reordenamiento):
                // al presionarlo y mover el dedo, la carpeta se colapsa sola
                // mientras se arrastra y se reabre automáticamente al soltarla.
                ReorderableDragStartListener(
                  index: widget.indice,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(Icons.drag_indicator_rounded, size: 20, color: widget.colorTema.withOpacity(0.4)),
                  ),
                ),

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





// --- TUS COMPONENTES ORIGINALES (_SeccionRutinasHoy y TareaCard) ---

// _SeccionRutinasHoy: pinta el contenido del tab "Rutinas" en la pantalla principal.
// Es un widget "de solo lectura" respecto a las notificaciones: únicamente
// observa (ref.watch) el estado actual de rutinaProvider y construye la lista
// de RutinaCard para HOY. Toda la lógica de cancelar/programar notificaciones
// vive en rutina_provider.dart y rutina_card.dart, NO aquí.
class _SeccionRutinasHoy extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const _SeccionRutinasHoy({required this.scrollController});

  @override
  ConsumerState<_SeccionRutinasHoy> createState() => _SeccionRutinasHoyState();
}

class _SeccionRutinasHoyState extends ConsumerState<_SeccionRutinasHoy> {
  // Id de la única rutina con la tarjeta expandida (o null si ninguna).
  // Vive aquí (en el contenedor de la lista) y no en RutinaCard para que
  // expandir una tarjeta colapse automáticamente cualquier otra.
  String? _idRutinaExpandida;

  @override
  Widget build(BuildContext context) {
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
              const _BadgeMonedasRacha(),
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
                    : OverflowScrollbar(
                        controller: widget.scrollController,
                        child: ListView.builder(
                        controller: widget.scrollController,
                        padding: EdgeInsets.only(top: 16, bottom: 100 + MediaQuery.of(context).padding.bottom, left: 16, right: 16),
                        itemCount: rutinasDeHoy.length,
                        itemBuilder: (context, index) {
                          final rutina = rutinasDeHoy[index];
                          return RutinaCard(
                            key: ValueKey(rutina.id),
                            rutina: rutina,
                            colorTema: colorPrincipal,
                            esExpandida: _idRutinaExpandida == rutina.id,
                            onToggleExpansion: () => setState(() {
                              _idRutinaExpandida = _idRutinaExpandida == rutina.id ? null : rutina.id;
                            }),
                          );
                        },
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

// Texto explicativo de las monedas de racha, compartido entre el SnackBar
// que aparece al tocar el saldo (_BadgeMonedasRacha) y cualquier otro lugar
// que quiera explicarlas con las mismas palabras.
const String explicacionMonedasRacha =
    '🪙 Ganas 1 moneda cada vez que una rutina llega a una racha de 7 (y de '
    'nuevo en 14, 21...). Úsalas para omitir un día sin romper tu racha: '
    'cuesta más cuanto más seguido omitas la misma rutina.';

// Saldo de monedas de racha: se ganan al alcanzar un hito de racha semanal
// en cualquier rutina y se gastan al omitir una ocurrencia de hoy sin
// romper la racha (ver toggleOmitida en rutina_provider.dart). Vive junto
// al botón de "Configurar Horario Semanal" para que el usuario lo tenga a
// la vista mientras decide si le conviene omitir algo hoy. Es tocable: al
// presionarlo muestra un SnackBar explicando cómo funcionan (el Tooltip
// solo se ve con long-press/hover, poco descubrible).
// Selector de pestaña tipo píldora del header en landscape (reemplaza al
// TabBar de portrait). Solo cambia de apariencia; quien manda en cuál
// pestaña está activa sigue siendo _tabController, así que rotar el
// dispositivo entre portrait y landscape nunca deja el índice desincronizado.
// Panel de detalle de rutina en landscape (título completo + descripción),
// superpuesto sobre el grid en vez de un showDialog centrado: un diálogo no
// se puede posicionar en la zona del grid sin calcular su geometría, y este
// panel es hermano del grid dentro del mismo Stack en
// _buildContenidoRutinasLandscape, así que ocupa exactamente esa zona sin
// tapar el sidebar ("Hoy es...") ni el header. Sin botón "Editar": el tap
// sobre la tarjeta no reemplaza ningún acceso existente (no hacía nada
// antes de este rediseño) y editar ya tiene su propia entrada en el header
// ("Editar rutina" / ícono de lápiz).
class _PanelDetalleRutinaLandscape extends ConsumerWidget {
  final Rutina rutina;
  final TemaApp tema;
  final VoidCallback onCerrar;
  const _PanelDetalleRutinaLandscape({super.key, required this.rutina, required this.tema, required this.onCerrar});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool tieneDescripcion = rutina.descripcion != null && rutina.descripcion!.trim().isNotEmpty;
    final Color colorFuerte = rutina.activa ? tema.colorPrincipal : Colors.grey;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tema.colorSuperficieCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorFuerte.withValues(alpha: 0.18)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colorFuerte.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(IconData(rutina.iconoCode, fontFamily: 'MaterialIcons'), color: colorFuerte, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    rutina.titulo,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: tema.colorTextoSuperficie),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colorFuerte),
                tooltip: 'Cerrar',
                onPressed: onCerrar,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                tieneDescripcion ? rutina.descripcion! : 'Esta rutina no tiene descripción.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: tieneDescripcion
                      ? tema.colorTextoSuperficie.withValues(alpha: 0.85)
                      : tema.colorTextoSuperficie.withValues(alpha: 0.5),
                  fontStyle: tieneDescripcion ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Acciones: mismo criterio que el checkbox/omitir de la tarjeta
          // (omitida excluye completar/omitir — hay que deshacer primero;
          // completada excluye omitir — ya se resolvió el día). El botón
          // "Completar"/"Desmarcar" llama al MISMO manejarToqueCheckboxRutina
          // que usa el checkbox de la tarjeta (portrait y landscape): es el
          // único punto que decide si toca el diálogo del temporizador o si
          // se completa directo, así que no hay una segunda lógica de
          // completado que mantener sincronizada acá.
          if (rutina.omitida)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => ref.read(rutinaProvider.notifier).toggleOmitida(rutina.id),
                icon: Icon(Icons.settings_backup_restore_rounded, color: colorOmitidaRutina),
                label: Text('Deshacer omisión', style: TextStyle(color: colorOmitidaRutina, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colorOmitidaRutina.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => manejarToqueCheckboxRutina(
                      context: context,
                      ref: ref,
                      rutina: rutina,
                      valor: !rutina.completada,
                    ),
                    icon: Icon(rutina.completada ? Icons.remove_circle_outline_rounded : Icons.check_circle_outline_rounded),
                    label: Text(rutina.completada ? 'Desmarcar' : 'Completar', style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorFuerte,
                      foregroundColor: tema.colorSobrePrincipal,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                if (!rutina.completada) ...[
                  const SizedBox(width: 12),
                  Expanded(child: BotonOmitirRutinaPanel(rutina: rutina)),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _PildoraTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool seleccionado;
  final TemaApp tema;
  final VoidCallback onTap;

  const _PildoraTab({required this.icon, required this.label, required this.seleccionado, required this.tema, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color colorPrincipal = tema.colorPrincipal;
    final Color colorInactivo = colorPrincipal.withValues(alpha: 0.55);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: seleccionado ? colorPrincipal : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: seleccionado ? tema.colorSobrePrincipal : colorInactivo),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: seleccionado ? tema.colorSobrePrincipal : colorInactivo)),
          ],
        ),
      ),
    );
  }
}

class _BadgeMonedasRacha extends ConsumerWidget {
  const _BadgeMonedasRacha();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int monedas = ref.watch(monedasProvider);
    return Tooltip(
      message: explicacionMonedasRacha,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => mostrarSnackBarSimple(
          mensaje: explicacionMonedasRacha,
          colorFondo: colorOmitidaRutina,
          colorTexto: Colors.white,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: colorOmitidaRutina.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🪙', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                '$monedas',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorOmitidaRutina, fontSize: 14),
              ),
            ],
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
    final bool esRecurrente = tarea.tipoRecurrencia != TipoRecurrencia.ninguna;
    // Una recurrente que SIGUE viva nunca queda con esCompletada = true (ver
    // toggleTarea): detectamos su "undo" por tener una completación reciente
    // para deshacer, no por esCompletada. La única excepción es la ÚLTIMA
    // ocurrencia (agotó su límite): esa sí queda esCompletada=true Y con
    // fechaLimiteAnterior seteado, así que puedeDeshacerRecurrente también
    // la cubre correctamente (ambas rutas de deshacer conviven en el mismo
    // flag, ver toggleTarea).
    final bool puedeDeshacerRecurrente = esRecurrente && tarea.fechaLimiteAnterior != null;
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
                                    // Expanded (con ellipsis): agregarle el progreso de
                                    // recurrencia a esta fila la hizo más larga y puede
                                    // desbordar con nombres de día largos ("miércoles") +
                                    // "N de M"; sin esto tronaba con overflow en angostos.
                                    Flexible(
                                      child: Text(
                                        // 23:59 es el valor implícito cuando no se eligió hora (ver
                                        // add_tarea_modal._guardarTarea), así que no se muestra.
                                        DateFormat(
                                          (tarea.fechaLimite!.hour == 23 && tarea.fechaLimite!.minute == 59) ? 'EEEE, d MMM' : 'EEEE, d MMM • HH:mm',
                                          'es',
                                        ).format(tarea.fechaLimite!),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: colorBase.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (esRecurrente) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.repeat, size: 14, color: colorBase.withValues(alpha: 0.9)),
                                      if (tarea.textoProgresoRecurrencia != null) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          tarea.textoProgresoRecurrencia!,
                                          style: TextStyle(color: colorBase.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ],
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
          if (_showOverlayMenu) Positioned.fill(child: GestureDetector(onTap: () => setState(() => _showOverlayMenu = false), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), child: Container(color: Colors.white.withValues(alpha: 0.2), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildActionIcon(icon: (tarea.esCompletada || puedeDeshacerRecurrente) ? Icons.undo : Icons.check_rounded, color: const Color(0xFF4CAF50), onTap: () { setState(() => _showOverlayMenu = false); if (puedeDeshacerRecurrente) { ref.read(tareaProvider.notifier).deshacerRecurrente(tarea.id); } else { ref.read(tareaProvider.notifier).toggleTarea(tarea.id); } }), _buildActionIcon(icon: Icons.edit_rounded, color: Colors.blueGrey, onTap: () { setState(() => _showOverlayMenu = false); abrirFormularioTarea(context, tareaAEditar: tarea); }), _buildActionIcon(icon: Icons.delete_rounded, color: Colors.redAccent, onTap: () { setState(() => _showOverlayMenu = false); Future.delayed(const Duration(milliseconds: 150), () { if (!mounted) return; ref.read(tareaProvider.notifier).deleteTarea(tarea.id); mostrarSnackBarSimple(mensaje: 'Tarea eliminada', colorFondo: widget.tema.colorPrincipal, colorTexto: widget.tema.colorSobrePrincipal); }); })]))))),
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

  Color _getColorUrgencia(int urgencia, TemaApp tema) => colorUrgenciaTarea(urgencia, tema);

  String _getLabelUrgencia(int urgencia) => labelUrgenciaTarea(urgencia);

  
}
