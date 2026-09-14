import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/tarea.dart';
import '../../providers/tarea_provider.dart';
import '../../providers/tema_provider.dart';
import '../../core/colores_estado_tarea.dart';
import '../../core/app_messenger.dart';
import 'add_tarea_modal.dart';

// Versión compacta de TareaCard (home_screen.dart) para la grilla de 2
// columnas del layout horizontal: mismo modelo de interacción (checkbox
// para completar, tap para editar, long-press para el menú de
// check/editar/eliminar) pero en una tarjeta baja tipo "píldora" en vez
// del ListTile alto y expandible de portrait.
class TareaLandscapeCard extends ConsumerStatefulWidget {
  final Tarea tarea;
  final TemaApp tema;
  const TareaLandscapeCard({super.key, required this.tarea, required this.tema});

  @override
  ConsumerState<TareaLandscapeCard> createState() => _TareaLandscapeCardState();
}

class _TareaLandscapeCardState extends ConsumerState<TareaLandscapeCard> {
  bool _showOverlayMenu = false;
  Timer? _timerAtraso;
  // Mismo motivo que TareaCard (home_screen.dart): completar la ÚLTIMA
  // ocurrencia de una recurrente con límite archiva de inmediato, sacando
  // la tarjeta de `state` en el mismo frame — sin esto, desaparece antes de
  // que el usuario vea el check o el tachado. Ver build() y
  // _completarConFeedbackVisual.
  bool _mostrandoCompletadaFinal = false;

  @override
  void initState() {
    super.initState();
    _programarRevisarAtraso();
  }

