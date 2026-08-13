import 'package:flutter/material.dart';

// Scrollbar que solo se dibuja cuando el contenido realmente desborda el
// viewport (maxScrollExtent > 0). A diferencia de Scrollbar(thumbVisibility:
// true), que muestra el thumb siempre (ocupando todo el track cuando no hay
// nada que scrollear), esta variante lo oculta por completo en ese caso.
//
// Requiere un ScrollController propio (no compartido con otra lista que
// pueda estar montada al mismo tiempo, ver los comentarios en
// _HomeScreenState de home_screen.dart) porque necesita leer
// controller.position.maxScrollExtent.
class OverflowScrollbar extends StatefulWidget {
  final ScrollController controller;
  final Widget child;

  const OverflowScrollbar({super.key, required this.controller, required this.child});

  @override
  State<OverflowScrollbar> createState() => _OverflowScrollbarState();
}

class _OverflowScrollbarState extends State<OverflowScrollbar> {
  bool _desborda = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_actualizar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualizar());
  }

  @override
  void didUpdateWidget(covariant OverflowScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_actualizar);
      widget.controller.addListener(_actualizar);
    }
    // El contenido pudo cambiar de tamaño (se agregó/quitó una tarea, nota o
    // rutina) sin que el usuario haya scrolleado: hay que remedir el
    // maxScrollExtent después de este frame, no solo cuando cambia el offset.
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualizar());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_actualizar);
    super.dispose();
  }

  void _actualizar() {
    if (!mounted || !widget.controller.hasClients) return;
    final bool nuevoValor = widget.controller.position.maxScrollExtent > 0;
    if (nuevoValor != _desborda) setState(() => _desborda = nuevoValor);
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: widget.controller,
      thumbVisibility: _desborda,
      child: widget.child,
    );
  }
}
