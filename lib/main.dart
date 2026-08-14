import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/rutina_form_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notificaciones_service.dart';
import 'services/widget_background_dispatcher.dart';
import 'services/widget_tareas_service.dart';
import 'services/widget_rutinas_service.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'core/app_messenger.dart';

// 1. Creamos una llave global para navegar desde cualquier parte (incluso en segundo plano)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

    // Registra el callback que atiende los clicks en los íconos interactivos
    // de los widgets de pantalla de inicio (alternar modo en Tareas, refresh
    // en Rutinas). Único punto de entrada headless posible: home_widget
    // reemplaza el handle anterior en vez de apilarlos (ver
    // widget_background_dispatcher.dart).
    await HomeWidget.registerInteractivityCallback(widgetsBackgroundCallback);

    // Tocar la tarjeta de un widget (fuera de sus íconos interactivos, que
    // tienen su propio manejo vía el callback de arriba) trae la app al
    // frente por launchMode="singleTop" y home_widget emite este evento acá.
    // Cubre el caso "la app ya estaba corriendo"; el cold start (proceso
    // muerto) se maneja aparte más abajo con initiallyLaunchedFromHomeWidget,
    // porque a diferencia de HomeScreen (ya es `home:`), RutinaFormScreen
    // necesita un push explícito para aparecer.
    HomeWidget.widgetClicked.listen(_manejarClickWidget);

    final uriDeLanzamiento = await HomeWidget.initiallyLaunchedFromHomeWidget();

    runApp(
      ProviderScope(
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
// RutinaFormScreen no lo es.
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
    // Resumen todavía no tiene un servicio de datos propio (llega en la
    // Fase 5); por ahora solo se le pide refrescar su vista actual. Nota
    // rápida no depende de datos, pero se refresca igual por consistencia
    // con los otros 3 widgets.
    HomeWidget.updateWidget(androidName: 'ResumenWidgetProvider');
    HomeWidget.updateWidget(androidName: 'NotaRapidaWidgetProvider');
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