  @override
  void didUpdateWidget(covariant TareaLandscapeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tarea.fechaLimite != widget.tarea.fechaLimite || oldWidget.tarea.esCompletada != widget.tarea.esCompletada) {
      _timerAtraso?.cancel();
      _programarRevisarAtraso();
    }
  }

  // Mismo mecanismo que TareaCard: si falta tiempo para la fecha límite,
  // programa un único redibujo justo cuando cruza a "atrasada" (en vez de
  // depender de que el usuario reabra la pantalla para verlo actualizado).
  void _programarRevisarAtraso() {
    final tarea = widget.tarea;
    if (!tarea.esCompletada && tarea.fechaLimite != null) {
      final ahora = DateTime.now();
      if (tarea.fechaLimite!.isAfter(ahora)) {
        _timerAtraso = Timer(tarea.fechaLimite!.difference(ahora), () {
          if (mounted) setState(() {});
        });
      }
    }
  }

  @override
  void dispose() {
    _timerAtraso?.cancel();
    super.dispose();
  }

  void _abrirEdicion(BuildContext context) {
    abrirFormularioTarea(context, tareaAEditar: widget.tarea);
  }

  // Punto único para completar una tarea desde esta tarjeta (checkbox y
  // menú de acciones al mantener presionado). Mismo motivo y mismo patrón
  // que TareaCard._completarConFeedbackVisual en home_screen.dart.
  void _completarConFeedbackVisual() {
    if (_mostrandoCompletadaFinal) return; // ya en curso, evita disparar dos veces
    if (widget.tarea.completarAgotaLimite) {
      setState(() => _mostrandoCompletadaFinal = true);
      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        ref.read(tareaProvider.notifier).toggleTarea(widget.tarea.id);
      });
    } else {
      ref.read(tareaProvider.notifier).toggleTarea(widget.tarea.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // _mostrandoCompletadaFinal sobreescribe esCompletada para que el resto
    // completo de este build reaccione igual que ante una completación
    // real (ver comentario del campo y TareaCard en home_screen.dart, mismo
    // patrón).
    final tarea = _mostrandoCompletadaFinal ? widget.tarea.copyWith(esCompletada: true) : widget.tarea;
    final colorBase = colorUrgenciaTarea(tarea.urgencia, widget.tema);
    final bool esMedianoche = widget.tema == TemaApp.medianoche;
    final Color colorTarjeta = tarea.esCompletada
        ? Colors.white.withValues(alpha: 0.7)
        : (widget.tema == TemaApp.clasico ? Colors.white : colorBase.withValues(alpha: 0.25));
    final bool estaAtrasada = tarea.estaAtrasada;
    final bool tieneSubtareas = tarea.subtareas.isNotEmpty;
    final bool esRecurrente = tarea.tipoRecurrencia != TipoRecurrencia.ninguna;
    // Mismo criterio que TareaCard (home_screen.dart): una tarea recurrente
    // nunca queda con esCompletada = true, así que su "undo" se detecta por
    // tener una completación reciente para deshacer.
    final bool puedeDeshacerRecurrente = esRecurrente && tarea.fechaLimiteAnterior != null;
    const Color colorTextoClaro = Color(0xFFF1F5F9);
    final Color colorTitulo = tarea.esCompletada ? Colors.black38 : (esMedianoche ? colorTextoClaro : Colors.black87);

    return Container(
      decoration: BoxDecoration(
        color: colorTarjeta,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tarea.esCompletada ? Colors.transparent : colorBase.withValues(alpha: widget.tema == TemaApp.clasico ? 0.6 : 0.4),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: () => _abrirEdicion(context),
            onLongPress: () => setState(() => _showOverlayMenu = true),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: tarea.esCompletada,
                          activeColor: colorBase,
                          shape: const CircleBorder(),
                          side: BorderSide(color: tarea.esCompletada ? colorBase : (esMedianoche ? Colors.white54 : Colors.black45), width: 1.5),
                          onChanged: (_) => _completarConFeedbackVisual(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            tarea.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: tarea.esCompletada ? FontWeight.normal : FontWeight.w600,
                              decoration: tarea.esCompletada ? TextDecoration.lineThrough : null,
                              color: colorTitulo,
                            ),
                          ),
                        ),
                      ),
                      if (!tarea.esCompletada) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: estaAtrasada ? Colors.red.shade700 : ((widget.tema == TemaApp.clasico || esMedianoche) ? colorBase.withValues(alpha: 0.2) : colorBase),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            estaAtrasada ? 'ATRASADO' : labelUrgenciaTarea(tarea.urgencia),
                            style: TextStyle(
                              color: estaAtrasada ? Colors.white : ((widget.tema == TemaApp.clasico || esMedianoche) ? colorBase : Colors.white),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: Row(
                      children: [
                        if (!tarea.esCompletada && tarea.fechaLimite != null) ...[
                          Icon(Icons.access_time, size: 12, color: colorBase.withValues(alpha: 0.9)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              DateFormat(
                                (tarea.fechaLimite!.hour == 23 && tarea.fechaLimite!.minute == 59) ? 'EEE, d MMM' : 'EEE, d MMM • HH:mm',
                                'es',
                              ).format(tarea.fechaLimite!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colorBase.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (esRecurrente) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.repeat, size: 12, color: colorBase.withValues(alpha: 0.9)),
                            if (tarea.textoProgresoRecurrencia != null) ...[
                              const SizedBox(width: 3),
                              Text(
                                tarea.textoProgresoRecurrencia!,
                                style: TextStyle(color: colorBase.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ] else
                          const Spacer(),
                        if (tieneSubtareas)
                          Text(
                            '${tarea.progresoSubtareas.$1}/${tarea.progresoSubtareas.$2}',
                            style: TextStyle(color: colorBase, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showOverlayMenu)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showOverlayMenu = false),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildActionIcon(
                          icon: (tarea.esCompletada || puedeDeshacerRecurrente) ? Icons.undo : Icons.check_rounded,
                          color: const Color(0xFF4CAF50),
                          onTap: () {
                            setState(() => _showOverlayMenu = false);
                            if (puedeDeshacerRecurrente) {
                              ref.read(tareaProvider.notifier).deshacerRecurrente(tarea.id);
                            } else {
                              _completarConFeedbackVisual();
                            }
                          },
                        ),
                        _buildActionIcon(
                          icon: Icons.edit_rounded,
                          color: Colors.blueGrey,
                          onTap: () {
                            setState(() => _showOverlayMenu = false);
                            _abrirEdicion(context);
                          },
                        ),
                        _buildActionIcon(
                          icon: Icons.delete_rounded,
                          color: Colors.redAccent,
                          onTap: () {
                            setState(() => _showOverlayMenu = false);
                            Future.delayed(const Duration(milliseconds: 150), () {
                              if (!mounted) return;
                              ref.read(tareaProvider.notifier).deleteTarea(tarea.id);
                              mostrarSnackBarSimple(mensaje: 'Tarea eliminada', colorFondo: widget.tema.colorPrincipal, colorTexto: widget.tema.colorSobrePrincipal);
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
    return CircleAvatar(backgroundColor: Colors.white, radius: 20, child: IconButton(icon: Icon(icon, color: color, size: 20), onPressed: onTap));
  }
}
