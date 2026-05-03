import 'dart:io';
import 'package:app_tareas/presentation/screens/pantalla_alarma.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/tarea.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/scheduler.dart' hide Priority;


class NotificacionesService {
  static final NotificacionesService _instancia = NotificacionesService._interno();
  factory NotificacionesService() => _instancia;
  NotificacionesService._interno();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  
  // Llave global para poder navegar a la pantalla de alarma en segundo plano
  static late GlobalKey<NavigatorState> _navigatorKey;
  
  // IDs de los canales separados
  static const String canalRecordatoriosId = 'canal_recordatorios_v3';
  static const String canalAlarmasId = 'canal_alarmas_v3';

  // Ahora init() recibe la llave de navegación de main.dart
  Future<void> init(GlobalKey<NavigatorState> key) async {
    _navigatorKey = key;
    print('🔧 Iniciando servicio de notificaciones con ZonedSchedule...');
    tz.initializeTimeZones();
    
    try {
      var zonaDetectada = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zonaDetectada.toString()));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('America/Mexico_City')); 
    }

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);
    
    // 1. Canal de RECORDATORIOS (Notificación normal)
    final AndroidNotificationChannel canalRecordatorios = const AndroidNotificationChannel(
      canalRecordatoriosId,
      'Recordatorios',
      importance: Importance.high,
      description: 'Avisos previos (1 hora antes) de tareas y rutinas',
      playSound: true,
      enableVibration: true,
    );

    // 2. Canal de ALARMAS (Pantalla Completa)
    final AndroidNotificationChannel canalAlarmas = const AndroidNotificationChannel(
      canalAlarmasId,
      'Alarmas Urgentes',
      importance: Importance.max,
      description: 'Avisos a la hora exacta que encienden la pantalla',
      playSound: true,
      enableVibration: true,
    );

    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalRecordatorios);
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalAlarmas);

    // Inicializamos el plugin y configuramos qué hacer al recibir el evento de pantalla completa
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Escuchamos si la notificación es del tipo "alarma" estando la app en segundo plano
        if (response.payload != null && response.payload!.startsWith('alarma|')) {
          _manejarNavegacionAlarma(response.payload!);
        }
      },
    );

    // --- NUEVO: Verificar si la app se abrió por una notificación (Cold Start) ---
    final NotificationAppLaunchDetails? details = await _plugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp) {
      if (details.notificationResponse?.payload != null) {
        _manejarNavegacionAlarma(details.notificationResponse!.payload!);
      }
    }

    if (Platform.isAndroid) {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
    }
  }

  // --- NUEVA FUNCIÓN: Navegación Segura ---
  void _manejarNavegacionAlarma(String payload) {
    if (payload.startsWith('alarma|')) {
      final partes = payload.split('|');
      if (partes.length >= 3) {
        final titulo = partes[1];
        final cuerpo = partes[2];

        // Usamos SchedulerBinding para esperar a que el Navigator esté listo
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => PantallaAlarma(titulo: titulo, cuerpo: cuerpo),
            ),
          );
        });
      }
    }
  }

  // --- AUTOMATIZACIÓN DE PERMISOS ESPECIALES ---
  Future<void> solicitarPermisosEspeciales() async {
    if (!Platform.isAndroid) return;
    final statusAlarma = await Permission.scheduleExactAlarm.status;
    if (statusAlarma.isDenied) {
      await Permission.scheduleExactAlarm.request(); 
    }
    final statusBateria = await Permission.ignoreBatteryOptimizations.status;
    if (!statusBateria.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  // --- ALARMAS PARA TAREAS ---
  Future<void> programarAlertaDefinitiva(Tarea tarea) async {
    final int idBase = tarea.id.hashCode.abs() % 100000;
    await cancelarAlerta(tarea.id);

    if (tarea.esCompletada || tarea.fechaLimite == null) return;

    final ahoraReal = DateTime.now(); 
    final ahoraTz = tz.TZDateTime.now(tz.local);

    // --- 1. FECHA LÍMITE (PANTALLA COMPLETA) ---
    if (tarea.fechaLimite!.isAfter(ahoraReal)) {
      final cuantoFalta = tarea.fechaLimite!.difference(ahoraReal);
      final tzLimite = ahoraTz.add(cuantoFalta);
      
      String tituloLimite = '⏰ Tiempo agotado';
      String cuerpoLimite = 'La fecha límite para "${tarea.titulo}" ha llegado.';
      
      if (tarea.urgencia == 4) {
         tituloLimite = '🔥 ¡URGENTE: TIEMPO AGOTADO!';
         cuerpoLimite = 'La tarea prioritaria "${tarea.titulo}" ha llegado a su límite.';
      }

      await _programarNotificacion(idBase + 2, tituloLimite, cuerpoLimite, tzLimite, tarea.fechaLimite!, esAlarmaFullScreen: true);
    }

    // --- 2. RECORDATORIO 1 HORA ANTES (NOTIFICACIÓN NORMAL) ---
    final fechaRecordatorio = tarea.fechaLimite!.subtract(const Duration(minutes: 60));
    if (fechaRecordatorio.isAfter(ahoraReal)) {
      final cuantoFalta = fechaRecordatorio.difference(ahoraReal);
      final tzRecordatorio = ahoraTz.add(cuantoFalta);
      
      await _programarNotificacion(idBase + 1, '⏳ Queda 1 hora', 'En 60 minutos vence "${tarea.titulo}". ¡Tú puedes!', tzRecordatorio, fechaRecordatorio, esAlarmaFullScreen: false);
    }

    // --- 3. URGENCIA / INICIO (PANTALLA COMPLETA) ---
    if (tarea.horasEstimadas != null && tarea.horasEstimadas! > 0) {
      final fechaUrgencia = tarea.fechaLimite!.subtract(Duration(hours: tarea.horasEstimadas!));
      if (fechaUrgencia.isAfter(ahoraReal)) {
        final cuantoFalta = fechaUrgencia.difference(ahoraReal);
        final tzUrgencia = ahoraTz.add(cuantoFalta);
        
        await _programarNotificacion(idBase, '🚀 Es hora de empezar', 'Deberías empezar "${tarea.titulo}" justo ahora para cumplir el estimado.', tzUrgencia, fechaUrgencia, esAlarmaFullScreen: true);
      }
    }
  }

  // --- FUNCIÓN INTERNA ---
  Future<void> _programarNotificacion(int id, String titulo, String body, tz.TZDateTime fechaSistema, DateTime fechaVisual, {required bool esAlarmaFullScreen}) async {
    try {
      final AndroidNotificationDetails detalles = esAlarmaFullScreen
          ? const AndroidNotificationDetails(canalAlarmasId, 'Alarmas Urgentes', importance: Importance.max, priority: Priority.max, color: Color(0xFF276749), fullScreenIntent: true)
          : const AndroidNotificationDetails(canalRecordatoriosId, 'Recordatorios', importance: Importance.high, priority: Priority.high, color: Color(0xFF276749), fullScreenIntent: false);

      await _plugin.zonedSchedule(
        id, titulo, body, fechaSistema,
        NotificationDetails(android: detalles),
        androidScheduleMode: AndroidScheduleMode.alarmClock, 
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: esAlarmaFullScreen ? 'alarma|$titulo|$body' : null,
      );
    } catch (e) {
      print('❌ ERROR AL AGENDAR ALARMA: $e');
    }
  }

  // --- ALARMAS PARA RUTINAS ---
  Future<void> programarAlertaRutina({
    required int id,
    required String titulo,
    required String body,
    required DateTime fechaVisual,
    bool esAlarmaFullScreen = true, 
  }) async {
    final tz.TZDateTime fechaSistema = tz.TZDateTime.from(fechaVisual, tz.getLocation('America/Mexico_City'));
    
    try {
      final AndroidNotificationDetails detalles = esAlarmaFullScreen
          ? const AndroidNotificationDetails(canalAlarmasId, 'Alarmas Urgentes', importance: Importance.max, priority: Priority.max, color: Color(0xFF276749), fullScreenIntent: true)
          : const AndroidNotificationDetails(canalRecordatoriosId, 'Recordatorios', importance: Importance.high, priority: Priority.high, color: Color(0xFF276749), fullScreenIntent: false);

      await _plugin.zonedSchedule(
        id, titulo, body, fechaSistema,
        NotificationDetails(android: detalles),
        androidScheduleMode: AndroidScheduleMode.alarmClock, 
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: esAlarmaFullScreen ? 'alarma|$titulo|$body' : null,
      );
    } catch (e) {
      print('❌ ERROR AL AGENDAR RUTINA: $e');
    }
  }  

  // --- MÉTODOS DE UTILIDAD Y LIMPIEZA ---
  Future<void> cancelarAlerta(String id) async {
    final int idBase = id.hashCode.abs() % 100000;
    await _plugin.cancel(idBase);
    await _plugin.cancel(idBase + 1);
    await _plugin.cancel(idBase + 2);
  }

  Future<void> cancelarAlertaRutina(int id) async {
    try {
      await _plugin.cancel(id); 
    } catch (e) {}
  }
}