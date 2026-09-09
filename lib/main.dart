import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/rutina_form_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/widgets/nota_dialog.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notificaciones_service.dart';
import 'services/widget_background_dispatcher.dart';
import 'services/widget_tareas_service.dart';
import 'services/widget_rutinas_service.dart';
import 'services/widget_notas_service.dart';
import 'services/widget_progreso_service.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'core/app_messenger.dart';
import 'providers/temporizador_rutina_provider.dart';

// 1. Creamos una llave global para navegar desde cualquier parte (incluso en segundo plano)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Contenedor de Riverpod creado a mano (en vez de dejar que ProviderScope lo
// arme internamente) para que el handler de clicks del widget de Rutinas
// pueda pedir un cambio de pestaña (tabSolicitadaWidgetProvider) desde fuera
// del árbol de widgets, igual que navigatorKey permite navegar desde fuera.
// Se lo pasa a MyApp vía UncontrolledProviderScope para que sea EL MISMO
// contenedor que usa toda la app, no uno separado con estado propio.
final container = ProviderContainer();

void main() {
  // Sin este zone, cualquier excepción que ocurra fuera del ciclo de build
  // normal (Future.delayed, Timer, callbacks diferidos como el de "Deshacer")
  // no la atrapa el framework de Flutter: sube como error no capturado y en
  // una app instalada eso se traduce en un cierre abrupto sin ningún log que
  // lo explique. Con runZonedGuarded queda registrada y la app sigue viva.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError capturado: ${details.exceptionAsString()}');
    };

    await AndroidAlarmManager.initialize();
    await initializeDateFormatting('es', null);

    // Es vital pasar la llave aquí
    await NotificacionesService().init(navigatorKey);

    // Registra el callback que atiende los clicks que NO abren la app
    // (alternar modo en Tareas, completar una rutina desde su checkbox).
    // Único punto de entrada headless posible: home_widget reemplaza el
    // handle anterior en vez de apilarlos, así que widget_background_dispatcher.dart
    // despacha por uri.host en vez de registrar uno nuevo por acción.
    await HomeWidget.registerInteractivityCallback(widgetsBackgroundCallback);

    // Tocar la tarjeta de un widget (fuera de sus íconos/checkboxes propios,
    // que tienen su propio manejo headless vía el callback de arriba) trae
    // la app al frente por launchMode="singleTop" y home_widget emite este
    // evento acá. Cubre el caso "la app ya estaba corriendo"; el cold start
    // (proceso muerto) se maneja aparte más abajo con
    // initiallyLaunchedFromHomeWidget, porque a diferencia de HomeScreen (ya
    // es `home:`), RutinaFormScreen y el cambio de pestaña a Rutinas
    // necesitan un paso extra tras montar.
    HomeWidget.widgetClicked.listen(_manejarClickWidget);

    final uriDeLanzamiento = await HomeWidget.initiallyLaunchedFromHomeWidget();

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: MyApp(),
      ),
    );

    if (uriDeLanzamiento != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _manejarClickWidget(uriDeLanzamiento);
      });
    }
  }, (error, stackTrace) {
    debugPrint('Error no capturado fuera del árbol de widgets: $error\n$stackTrace');
  });
}

