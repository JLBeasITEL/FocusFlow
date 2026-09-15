import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nota.dart';
import '../../providers/nota_provider.dart';
import 'ayuda_formulario_button.dart';

// Paleta de 12 colores pastel para las notas. Vive acá (en vez de en
// home_screen.dart) porque tanto el diálogo de creación/edición como la
// tarjeta de grupo la necesitan.
const List<Color> coloresPostIt = [
  Color(0xFFFEF08A), Color(0xFFFFF7D1),
  Color(0xFFFECACA), Color(0xFFFBCFE8),
  Color(0xFFBFDBFE), Color(0xFFBAE6FD),
  Color(0xFFBBF7D0), Color(0xFFA7F3D0),
  Color(0xFFE9D5FF), Color(0xFFDDD6FE),
  Color(0xFFFED7AA), Color(0xFFCCFBF1),
];

// Alterna destacar/no-destacar una nota (máximo 2 a la vez, ver
// alternarDestacada en nota_provider.dart) y avisa con un SnackBar cuando ya
// se alcanzó el límite, en vez de dejar que el toque no haga nada visible.
void alternarDestacadaConFeedback(BuildContext context, WidgetRef ref, String id) {
  final exito = ref.read(notaProvider.notifier).alternarDestacada(id);
  if (!exito) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ya tienes 2 notas destacadas. Quita una para destacar otra.')),
    );
  }
}

