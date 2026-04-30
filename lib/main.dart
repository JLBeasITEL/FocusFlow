import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/screens/home_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notificaciones_service.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

void main() async {
  // 1. Asegura que Flutter esté listo para comandos nativos
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Inicializa el motor de alarmas de Android (El despertador)
  await AndroidAlarmManager.initialize();

  // 3. Configura el idioma de fechas
  await initializeDateFormatting('es', null);
  
  // 4. Configura el canal de notificaciones visuales
  await NotificacionesService().init(); 

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FocusFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}