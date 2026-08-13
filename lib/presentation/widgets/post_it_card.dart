import 'package:flutter/material.dart';
import '../../models/nota.dart';

// Widget interactivo de post-it con el clip de imagen. Se usa tanto en el
// tablero principal de notas como dentro de la pantalla de detalle de un
// grupo (ver grupo_notas_card.dart).
class PostItCard extends StatefulWidget {
  final NotaPostIt nota;
  final int index;
  final int columnasTotales;
  final VoidCallback onTapEditar;
  final VoidCallback onDelete;
  // Modo selección múltiple (armar un grupo): mientras está activo, tocar
  // la nota alterna su selección en vez de abrir el diálogo de edición, y
  // el clip de borrado se desactiva para evitar borrados accidentales.
  final bool modoSeleccion;
  final bool seleccionada;
  final VoidCallback? onToggleSeleccion;
  // Solo se pasa desde dentro de un grupo: saca la nota de su grupo sin
  // borrarla. Si es null, no se muestra el botón (tablero principal).
  final VoidCallback? onQuitarDeGrupo;

  const PostItCard({
    super.key,
    required this.nota,
    required this.index,
    required this.columnasTotales,
    required this.onTapEditar,
    required this.onDelete,
    this.modoSeleccion = false,
    this.seleccionada = false,
    this.onToggleSeleccion,
    this.onQuitarDeGrupo,
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
    final bool tieneTitulo = widget.nota.titulo.isNotEmpty;
    final bool esLista = widget.nota.tipo == TipoNota.lista;

    // Para notas de lista, "texto" está vacío (el contenido vive en
    // elementosLista), así que no sirve para medir el tramo de letra: se
    // fuerza siempre el tramo chico para que quepan los renglones con
    // checkbox. Si hay título, el cuerpo tiene menos alto disponible, así
    // que también se baja un tramo para no desbordar la tarjeta.
    final int largoTexto = esLista
        ? 40
        : widget.nota.texto.length + (tieneTitulo ? 20 : 0);

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

    final Widget cuerpo = widget.nota.tipo == TipoNota.lista
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
          );

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
              onTap: widget.modoSeleccion ? widget.onToggleSeleccion : widget.onTapEditar,
              child: Opacity(
                opacity: widget.modoSeleccion && !widget.seleccionada ? 0.6 : 1.0,
                child: Container(
                alignment: tieneTitulo ? Alignment.topLeft : alineacionCaja,
                clipBehavior: Clip.antiAlias,
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
                child: tieneTitulo
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.nota.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.black87, fontSize: tamanoLetra + 5, height: 1.15, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 4 * factorEscala + 2),
                        cuerpo,
                      ],
                    )
                  : cuerpo,
                ),
              ),
            ),
            if (!widget.modoSeleccion)
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
            if (widget.modoSeleccion)
              Positioned(
                top: 6,
                right: 6,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.seleccionada ? Colors.black87 : Colors.white,
                      border: Border.all(color: Colors.black54, width: 1.5),
                    ),
                    child: widget.seleccionada
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            if (widget.onQuitarDeGrupo != null)
              Positioned(
                top: 0,
                left: clipAlaIzquierda ? null : 10,
                right: clipAlaIzquierda ? 10 : null,
                child: GestureDetector(
                  onTap: widget.onQuitarDeGrupo,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white70),
                    child: const Icon(Icons.link_off_rounded, size: 16, color: Colors.black54),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
