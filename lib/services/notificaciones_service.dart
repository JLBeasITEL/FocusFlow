import 'dart:io';
import 'dart:typed_data'; 
import 'package:app_tareas/presentation/screens/pantalla_alarma.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart'; 
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Importación crucial para leer los sonidos
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
  
  // Cambiamos a v4 para forzar a Android a limpiar la caché anterior
  static const String canalRecordatoriosId = 'canal_recordatorios_v4';
  static const String canalAlarmasId = 'canal_alarmas_v4';

  Future<void> init(GlobalKey<NavigatorState> key) async {
    _navigatorKey = key;
    tz.initializeTimeZones();
    
    try {
      var zonaDetectada = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zonaDetectada.toString()));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('America/Mexico_City')); 
    }

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('app_icon');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);

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
      int iconoCode = 0; 

      if (partes.length >= 5) { 
        id = int.tryParse(partes[1]) ?? 0;
        titulo = partes[2];
        cuerpo = partes[3];
        iconoCode = int.tryParse(partes[4]) ?? 0; 
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

    bool usarPantallaCompleta = false;
    bool usarLoopInsistente = false;

    if (tarea.urgencia == 4) { 
      usarPantallaCompleta = true;
      usarLoopInsistente = true;
    } else if (tarea.urgencia == 3) { 
      usarPantallaCompleta = true;
      usarLoopInsistente = false; 
    } else { 
      usarPantallaCompleta = false;
      usarLoopInsistente = false; 
    }

    if (tarea.fechaLimite!.isAfter(ahoraReal)) {
      final tzLimite = ahoraTz.add(tarea.fechaLimite!.difference(ahoraReal));
      String titulo = tarea.urgencia == 4 ? '🔥 ¡URGENTE: TIEMPO AGOTADO!' : '⏰ Tiempo agotado';
      String cuerpo = tarea.urgencia == 4 ? 'La tarea prioritaria "${tarea.titulo}" ha llegado a su límite.' : 'La fecha límite para "${tarea.titulo}" ha llegado.';
      
      await _programarNotificacion(idBase + 2, titulo, cuerpo, tzLimite, 
        esAlarmaFullScreen: usarPantallaCompleta, 
        esInsistente: usarLoopInsistente
      );
    }

    final fechaRecordatorio = tarea.fechaLimite!.subtract(const Duration(minutes: 60));
    if (fechaRecordatorio.isAfter(ahoraReal)) {
      final tzRecordatorio = ahoraTz.add(fechaRecordatorio.difference(ahoraReal));
      await _programarNotificacion(idBase + 1, '⏳ Queda 1 hora', 'En 60 minutos vence "${tarea.titulo}".', tzRecordatorio, 
        esAlarmaFullScreen: false, 
        esInsistente: false
      );
    }

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
      // 1. Leemos los sonidos guardados
      final prefs = await SharedPreferences.getInstance();
      final sonidoNota = prefs.getString('sonido_notificacion') ?? 'default_nota';
      final sonidoAlarma = prefs.getString('sonido_alarma') ?? 'default_alarma';

      // 2. Elegimos qué sonido y canal usar
      final String sonidoElegido = esAlarmaFullScreen ? sonidoAlarma : sonidoNota;
      final String canalDinamicoId = esAlarmaFullScreen 
          ? '${canalAlarmasId}_$sonidoAlarma' 
          : '${canalRecordatoriosId}_$sonidoNota';

      final List<int>? flags = esInsistente ? <int>[4] : null;

      final AndroidNotificationDetails detalles = esAlarmaFullScreen
          ? AndroidNotificationDetails(canalDinamicoId, 'Alarmas Urgentes', 
              importance: Importance.max, priority: Priority.max, color: const Color(0xFF276749), fullScreenIntent: true, 
              playSound: true, sound: RawResourceAndroidNotificationSound(sonidoElegido), // <-- AQUÍ SE REPRODUCE EL SONIDO
              additionalFlags: flags != null ? Int32List.fromList(flags) : null)
          : AndroidNotificationDetails(canalDinamicoId, 'Recordatorios', 
              importance: Importance.high, priority: Priority.high, color: const Color(0xFF276749), fullScreenIntent: false,
              playSound: true, sound: RawResourceAndroidNotificationSound(sonidoElegido)); // <-- AQUÍ SE REPRODUCE EL SONIDO

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
    int? iconoCode, 
    bool esAlarmaFullScreen = true, bool esInsistente = true
  }) async {
    final tz.TZDateTime fechaSistema = tz.TZDateTime.from(fechaVisual, tz.getLocation('America/Mexico_City'));
    try {
      final prefs = await SharedPreferences.getInstance();
      final sonidoNota = prefs.getString('sonido_notificacion') ?? 'default_nota';
      final sonidoAlarma = prefs.getString('sonido_alarma') ?? 'default_alarma';

      final String sonidoElegido = esAlarmaFullScreen ? sonidoAlarma : sonidoNota;
      final String canalDinamicoId = esAlarmaFullScreen 
          ? '${canalAlarmasId}_$sonidoAlarma' 
          : '${canalRecordatoriosId}_$sonidoNota';

      final List<int>? flags = esInsistente ? <int>[4] : null;

      final AndroidNotificationDetails detalles = esAlarmaFullScreen
          ? AndroidNotificationDetails(canalDinamicoId, 'Alarmas Urgentes', importance: Importance.max, priority: Priority.max, color: const Color(0xFF276749), fullScreenIntent: true, playSound: true, sound: RawResourceAndroidNotificationSound(sonidoElegido), additionalFlags: flags != null ? Int32List.fromList(flags) : null)
          : AndroidNotificationDetails(canalDinamicoId, 'Recordatorios', importance: Importance.high, priority: Priority.high, color: const Color(0xFF276749), fullScreenIntent: false, playSound: true, sound: RawResourceAndroidNotificationSound(sonidoElegido));

      final String payloadData = esAlarmaFullScreen ? 'alarma|$id|$titulo|$body|${iconoCode ?? 0}' : '';

      await _plugin.zonedSchedule(
        id, titulo, body, fechaSistema,
        NotificationDetails(android: detalles),
        androidScheduleMode: AndroidScheduleMode.alarmClock, 
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: esAlarmaFullScreen ? payloadData : null, 
        // ESTA LÍNEA HACE QUE SE REPITA TODAS LAS SEMANAS INFINITAMENTE
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, 
      );
    } catch (e) {
       print('❌ Error agendando rutina: $e');
    }
  }

  Future<void> apagarSonidoAlarma(int id) async {
    try {
      if (id != 0) await _plugin.cancel(id); 
    } catch (e) {
      // Ignorar
    }
  }

  Future<void> cancelarAlerta(String id) async {
    final int idBase = id.hashCode.abs() % 100000;
    await _plugin.cancel(idBase);
    await _plugin.cancel(idBase + 1);
    await _plugin.cancel(idBase + 2);
  }

  Future<void> cancelarAlertaRutina(int id) async {
    try { await _plugin.cancel(id); } catch (e) { // Ignorar
    }
  }

  Future<void> programarRecordatoriosSecundarios(int idBase, String titulo, DateTime horaAlarma) async {
    final prefs = await SharedPreferences.getInstance();
    final sonidoNota = prefs.getString('sonido_notificacion') ?? 'default_nota';
    final canalDinamicoId = '${canalRecordatoriosId}_$sonidoNota';

    for (int i = 1; i <= 3; i++) {
      final fechaRecordatorio = horaAlarma.add(Duration(hours: i));
      final int idRecordatorio = idBase + (i * 10000); 
      
      final tz.TZDateTime fechaSistema = tz.TZDateTime.from(fechaRecordatorio, tz.local);

      try {
        await _plugin.zonedSchedule(
          idRecordatorio,
          'Sigue pendiente: $titulo',
          'No olvides registrar este hábito para no perder tu racha.',
          fechaSistema,
          NotificationDetails(
            android: AndroidNotificationDetails(
              canalDinamicoId, 
              'Recordatorios Horarios',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(sonidoNota),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, 
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      } catch (e) {
        print('❌ Error agendando recordatorio secundario: $e');
      }
    }
  }

  Future<void> cancelarRecordatoriosSecundarios(int idBase) async {
    for (int i = 1; i <= 3; i++) {
      await _plugin.cancel(idBase + (i * 10000));
    }
    print('🧹 Recordatorios secundarios cancelados para ID: $idBase');
  }

  Future<void> posponerAlerta(int idAlarma, String titulo, String cuerpo, int minutos) async {
    // 1. Cancelar la notificación activa para que Android la trate como una NUEVA alarma al sonar
    await _plugin.cancel(idAlarma);

    final tz.TZDateTime nuevaHora = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutos));
    final String datosPayload = 'alarma|$idAlarma|$titulo|$cuerpo|0'; 

    try {
      final prefs = await SharedPreferences.getInstance();
      final sonidoAlarma = prefs.getString('sonido_alarma') ?? 'default_alarma';
      final canalDinamicoId = '${canalAlarmasId}_$sonidoAlarma';

      await _plugin.zonedSchedule(
        idAlarma,
        titulo,
        cuerpo.isEmpty ? 'Pospuesto' : cuerpo,
        nuevaHora,
        NotificationDetails( 
          android: AndroidNotificationDetails(
            canalDinamicoId, 
            'Alarmas Urgentes', // Homologado con los otros métodos
            importance: Importance.max,
            priority: Priority.max, // Subido a max para forzar interrupción
            color: const Color(0xFF276749), // Agregamos tu color temático
            fullScreenIntent: true,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(sonidoAlarma),
            additionalFlags: Int32List.fromList(<int>[4]), // Mantiene el loop insistente
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: datosPayload,
      );
      print('✅ Alarma pospuesta exitosamente para dentro de $minutos minutos');
    } catch (e) {
      print('❌ Error al posponer la alarma: $e');
    }
  }

  // --- BOMBA NUCLEAR PARA ALARMAS FANTASMAS ---
  Future<void> limpiarTodasLasAlarmasDelSistema() async {
    await _plugin.cancelAll();
    print('🧹 Todas las alarmas de Android han sido reseteadas');
  }
}