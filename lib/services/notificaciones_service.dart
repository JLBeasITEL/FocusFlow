import 'dart:io';
import 'dart:typed_data'; 
import 'package:app_tareas/presentation/screens/pantalla_alarma.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart'; 
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/tarea.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificacionesService {
  static final NotificacionesService _instancia = NotificacionesService._interno();
  factory NotificacionesService() => _instancia;
  NotificacionesService._interno();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static late GlobalKey<NavigatorState> _navigatorKey;
  
  static const String canalRecordatoriosId = 'canal_recordatorios_v3';
  static const String canalAlarmasId = 'canal_alarmas_v3';

  Future<void> init(GlobalKey<NavigatorState> key) async {
    _navigatorKey = key;
    tz.initializeTimeZones();
    
    try {
      var zonaDetectada = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zonaDetectada.toString()));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('America/Mexico_City')); 
    }

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);
    
    final AndroidNotificationChannel canalRecordatorios = const AndroidNotificationChannel(
      canalRecordatoriosId, 'Recordatorios',
      importance: Importance.high, playSound: true, enableVibration: true,
    );

    final AndroidNotificationChannel canalAlarmas = const AndroidNotificationChannel(
      canalAlarmasId, 'Alarmas Urgentes',
      importance: Importance.max, playSound: true, enableVibration: true,
    );

    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalRecordatorios);
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalAlarmas);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.startsWith('alarma|')) {
          _manejarNavegacionAlarma(response.payload!);
        }
      },
    );

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

  void _manejarNavegacionAlarma(String payload) {
    if (payload.startsWith('alarma|')) {
      final partes = payload.split('|');
      int id = 0;
      String titulo = '';
      String cuerpo = '';
      int iconoCode = 0; // <-- NUEVA VARIABLE

      if (partes.length >= 5) { // Si trae ícono
        id = int.tryParse(partes[1]) ?? 0;
        titulo = partes[2];
        cuerpo = partes[3];
        iconoCode = int.tryParse(partes[4]) ?? 0; // Leemos el código
      } else if (partes.length == 4) {
        id = int.tryParse(partes[1]) ?? 0;
        titulo = partes[2];
        cuerpo = partes[3];
      } else if (partes.length == 3) {
        titulo = partes[1];
        cuerpo = partes[2];
      }

      SchedulerBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PantallaAlarma(idAlarma: id, titulo: titulo, cuerpo: cuerpo, iconoCode: iconoCode),
          ),
        );
      });
    }
  }

  Future<void> solicitarPermisosEspeciales() async {
    if (!Platform.isAndroid) return;
    final statusAlarma = await Permission.scheduleExactAlarm.status;
    if (statusAlarma.isDenied) await Permission.scheduleExactAlarm.request(); 
    final statusBateria = await Permission.ignoreBatteryOptimizations.status;
    if (!statusBateria.isGranted) await Permission.ignoreBatteryOptimizations.request();
  }

  // --- ALARMAS PARA TAREAS ---
  Future<void> programarAlertaDefinitiva(Tarea tarea) async {
    final int idBase = tarea.id.hashCode.abs() % 100000;
    await cancelarAlerta(tarea.id);

    if (tarea.esCompletada || tarea.fechaLimite == null) return;

    final ahoraReal = DateTime.now(); 
    final ahoraTz = tz.TZDateTime.now(tz.local);

    // 1. DETERMINAR EL NIVEL DE ALARMA SEGÚN URGENCIA
    bool usarPantallaCompleta = false;
    bool usarLoopInsistente = false;

    if (tarea.urgencia == 4) { // Muy Alta
      usarPantallaCompleta = true;
      usarLoopInsistente = true;
    } else if (tarea.urgencia == 3) { // Alta
      usarPantallaCompleta = true;
      usarLoopInsistente = false; // Suena normal, pero abre la pantalla
    } else { // Media (2) o Baja (1)
      usarPantallaCompleta = false;
      usarLoopInsistente = false; // Solo notificación discreta
    }

    // 2. PROGRAMAR FECHA LÍMITE
    if (tarea.fechaLimite!.isAfter(ahoraReal)) {
      final tzLimite = ahoraTz.add(tarea.fechaLimite!.difference(ahoraReal));
      String titulo = tarea.urgencia == 4 ? '🔥 ¡URGENTE: TIEMPO AGOTADO!' : '⏰ Tiempo agotado';
      String cuerpo = tarea.urgencia == 4 ? 'La tarea prioritaria "${tarea.titulo}" ha llegado a su límite.' : 'La fecha límite para "${tarea.titulo}" ha llegado.';
      
      await _programarNotificacion(idBase + 2, titulo, cuerpo, tzLimite, 
        esAlarmaFullScreen: usarPantallaCompleta, 
        esInsistente: usarLoopInsistente
      );
    }

    // 3. RECORDATORIO 1 HORA ANTES (Siempre será discreto)
    final fechaRecordatorio = tarea.fechaLimite!.subtract(const Duration(minutes: 60));
    if (fechaRecordatorio.isAfter(ahoraReal)) {
      final tzRecordatorio = ahoraTz.add(fechaRecordatorio.difference(ahoraReal));
      await _programarNotificacion(idBase + 1, '⏳ Queda 1 hora', 'En 60 minutos vence "${tarea.titulo}".', tzRecordatorio, 
        esAlarmaFullScreen: false, 
        esInsistente: false
      );
    }

    // 4. URGENCIA / INICIO (Usa la misma regla de urgencia que la fecha límite)
    if (tarea.horasEstimadas != null && tarea.horasEstimadas! > 0) {
      final fechaUrgencia = tarea.fechaLimite!.subtract(Duration(hours: tarea.horasEstimadas!));
      if (fechaUrgencia.isAfter(ahoraReal)) {
        final tzUrgencia = ahoraTz.add(fechaUrgencia.difference(ahoraReal));
        await _programarNotificacion(idBase, '🚀 Es hora de empezar', 'Deberías empezar "${tarea.titulo}" ahora.', tzUrgencia, 
          esAlarmaFullScreen: usarPantallaCompleta, 
          esInsistente: usarLoopInsistente
        );
      }
    }
  }

  Future<void> _programarNotificacion(int id, String titulo, String body, tz.TZDateTime fechaSistema, {required bool esAlarmaFullScreen, required bool esInsistente}) async {
    try {
      final List<int>? flags = esInsistente ? <int>[4] : null;

      final AndroidNotificationDetails detalles = esAlarmaFullScreen
          ? AndroidNotificationDetails(canalAlarmasId, 'Alarmas Urgentes', 
              importance: Importance.max, priority: Priority.max, color: const Color(0xFF276749), fullScreenIntent: true, 
              additionalFlags: flags != null ? Int32List.fromList(flags) : null)
          : const AndroidNotificationDetails(canalRecordatoriosId, 'Recordatorios', 
              importance: Importance.high, priority: Priority.high, color: Color(0xFF276749), fullScreenIntent: false);

      await _plugin.zonedSchedule(
        id, titulo, body, fechaSistema,
        NotificationDetails(android: detalles),
        androidScheduleMode: AndroidScheduleMode.alarmClock, 
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: esAlarmaFullScreen ? 'alarma|$id|$titulo|$body' : null, 
      );
    } catch (e) {
      print('❌ ERROR: $e');
    }
  }

  Future<void> programarAlertaRutina({
    required int id, required String titulo, required String body, 
    required DateTime fechaVisual, 
    int? iconoCode, // <-- AHORA ES UN ENTERO (int)
    bool esAlarmaFullScreen = true, bool esInsistente = true
  }) async {
    final tz.TZDateTime fechaSistema = tz.TZDateTime.from(fechaVisual, tz.getLocation('America/Mexico_City'));
    try {
      final List<int>? flags = esInsistente ? <int>[4] : null;

      // Quitamos el largeIcon, Android usará el logo por defecto
      final AndroidNotificationDetails detalles = esAlarmaFullScreen
          ? AndroidNotificationDetails(canalAlarmasId, 'Alarmas Urgentes', importance: Importance.max, priority: Priority.max, color: const Color(0xFF276749), fullScreenIntent: true, additionalFlags: flags != null ? Int32List.fromList(flags) : null)
          : const AndroidNotificationDetails(canalRecordatoriosId, 'Recordatorios', importance: Importance.high, priority: Priority.high, color: Color(0xFF276749), fullScreenIntent: false);

      // Enviamos el iconoCode oculto en el mensaje
      final String payloadData = esAlarmaFullScreen ? 'alarma|$id|$titulo|$body|${iconoCode ?? 0}' : '';

      await _plugin.zonedSchedule(
        id, titulo, body, fechaSistema,
        NotificationDetails(android: detalles),
        androidScheduleMode: AndroidScheduleMode.alarmClock, 
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: esAlarmaFullScreen ? payloadData : null, 
      );
    } catch (e) {}
  }

  // --- APAGAR Y CANCELAR ---
  Future<void> apagarSonidoAlarma(int id) async {
    try {
      if (id != 0) await _plugin.cancel(id); 
    } catch (e) {}
  }

  Future<void> cancelarAlerta(String id) async {
    final int idBase = id.hashCode.abs() % 100000;
    await _plugin.cancel(idBase);
    await _plugin.cancel(idBase + 1);
    await _plugin.cancel(idBase + 2);
  }

  Future<void> cancelarAlertaRutina(int id) async {
    try { await _plugin.cancel(id); } catch (e) {}
  }
}