// Atiende tanto el click con la app ya corriendo (HomeWidget.widgetClicked)
// como el cold start (initiallyLaunchedFromHomeWidget) — mismo Uri, mismo
// destino en ambos casos. 'abrir_tareas' no necesita push porque HomeScreen
// ya es la pantalla inicial (`home:`); 'programar_rutina' sí, porque
// RutinaFormScreen no lo es. 'abrir_rutinas' además pide el cambio a la
// pestaña de Rutinas: se escribe TANTO en currentTabIndexProvider (estado
// persistente, fuente de verdad para el initialIndex del TabController de
// la PRÓXIMA vez que HomeScreen se monte) COMO en tabSolicitadaWidgetProvider
// (comando de un solo uso que anima la pestaña si HomeScreen YA está
// montado). Se observó que, al traer la app al frente desde este widget con
// la app ya corriendo en segundo plano, HomeScreen a veces se remonta de
// cero (motivo no confirmado, posiblemente ligado al ciclo de vida de la
// Activity al volver de background) DESPUÉS de que este handler ya corrió:
// con solo tabSolicitadaWidgetProvider (comando efímero, ya consumido y
// limpiado por la instancia vieja), la instancia nueva no tenía forma de
// enterarse y volvía siempre a la pestaña 0 (Tareas). currentTabIndexProvider
// sobrevive ese remont porque vive en el ProviderContainer, no en el State
// de HomeScreen. Completar una rutina desde su checkbox NO pasa por acá: es
// headless, vía widget_background_dispatcher.dart, así que nunca abre la app.
void _manejarClickWidget(Uri? uri) {
  switch (uri?.host) {
    case 'abrir_tareas':
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      break;
    case 'programar_rutina':
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => const RutinaFormScreen()),
      );
      break;
    case 'abrir_rutinas':
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      container.read(currentTabIndexProvider.notifier).actualizar(1);
      container.read(tabSolicitadaWidgetProvider.notifier).solicitar(1);
      break;
    case 'abrir_notas':
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      container.read(currentTabIndexProvider.notifier).actualizar(2);
      container.read(tabSolicitadaWidgetProvider.notifier).solicitar(2);
      break;
    // Tocar una tarjeta puntual del widget de Notas: además de llevar a la
    // pestaña Notas, empuja AbrirNotaTrigger con el id que venga en la
    // query string (ver NotasWidgetProviderBase.kt), que abre esa nota en
    // el mismo diálogo de vista previa/edición que el tablero. Si el id no
    // existe más (nota borrada mientras tanto) mostrarDialogoNota no abre
    // nada y el trigger se cierra solo — mismo blindaje que usa el tablero.
    case 'abrir_nota':
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      container.read(currentTabIndexProvider.notifier).actualizar(2);
      container.read(tabSolicitadaWidgetProvider.notifier).solicitar(2);
      final idNota = uri?.queryParameters['id'];
      if (idNota != null && idNota.isNotEmpty) {
        navigatorKey.currentState?.push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.transparent,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondaryAnimation) => AbrirNotaTrigger(idNota: idNota),
          ),
        );
      }
      break;
    // Botones "+ Nueva nota" del widget de Notas: además de llevar a la
    // pestaña Notas (igual que 'abrir_notas'), empuja NuevaNotaTrigger, que
    // abre el mismo diálogo de creación que el botón "+" de la app (ver
    // nota_dialog.dart). Sin transición ni barrera propias porque el
    // diálogo ya trae las suyas — evita un parpadeo de pantalla en blanco
    // entre el push y el momento en que showGeneralDialog pinta encima.
    case 'nueva_nota':
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      container.read(currentTabIndexProvider.notifier).actualizar(2);
      container.read(tabSolicitadaWidgetProvider.notifier).solicitar(2);
      navigatorKey.currentState?.push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) => const NuevaNotaTrigger(),
        ),
      );
      break;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _sincronizarWidgetsAlPasarASegundoPlano();
      // El tick del temporizador de rutinas no debe seguir corriendo con la
      // app invisible: la cuenta real la lleva la alarma nativa (Android),
      // no este Timer.periodic en memoria — ver temporizador_rutina_provider.dart.
      container.read(temporizadorRutinaProvider.notifier).detenerTick();
    } else if (state == AppLifecycleState.resumed) {
      // iniciarTick() recalcula por diferencia contra venceEn ANTES de
      // reanudar el Timer.periodic, así que el primer valor mostrado tras
      // volver de segundo plano ya es el correcto (nunca continúa desde el
      // valor viejo con el que se pausó).
      container.read(temporizadorRutinaProvider.notifier).iniciarTick();
    }
  }

  // Red de seguridad adicional: si el isolate headless que atiende el toggle
  // del widget de Tareas llegara a fallar en algún escenario no cubierto,
  // este refresco (que corre en el isolate principal, con acceso confirmado
  // a los datos reales) deja ambos modos del widget de Tareas ya calculados
  // y al día antes de que la app pase a segundo plano o se cierre.
  void _sincronizarWidgetsAlPasarASegundoPlano() {
    WidgetTareasService.actualizarAmbosModos();
    WidgetRutinasService.actualizar();
    WidgetNotasService.actualizar();
    // Progreso combina totales de Tareas (recalculados acá) y de Rutinas
    // (ya recalculados arriba, publicados bajo sus propias claves): por eso
    // va al final, después de que ambos estén al día.
    WidgetProgresoService.actualizar();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(child: HomeScreen()),
    );
  }
}