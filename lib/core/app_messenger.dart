import 'package:flutter/material.dart';

// Key global de ScaffoldMessenger: permite mostrar SnackBars desde
// cualquier parte de la app sin depender del BuildContext de un widget en
// particular, que puede desmontarse antes de que el usuario interactúe
// con el SnackBar (ver el StateError de "ref" tras un Navigator.pop).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

// Duración única para todos los SnackBars de la app.
const duracionSnackBar = Duration(seconds: 5);

void mostrarSnackBarDeshacer({
  required String mensaje,
  required VoidCallback onDeshacer,
  Color? colorFondo,
  Color? colorTexto,
}) {
  _mostrar(mensaje: mensaje, colorFondo: colorFondo, colorTexto: colorTexto, onDeshacer: onDeshacer);
}

// Variante sin acción, usada por Tareas y Rutinas (ya no tienen "Deshacer").
void mostrarSnackBarSimple({
  required String mensaje,
  Color? colorFondo,
  Color? colorTexto,
}) {
  _mostrar(mensaje: mensaje, colorFondo: colorFondo, colorTexto: colorTexto);
}

void _mostrar({
  required String mensaje,
  Color? colorFondo,
  Color? colorTexto,
  VoidCallback? onDeshacer,
}) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      padding: EdgeInsets.zero,
      backgroundColor: colorFondo,
      duration: duracionSnackBar,
      behavior: SnackBarBehavior.floating,
      content: _ContenidoSnackBar(
        mensaje: mensaje,
        colorTexto: colorTexto,
        colorBarra: _oscurecer(colorFondo ?? Colors.black87),
        onDeshacer: onDeshacer,
      ),
    ),
  );
  // ScaffoldMessengerState NO autocierra un SnackBar con "action" cuando
  // MediaQuery.accessibleNavigation está activo (lectores de pantalla) —
  // es a propósito, para darle más tiempo a esos usuarios. Como acá el
  // requisito es que dure siempre exactamente 5s, forzamos el cierre con
  // nuestro propio temporizador en vez de depender del interno.
  Future.delayed(duracionSnackBar, () {
    try {
      controller.close();
    } catch (e) {
      debugPrint('Error al cerrar el SnackBar diferido: $e');
    }
  });
}

Color _oscurecer(Color color, [double cantidad = 0.25]) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - cantidad).clamp(0.0, 1.0)).toColor();
}

// Mensaje + botón "Deshacer" (opcional) con una barra delgada arriba que se
// achica de izquierda a derecha durante los 5s del SnackBar, como indicador
// visual del tiempo restante antes del auto-cierre.
class _ContenidoSnackBar extends StatelessWidget {
  final String mensaje;
  final Color colorBarra;
  final Color? colorTexto;
  final VoidCallback? onDeshacer;

  const _ContenidoSnackBar({
    required this.mensaje,
    required this.colorBarra,
    this.colorTexto,
    this.onDeshacer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BarraTiempoRestante(color: colorBarra),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(child: Text(mensaje, style: colorTexto != null ? TextStyle(color: colorTexto) : null)),
              if (onDeshacer != null)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: colorTexto,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    // El elemento capturado al momento de borrar puede haber
                    // quedado obsoleto (p. ej. el provider se reconstruyó
                    // mientras el SnackBar estaba visible); si "Deshacer"
                    // falla, se registra el error en vez de dejarlo escalar
                    // como excepción no manejada.
                    try {
                      onDeshacer!();
                    } catch (e) {
                      debugPrint('Error al deshacer: $e');
                    }
                    scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
                  },
                  child: const Text('Deshacer', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarraTiempoRestante extends StatelessWidget {
  final Color color;

  const _BarraTiempoRestante({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 0.0),
        duration: duracionSnackBar,
        curve: Curves.linear,
        builder: (context, valor, _) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: valor.clamp(0.0, 1.0),
          child: Container(color: color),
        ),
      ),
    );
  }
}
