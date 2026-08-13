import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tema_provider.dart';

const _logoGris = 'assets/images/splash_logo_gris.png';
const _logoBlanco = 'assets/images/splash_logo_blanco.png';

// Pantalla de bienvenida: se dibuja encima de [child] (que ya se está
// construyendo debajo, así sus providers cargan mientras se ve el logo) y
// se retira con un fundido una vez que el logo tuvo tiempo de mostrarse.
//
// El nombre y el logo se ocultan (_listo = false) hasta que ambas variantes
// del logo terminan de precachearse: sin esto, el texto pinta en el primer
// frame pero la imagen tarda uno o más frames en decodificar, así que se ve
// primero el nombre y el logo "aparece después" — justo el salto que se
// quería evitar. Al esperar al precache, texto y logo entran juntos en el
// mismo frame.
//
// Al ser ConsumerStatefulWidget, observa temaProvider igual que HomeScreen:
// arranca con TemaApp.clasico (valor inicial de TemaNotifier.build()) y en
// cuanto termina de leerse el tema guardado en SharedPreferences, este
// widget se reconstruye con los colores/degradado/logo correctos. Por eso
// se precachean las DOS variantes del logo (gris y blanco): todavía no se
// sabe cuál va a mostrarse cuando arranca el precache.
class SplashScreen extends ConsumerStatefulWidget {
  final Widget child;
  const SplashScreen({required this.child, super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _listo = false;
  bool _overlayVisible = true;
  bool _overlayRemovido = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precargarYMostrar());
  }

  Future<void> _precargarYMostrar() async {
    if (!mounted) return;
    final anchoCache = _anchoCache(context);
    await Future.wait([
      precacheImage(ResizeImage(const AssetImage(_logoGris), width: anchoCache), context),
      precacheImage(ResizeImage(const AssetImage(_logoBlanco), width: anchoCache), context),
    ]);
    if (!mounted) return;
    setState(() => _listo = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  // El logo fuente mide ~1200px de ancho pero se muestra a 140: sin
  // limitar el ancho de decodificación, Image procesa el PNG completo a
  // resolución nativa, lo que también contribuye a los saltos.
  int _anchoCache(BuildContext context) => (140 * MediaQuery.of(context).devicePixelRatio).round();

  @override
  Widget build(BuildContext context) {
    // Una vez terminado el fade-out ya no hace falta seguir apilando el
    // overlay (ni pagar su costo de layout) encima de la pantalla real.
    if (_overlayRemovido) return widget.child;

    final temaActual = ref.watch(temaProvider);
    // El logo gris solo contrasta bien sobre el fondo blanco de Clásico;
    // los otros 4 temas usan fondos con color/gradiente, así que llevan la
    // variante blanca (mismo criterio que "imagenFondo" en HomeScreen).
    final String logo = temaActual == TemaApp.clasico ? _logoGris : _logoBlanco;

    return Stack(
      children: [
        // RepaintBoundary aísla el árbol de HomeScreen en su propia capa,
        // para que sus propios rebuilds/animaciones no obliguen a
        // recomponer el overlay que se está desvaneciendo encima.
        RepaintBoundary(child: widget.child),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _overlayVisible ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            onEnd: () {
              if (!_overlayVisible && mounted) setState(() => _overlayRemovido = true);
            },
            // Con esto, el fundido lo resuelve el compositor variando la
            // opacidad de una capa ya rasterizada, en vez de repintar todo
            // el overlay en cada tick de la animación.
            child: RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(gradient: temaActual.degradadoFondo),
                alignment: Alignment.center,
                child: Opacity(
                  // Nombre y logo aparecen juntos recién cuando el precache
                  // de ambas imágenes termina (ver _precargarYMostrar).
                  opacity: _listo ? 1 : 0,
                  // Es puro decorativo: sin esto, TalkBack/Accessibility
                  // Scanner puede enfocar el texto "FocusFlow" por ser el
                  // primer elemento en aparecer, dibujando su indicador de
                  // foco (línea/recuadro) encima.
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(logo, width: 140, cacheWidth: _anchoCache(context), fit: BoxFit.contain),
                        const SizedBox(height: 18),
                        Text(
                          'FocusFlow',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: temaActual.colorPrincipal, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