// Abre el diálogo de crear/editar nota. Sin idAEditar crea una nota nueva;
// con idAEditar busca la nota por id (en vez de por índice posicional) para
// poder invocarse tanto desde el tablero principal como desde dentro de un
// grupo, donde la posición visible no coincide con el índice en el estado.
// grupoNombrePorDefecto solo aplica al crear (se ignora si idAEditar no es
// null): deja la nota nueva ya sumada a ese grupo en vez de suelta en el
// tablero. Lo usa el botón "Nueva nota" de GrupoNotasDetalleScreen (ver
// grupo_notas_card.dart) para crear directamente dentro de la carpeta
// abierta, sin el paso extra de agregarla después con "Agregar notas".
Future<void> mostrarDialogoNota(BuildContext context, WidgetRef ref, {String? idAEditar, String? grupoNombrePorDefecto}) {
  final List<NotaPostIt> notasActuales = ref.read(notaProvider);
  final bool esNueva = idAEditar == null;
  final int indice = esNueva ? -1 : notasActuales.indexWhere((n) => n.id == idAEditar);
  if (!esNueva && indice == -1) return Future.value(); // La nota ya no existe (se borró mientras tanto)
  final NotaPostIt? notaActual = esNueva ? null : notasActuales[indice];

  final controller = TextEditingController(text: esNueva ? '' : notaActual!.texto);
  final tituloController = TextEditingController(text: esNueva ? '' : notaActual!.titulo);
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

  // Cuando el campo de un elemento de la lista recibe foco, lo hace visible
  // por encima del teclado. Sin esto, el SingleChildScrollView del diálogo
  // no sabe qué parte del contenido debe mostrar y el campo activo queda
  // tapado por el teclado al agregar varios elementos.
  FocusNode crearFocusNodeConAutoScroll() {
    final nodo = FocusNode();
    nodo.addListener(() {
      if (nodo.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = nodo.context;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        });
      }
    });
    return nodo;
  }

  List<FocusNode> focusNodesLista = itemsTemp.map((e) => crearFocusNodeConAutoScroll()).toList();

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black.withOpacity(0.6),
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AnimatedPadding(
            duration: const Duration(milliseconds: 100),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Center(
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

                        // ÁREA DE CONTENIDO (TÍTULO + TEXTO O LISTA)
                        Padding(
                          padding: const EdgeInsets.only(top: 64.0, left: 54.0, right: 16.0, bottom: 80.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // TÍTULO (OPCIONAL): se edita aparte del cuerpo y se ve
                              // más grande, tanto acá como en la tarjeta del tablero.
                              if (modoEdicion)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: TextField(
                                    controller: tituloController,
                                    textCapitalization: TextCapitalization.sentences,
                                    style: const TextStyle(fontSize: 24, color: Colors.black87, fontWeight: FontWeight.w800, height: 1.2),
                                    decoration: const InputDecoration(hintText: 'Título (opcional)', border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                                  ),
                                )
                              else if (notaActual!.titulo.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text(notaActual.titulo, style: const TextStyle(fontSize: 24, color: Colors.black87, fontWeight: FontWeight.w800, height: 1.2)),
                                ),
                              tipoActual == TipoNota.texto
                            ? (modoEdicion
                                ? TextField(
                                    controller: controller,
                                    autofocus: true,
                                    maxLines: 8, minLines: 3,
                                    textCapitalization: TextCapitalization.sentences,
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
                                                  textCapitalization: TextCapitalization.sentences,
                                                  textInputAction: TextInputAction.next, // Configura el botón del teclado como "Siguiente"
                                                  onSubmitted: (val) {
                                                    // Si el usuario presiona Enter estando en el último elemento de la lista, crea uno nuevo automáticamente
                                                    if (i == itemsTemp.length - 1) {
                                                      final nuevoFocusNode = crearFocusNodeConAutoScroll();
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
                                          final nuevoFocusNode = crearFocusNodeConAutoScroll();
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
                                  'Título: Opcional, arriba del todo. Se ve más grande que el resto tanto acá como en el tablero.',
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
                                            for (final opcion in coloresPostIt)
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
                                            focusNodesLista.add(crearFocusNodeConAutoScroll());
                                          }
                                        } else if (itemsTemp.isEmpty) {
                                          itemsTemp.add(ItemLista(texto: ''));
                                          controllersLista.add(TextEditingController());
                                          focusNodesLista.add(crearFocusNodeConAutoScroll());
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
                                      tituloController.text = notaActual.titulo;
                                      itemsTemp = notaActual.elementosLista.map((e) => ItemLista(texto: e.texto, completado: e.completado)).toList();
                                      controllersLista = itemsTemp.map((e) => TextEditingController(text: e.texto)).toList();
                                      focusNodesLista = itemsTemp.map((e) => crearFocusNodeConAutoScroll()).toList();
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
                                        notaActual!.id, controller.text, tipo: tipoActual, elementosLista: itemsTemp, colorValue: colorElegido, titulo: tituloController.text.trim()
                                      );
                                    } else {
                                      // Si el usuario no eligió color, se mantiene el comportamiento aleatorio original
                                      int colorFinal = colorElegido ?? coloresPostIt[math.Random().nextInt(coloresPostIt.length)].value;

                                      final ahora = DateTime.now().millisecondsSinceEpoch;
                                      final nueva = NotaPostIt(
                                        id: ahora.toString(),
                                        texto: controller.text,
                                        colorValue: colorFinal,
                                        rotacion: (math.Random().nextDouble() - 0.5) * 0.1,
                                        tipo: tipoActual,
                                        titulo: tituloController.text.trim(),
                                        grupoNombre: grupoNombrePorDefecto ?? '',
                                        elementosLista: itemsTemp,
                                        creadaEn: ahora,
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
          ),
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

// Ruta invisible que solo existe para abrir mostrarDialogoNota() con un
// BuildContext y WidgetRef reales (el click en el widget de Notas llega
// desde main.dart, fuera del árbol de widgets, y ese diálogo los necesita
// a ambos). No pinta nada propio: se empuja sin transición ni barrera sobre
// HomeScreen (mismo patrón que 'programar_rutina' en main.dart) y se cierra
// sola en cuanto el diálogo se despacha, dejando a HomeScreen tal cual
// hubiera quedado si el usuario tocara el botón "+" de la pestaña Notas.
class NuevaNotaTrigger extends ConsumerStatefulWidget {
  const NuevaNotaTrigger({super.key});

  @override
  ConsumerState<NuevaNotaTrigger> createState() => _NuevaNotaTriggerState();
}

class _NuevaNotaTriggerState extends ConsumerState<NuevaNotaTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await mostrarDialogoNota(context, ref);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// Misma idea que NuevaNotaTrigger pero para abrir una nota puntual al tocar
// su tarjeta en el widget de Notas (ver 'abrir_nota' en main.dart): en vez
// de crear, busca idNota en notaProvider y abre su diálogo en modo vista
// previa. Si la nota ya no existe (se borró entre que se generó el widget y
// el toque), mostrarDialogoNota no abre nada y este trigger simplemente se
// cierra solo, dejando al usuario en la pestaña Notas sin ningún error.
class AbrirNotaTrigger extends ConsumerStatefulWidget {
  final String idNota;

  const AbrirNotaTrigger({super.key, required this.idNota});

  @override
  ConsumerState<AbrirNotaTrigger> createState() => _AbrirNotaTriggerState();
}

class _AbrirNotaTriggerState extends ConsumerState<AbrirNotaTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await mostrarDialogoNota(context, ref, idAEditar: widget.idNota);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// =========================================================================
// Pintor decorativo de la libreta usado como fondo del diálogo de nota.
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
