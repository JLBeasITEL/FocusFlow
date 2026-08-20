import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nota.dart';
import '../../providers/nota_provider.dart';
import '../../providers/tema_provider.dart';
import '../../core/app_messenger.dart';
import 'post_it_card.dart';
import 'nota_dialog.dart';
import 'overflow_scrollbar.dart';

// Tarjeta que representa un grupo de notas en el tablero: una pila de
// post-its con el nombre del grupo "por encima" (banner superior), del
// mismo tamaño que una nota suelta (ver _buildTabNotas en home_screen.dart).
class TarjetaGrupoNotas extends StatelessWidget {
  final String nombreGrupo;
  final List<NotaPostIt> notas;
  final int columnasTotales;
  final VoidCallback onTap;
  // true mientras el tablero está en modo selección de notas sueltas: los
  // grupos no se pueden seleccionar, así que se muestran atenuados y sin
  // reaccionar al toque.
  final bool deshabilitada;
  // true mientras se arrastra una nota justo encima de esta tarjeta: resalta
  // el borde para indicar que soltarla la suma al grupo.
  final bool resaltada;

  const TarjetaGrupoNotas({
    super.key,
    required this.nombreGrupo,
    required this.notas,
    required this.columnasTotales,
    required this.onTap,
    this.deshabilitada = false,
    this.resaltada = false,
  });

