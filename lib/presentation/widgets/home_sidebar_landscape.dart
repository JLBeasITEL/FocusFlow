import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/tarea_provider.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/nota_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../providers/tema_provider.dart';
import 'progreso_rutinas_bar.dart';
import 'grupo_notas_card.dart';

// Panel lateral del layout horizontal (HomeScreen en landscape): muestra un
// resumen distinto según la pestaña activa (Tareas/Rutinas/Notas), leyendo
// los mismos providers que ya usa el layout de portrait, sin estado propio.
class HomeSidebarLandscape extends StatelessWidget {
  final int currentIndex;
  final TemaApp tema;

  const HomeSidebarLandscape({super.key, required this.currentIndex, required this.tema});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tema.colorSuperficieCard,
        borderRadius: BorderRadius.circular(28),
      ),
      child: SingleChildScrollView(
        child: switch (currentIndex) {
          0 => _SidebarTareas(tema: tema),
          1 => _SidebarRutinas(tema: tema),
          _ => _SidebarNotas(tema: tema),
        },
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
            children: carpetas
                .map((g) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: colorPrincipal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_rounded, size: 14, color: colorPrincipal),
                          const SizedBox(width: 6),
                          Text(g, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorPrincipal)),
                          const SizedBox(width: 4),
                          Text('${mapaCarpetas[g]}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorPrincipal.withValues(alpha: 0.7))),
                        ],
                      ),
                    ))
                .toList(),
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
        const SizedBox(height: 16),
        if (rutinasDeHoy.isNotEmpty) ProgresoRutinasBar(rutinasDeHoy: rutinasDeHoy, colorTema: colorPrincipal),
        const SizedBox(height: 12),
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
  const _FilaVista({required this.icon, required this.texto, required this.colorPrincipal});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: colorPrincipal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorPrincipal),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorPrincipal))),
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
