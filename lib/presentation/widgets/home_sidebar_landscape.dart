import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/tarea_provider.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/nota_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../providers/tema_provider.dart';
import 'filtro_tareas_modal.dart';
import 'progreso_rutinas_bar.dart';
import 'grupo_notas_card.dart';
import 'overflow_scrollbar.dart';
import '../utils/iconos_grupo.dart';

// Panel lateral del layout horizontal (HomeScreen en landscape): muestra un
// resumen distinto según la pestaña activa (Tareas/Rutinas/Notas), leyendo
// los mismos providers que ya usa el layout de portrait, sin estado propio.
class HomeSidebarLandscape extends StatefulWidget {
  final int currentIndex;
  final TemaApp tema;

  const HomeSidebarLandscape({super.key, required this.currentIndex, required this.tema});

  @override
  State<HomeSidebarLandscape> createState() => _HomeSidebarLandscapeState();
}

class _HomeSidebarLandscapeState extends State<HomeSidebarLandscape> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.tema.colorSuperficieCard,
        borderRadius: BorderRadius.circular(28),
      ),
      child: OverflowScrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: switch (widget.currentIndex) {
            0 => _SidebarTareas(tema: widget.tema),
            1 => _SidebarRutinas(tema: widget.tema),
            _ => _SidebarNotas(tema: widget.tema),
          },
        ),
      ),
    );
  }
}

class _SidebarTareas extends ConsumerWidget {
  final TemaApp tema;
  const _SidebarTareas({required this.tema});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tareas = ref.watch(tareaProvider);
    final tipoOrden = ref.watch(ordenProvider);
    final vistaAgrupada = ref.watch(vistaAgrupadaProvider);
    final ordenGrupos = ref.watch(ordenGruposProvider);
    final filtroTareas = ref.watch(filtroTareasProvider);
    final Color colorTexto = tema.colorTextoSuperficie;
    final Color colorPrincipal = tema.colorPrincipal;

    final int pendientes = tareas.where((t) => !t.esCompletada).length;
    final int vencenHoy = tareas.where((t) => !t.esCompletada && t.fechaLimite != null && DateUtils.isSameDay(t.fechaLimite!, DateTime.now())).length;
    final int atrasadas = tareas.where((t) => t.estaAtrasada).length;

    final Map<String, int> mapaCarpetas = {};
    for (final t in tareas) {
      mapaCarpetas[t.grupo] = (mapaCarpetas[t.grupo] ?? 0) + 1;
    }
    final carpetas = mapaCarpetas.keys.toList()
      ..sort((a, b) {
        final ia = ordenGrupos.indexOf(a);
        final ib = ordenGrupos.indexOf(b);
        if (ia == -1 && ib == -1) return a.compareTo(b);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });

