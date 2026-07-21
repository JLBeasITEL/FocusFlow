import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notificaciones_service.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

// 1. Creamos una llave global para navegar desde cualquier parte (incluso en segundo plano)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await AndroidAlarmManager.initialize();
  await initializeDateFormatting('es', null);
  
  // Es vital pasar la llave aquí
  await NotificacionesService().init(navigatorKey); 

  runApp(
    ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(child: HomeScreen()),
    );
  }
}