  @override
  Widget build(BuildContext context) {
    final coloresPila = notas.take(3).map((n) => n.color).toList();
    if (coloresPila.isEmpty) coloresPila.add(coloresPostIt.first);
    final double factorEscala = (2 / columnasTotales).clamp(0.5, 1.6);
    final double tamanoLetra = (18.0 * factorEscala).clamp(13.0, 24.0);

    return AnimatedScale(
      scale: resaltada ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Opacity(
      opacity: deshabilitada ? 0.4 : 1.0,
      child: GestureDetector(
        onTap: deshabilitada ? null : onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cartas traseras: apenas asomadas, dan el efecto de pila.
            if (coloresPila.length > 2)
              Positioned(
                left: 16, top: 16, right: 0, bottom: 0,
                child: Transform.rotate(
                  angle: 0.06,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: coloresPila[2],
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(1, 1))],
                    ),
                  ),
                ),
              ),
            if (coloresPila.length > 1)
              Positioned(
                left: 8, top: 8, right: 4, bottom: 4,
                child: Transform.rotate(
                  angle: -0.04,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: coloresPila[1],
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 3, offset: const Offset(1, 1))],
                    ),
                  ),
                ),
              ),
            // Carta principal, con el nombre del grupo en un banner arriba.
            Positioned(
              left: 0, top: 0, right: 8, bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: coloresPila[0],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 5, offset: const Offset(2, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10 * factorEscala + 2, vertical: 6 * factorEscala + 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.08),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                      ),
                      child: Text(
                        nombreGrupo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: tamanoLetra, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.15),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Icon(Icons.folder_copy_rounded, size: tamanoLetra * 1.8, color: Colors.black45),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 10 * factorEscala + 2, bottom: 6 * factorEscala + 2),
                      child: Text(
                        '${notas.length} notas',
                        style: TextStyle(fontSize: tamanoLetra * 0.65, color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// Pantalla que muestra las notas de un grupo (tocar una la abre para
// editar, igual que en el tablero principal) y permite disolver el grupo
// completo o sacar notas sueltas de él.
class GrupoNotasDetalleScreen extends ConsumerStatefulWidget {
  final String nombreGrupo;

  const GrupoNotasDetalleScreen({super.key, required this.nombreGrupo});

  @override
  ConsumerState<GrupoNotasDetalleScreen> createState() => _GrupoNotasDetalleScreenState();
}

class _GrupoNotasDetalleScreenState extends ConsumerState<GrupoNotasDetalleScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Mismo patrón que _eliminarNota en home_screen.dart: captura el notifier
  // antes de mostrar el SnackBar, porque el callback de "Deshacer" corre
  // en diferido y para entonces este widget puede haberse desmontado.
  void _eliminarNota(WidgetRef ref, Color colorTema, Color colorSobreTema, NotaPostIt nota) {
    final notifier = ref.read(notaProvider.notifier);
    final datos = notifier.eliminarConDeshacer(nota.id);
    if (datos == null) return;
    mostrarSnackBarDeshacer(
      mensaje: 'Nota eliminada',
      onDeshacer: () => notifier.restaurar(datos.elemento, datos.indice),
      colorFondo: colorTema,
      colorTexto: colorSobreTema,
    );
  }

  // Muestra las notas sueltas (sin grupo) para elegir cuáles sumar a este
  // grupo. Reutiliza agruparNotas: como el nombre ya existe, las notas
  // elegidas simplemente se agregan a él.
  Future<void> _agregarNotas(BuildContext context, WidgetRef ref, List<NotaPostIt> notasSueltas) async {
    final seleccionadas = <String>{};
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Agregar notas al grupo'),
          content: SizedBox(
            width: double.maxFinite,
            child: notasSueltas.isEmpty
                ? const Text('No hay notas sueltas para agregar.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: notasSueltas.length,
                    itemBuilder: (context, index) {
                      final nota = notasSueltas[index];
                      final etiqueta = nota.titulo.isNotEmpty
                          ? nota.titulo
                          : (nota.tipo == TipoNota.lista
                              ? (nota.elementosLista.isNotEmpty ? nota.elementosLista.first.texto : 'Lista')
                              : nota.texto);
                      return CheckboxListTile(
                        value: seleccionadas.contains(nota.id),
                        onChanged: (val) => setState(() {
                          if (val == true) {
                            seleccionadas.add(nota.id);
                          } else {
                            seleccionadas.remove(nota.id);
                          }
                        }),
                        secondary: CircleAvatar(backgroundColor: nota.color, radius: 12),
                        title: Text(
                          etiqueta.isEmpty ? '(sin texto)' : etiqueta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: seleccionadas.isEmpty ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );

    if (confirmar == true) {
      ref.read(notaProvider.notifier).agruparNotas(seleccionadas.toList(), widget.nombreGrupo);
    }
  }

  Future<void> _confirmarDisolver(BuildContext context, WidgetRef ref) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disolver grupo'),
        content: Text('Las notas de "${widget.nombreGrupo}" volverán a mostrarse sueltas en el tablero. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Disolver')),
        ],
      ),
    );
    if (confirmar == true) {
      ref.read(notaProvider.notifier).disolverGrupo(widget.nombreGrupo);
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todasLasNotas = ref.watch(notaProvider);
    final notasDelGrupo = todasLasNotas.where((n) => n.grupoNombre == widget.nombreGrupo).toList();
    final temaActual = ref.watch(temaProvider);
    final colorTema = temaActual.colorPrincipal;
    final colorSobreTema = temaActual.colorSobrePrincipal;

    // Si se quitaron/borraron todas las notas del grupo mientras esta
    // pantalla estaba abierta, ya no queda nada que mostrar: se cierra sola.
    if (notasDelGrupo.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorTema,
        foregroundColor: colorSobreTema,
        title: Text(widget.nombreGrupo),
        actions: [
          IconButton(
            icon: const Icon(Icons.post_add_rounded),
            tooltip: 'Nueva nota',
            onPressed: () => mostrarDialogoNota(context, ref, grupoNombrePorDefecto: widget.nombreGrupo),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded),
            tooltip: 'Agregar notas',
            onPressed: () => _agregarNotas(context, ref, todasLasNotas.where((n) => n.grupoNombre.isEmpty).toList()),
          ),
          IconButton(
            icon: const Icon(Icons.link_off_rounded),
            tooltip: 'Disolver grupo',
            onPressed: () => _confirmarDisolver(context, ref),
          ),
        ],
      ),
      body: notasDelGrupo.isEmpty
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (context, constraints) {
                // Mismo criterio de tamaño de celda que el tablero principal
                // (ver _tamanoMinimoCelda en home_screen.dart): antes esto
                // usaba siempre 2 columnas fijas, así que en landscape (ancho
                // grande) las notas quedaban enormes comparadas con las del
                // tablero.
                const double anchoTarget = 140;
                const double espaciado = 12;
                final int columnas = math.max(2, ((constraints.maxWidth + espaciado) / (anchoTarget + espaciado)).floor());
                return OverflowScrollbar(
                  controller: _scrollController,
                  child: GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnas,
                    crossAxisSpacing: espaciado,
                    mainAxisSpacing: espaciado,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: notasDelGrupo.length,
                  itemBuilder: (context, index) {
                    final nota = notasDelGrupo[index];
                    return PostItCard(
                      key: ValueKey(nota.id),
                      nota: nota,
                      index: index,
                      columnasTotales: columnas,
                      onTapEditar: () => mostrarDialogoNota(context, ref, idAEditar: nota.id),
                      onDelete: () => _eliminarNota(ref, colorTema, colorSobreTema, nota),
                      onQuitarDeGrupo: () => ref.read(notaProvider.notifier).quitarDeGrupo(nota.id),
                      onToggleDestacada: () => alternarDestacadaConFeedback(context, ref, nota.id),
                    );
                  },
                  ),
                );
              },
            ),
    );
  }
}