    final List<String> detalles = [
      if (vencenHoy > 0) '$vencenHoy vence${vencenHoy == 1 ? '' : 'n'} hoy',
      if (atrasadas > 0) '$atrasadas atrasada${atrasadas == 1 ? '' : 's'}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$pendientes tarea${pendientes == 1 ? '' : 's'} pendiente${pendientes == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: colorTexto),
        ),
        const SizedBox(height: 4),
        Text(
          detalles.isEmpty ? 'Vas al día' : detalles.join(' · '),
          style: TextStyle(fontSize: 13, color: colorTexto.withValues(alpha: 0.6)),
        ),
        if (carpetas.isNotEmpty) ...[
          const SizedBox(height: 24),
          _EtiquetaSeccion(texto: 'CARPETAS', color: colorTexto),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: carpetas.map((g) {
              // Tocar una carpeta filtra la grilla a solo esas tareas
              // (reusa filtroTareasProvider.grupos); tocarla de nuevo
              // limpia el filtro de grupo en vez de dejarlo pegado.
              final seleccionada = filtroTareas.grupos.contains(g);
              final colorChip = seleccionada ? tema.colorSobrePrincipal : colorPrincipal;
              return GestureDetector(
                onTap: () {
                  final notifier = ref.read(filtroTareasProvider.notifier);
                  final esUnicaSeleccionada = filtroTareas.grupos.length == 1 && seleccionada;
                  notifier.actualizar(filtroTareas.copyWith(grupos: esUnicaSeleccionada ? {} : {g}));
                },
                // El tap normal filtra (arriba); mantener presionado el chip
                // abre el selector de ícono, mismo atajo que usa portrait —
                // no hay espacio en el chip para un badge de lápiz propio.
                onLongPress: () => mostrarSelectorIconoGrupo(context, ref, g),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: seleccionada ? colorPrincipal : colorPrincipal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      iconoWidgetDeGrupo(ref.watch(iconosGruposProvider), g, size: 14, color: colorChip),
                      const SizedBox(width: 6),
                      Text(g, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorChip)),
                      const SizedBox(width: 4),
                      Text('${mapaCarpetas[g]}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorChip.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 24),
        _EtiquetaSeccion(texto: 'VISTA', color: colorTexto),
        const SizedBox(height: 10),
        PopupMenuButton<TipoOrden>(
          tooltip: 'Ordenar',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (v) => ref.read(ordenProvider.notifier).cambiarOrden(v),
          itemBuilder: (context) => TipoOrden.values.map((t) => PopupMenuItem(value: t, child: Text(t.label))).toList(),
          child: _FilaVista(icon: Icons.sort_rounded, texto: 'Orden: ${tipoOrden.label}', colorPrincipal: colorPrincipal),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => ref.read(vistaAgrupadaProvider.notifier).cambiarVista(!vistaAgrupada),
          child: _FilaVista(
            icon: vistaAgrupada ? Icons.folder_rounded : Icons.view_agenda_rounded,
            texto: vistaAgrupada ? 'Agrupadas' : 'Todas juntas',
            colorPrincipal: colorPrincipal,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => abrirFiltroTareas(context),
          child: _FilaVista(
            icon: Icons.filter_alt_rounded,
            texto: filtroTareas.activo ? 'Filtro (${filtroTareas.cantidadActivos})' : 'Filtrar',
            colorPrincipal: colorPrincipal,
            resaltado: filtroTareas.activo,
            colorSobreResaltado: tema.colorSobrePrincipal,
          ),
        ),
      ],
    );
  }
}

class _SidebarRutinas extends ConsumerWidget {
  final TemaApp tema;
  const _SidebarRutinas({required this.tema});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listaCompleta = ref.watch(rutinaProvider);
    final int monedas = ref.watch(monedasProvider);
    final Color colorTexto = tema.colorTextoSuperficie;
    final Color colorPrincipal = tema.colorPrincipal;

    final int diaActual = DateTime.now().weekday - 1;
    final rutinasDeHoy = listaCompleta.where((r) => r.horarios.containsKey(diaActual) && r.activa).toList();
    final int pendientesHoy = rutinasDeHoy.where((r) => !r.completada && !r.omitida).length;
    final int rachaMaxima = rutinasDeHoy.isEmpty ? 0 : rutinasDeHoy.map((r) => r.racha).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hoy es ${DateFormat('EEEE', 'es_ES').format(DateTime.now())}', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: colorTexto)),
        const SizedBox(height: 4),
        Text(
          rutinasDeHoy.isEmpty ? 'No hay hábitos programados.' : 'Te quedan $pendientesHoy hábito${pendientesHoy == 1 ? '' : 's'} para hoy.',
          style: TextStyle(fontSize: 13, color: colorTexto.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 4),
        if (rutinasDeHoy.isNotEmpty) ProgresoRutinasBar(rutinasDeHoy: rutinasDeHoy, colorTema: colorPrincipal),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _StatBox(valor: '$rachaMaxima', etiqueta: 'Racha máx.', tema: tema)),
            const SizedBox(width: 12),
            Expanded(child: _StatBox(valor: '$monedas', etiqueta: 'Monedas', tema: tema)),
          ],
        ),
      ],
    );
  }
}

class _SidebarNotas extends ConsumerWidget {
  final TemaApp tema;
  const _SidebarNotas({required this.tema});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notas = ref.watch(notaProvider);
    final Color colorTexto = tema.colorTextoSuperficie;
    final Color colorPrincipal = tema.colorPrincipal;

    final Map<String, int> mapaGrupos = {};
    for (final n in notas) {
      if (n.grupoNombre.isEmpty) continue;
      mapaGrupos[n.grupoNombre] = (mapaGrupos[n.grupoNombre] ?? 0) + 1;
    }
    final grupos = mapaGrupos.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${notas.length} nota${notas.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: colorTexto)),
        const SizedBox(height: 4),
        Text('en tu tablero', style: TextStyle(fontSize: 13, color: colorTexto.withValues(alpha: 0.6))),
        if (grupos.isNotEmpty) ...[
          const SizedBox(height: 24),
          _EtiquetaSeccion(texto: 'GRUPOS', color: colorTexto),
          const SizedBox(height: 10),
          ...grupos.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GrupoNotasDetalleScreen(nombreGrupo: g))),
                child: _FilaVista(icon: Icons.folder_copy_rounded, texto: '$g (${mapaGrupos[g]})', colorPrincipal: colorPrincipal),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EtiquetaSeccion extends StatelessWidget {
  final String texto;
  final Color color;
  const _EtiquetaSeccion({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: color.withValues(alpha: 0.5)));
  }
}

class _FilaVista extends StatelessWidget {
  final IconData icon;
  final String texto;
  final Color colorPrincipal;
  // Usado por la fila "Filtrar": cuando hay un filtro activo, se pinta con
  // el color principal de fondo en vez del tinte suave de siempre, igual
  // que el pill de portrait, para que se note que hay algo filtrando.
  final bool resaltado;
  final Color? colorSobreResaltado;
  const _FilaVista({
    required this.icon,
    required this.texto,
    required this.colorPrincipal,
    this.resaltado = false,
    this.colorSobreResaltado,
  });

  @override
  Widget build(BuildContext context) {
    final colorContenido = resaltado ? (colorSobreResaltado ?? Colors.white) : colorPrincipal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: resaltado ? colorPrincipal : colorPrincipal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorContenido),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorContenido))),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final TemaApp tema;
  const _StatBox({required this.valor, required this.etiqueta, required this.tema});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: tema.colorPrincipal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: tema.colorPrincipal)),
          const SizedBox(height: 2),
          Text(etiqueta, style: TextStyle(fontSize: 11, color: tema.colorTextoSuperficie.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}
