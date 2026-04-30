import 'dart:io';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/tarea.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';

class NotificacionesService {
  static final NotificacionesService _instancia = NotificacionesService._interno();
  factory NotificacionesService() => _instancia;
  NotificacionesService._interno();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  
  // ID de canal centralizado para evitar problemas de compatibilidad
  static const String canalIdGlobal = 'canal_tareas_pro_v3';

  Future<void> init() async {
    print('🔧 Iniciando servicio de notificaciones con ZonedSchedule...');
    tz.initializeTimeZones();
    
    try {
      var zonaDetectada = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zonaDetectada.toString()));
      print('🌎 Zona horaria detectada: $zonaDetectada');
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('America/Mexico_City')); 
      print('⚠️ Zona horaria forzada a America/Mexico_City debido a error: $e');
    }

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);
    
    // Crear el canal de alta prioridad de forma explícita
    final AndroidNotificationChannel channel = const AndroidNotificationChannel(
      canalIdGlobal,
      'Alertas de Tareas',
      importance: Importance.max,
      description: 'Canal principal para recordatorios exactos',
      playSound: true,
      enableVibration: true,
    );

    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _plugin.initialize(initSettings);

    print('🔐 Solicitando permisos básicos de Android...');
    if (Platform.isAndroid) {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
    }
    
    print('✅ Inicialización del servicio completa.');
  }

  // --- AUTOMATIZACIÓN DE PERMISOS ESPECIALES (EL ESCUDO) ---
  Future<void> solicitarPermisosEspeciales() async {
    if (!Platform.isAndroid) return;
    print('🔍 Verificando permisos agresivos de batería y alarmas...');

    final statusAlarma = await Permission.scheduleExactAlarm.status;
    if (statusAlarma.isDenied) {
      print('⚠️ Permiso de alarma exacta denegado. Abriendo diálogo...');
      await Permission.scheduleExactAlarm.request(); 
    }

    final statusBateria = await Permission.ignoreBatteryOptimizations.status;
    if (!statusBateria.isGranted) {
      print('⚠️ Batería optimizada. Abriendo diálogo para lista blanca...');
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> programarAlertaDefinitiva(Tarea tarea) async {
    final int idBase = tarea.id.hashCode.abs() % 100000;
    await cancelarAlerta(tarea.id);

    if (tarea.esCompletada || tarea.fechaLimite == null) return;

    final ahoraReal = DateTime.now(); 
    final ahoraTz = tz.TZDateTime.now(tz.local);
    final random = Random(); // 🎲 Inicializamos el generador aleatorio

    print('📅 Calculando alertas (ID: $idBase) para "${tarea.titulo}"...');

    // --- 1. FECHA LÍMITE ---
    if (tarea.fechaLimite!.isAfter(ahoraReal)) {
      final cuantoFalta = tarea.fechaLimite!.difference(ahoraReal);
      final tzLimite = ahoraTz.add(cuantoFalta);
      
      final opcionesLimite = [
        {'titulo': '🚨 ¡Se acabó el tiempo!', 'cuerpo': 'Tu tarea "${tarea.titulo}" acaba de vencer.'},
        {'titulo': '⏰ Tiempo agotado', 'cuerpo': 'La fecha límite para "${tarea.titulo}" ha llegado.'},
        {'titulo': '🛑 Límite alcanzado', 'cuerpo': 'Es la hora cero para entregar "${tarea.titulo}".'},
        {'titulo': '🔔 Fin del plazo', 'cuerpo': 'El tiempo programado para "${tarea.titulo}" ha terminado.'},
        {'titulo': '🏁 Meta final', 'cuerpo': 'Se cumplió el plazo de "${tarea.titulo}". ¡Ojalá la hayas terminado!'},
      ];

      // Elegimos una opción al azar (del 0 al 4)
      var seleccion = opcionesLimite[random.nextInt(opcionesLimite.length)];
      String tituloLimite = seleccion['titulo']!;
      String cuerpoLimite = seleccion['cuerpo']!;
      
      // Mantenemos la regla especial: si es urgencia máxima, sobrescribe el azar
      if (tarea.urgencia == 4) {
         tituloLimite = '🔥 ¡URGENTE: TIEMPO AGOTADO!';
         cuerpoLimite = 'La tarea prioritaria "${tarea.titulo}" ha llegado a su límite.';
      }

      await _programarNotificacion(idBase + 2, tituloLimite, cuerpoLimite, tzLimite, tarea.fechaLimite!);
    } else {
      print('⚠️ La fecha límite (${tarea.fechaLimite}) ya pasó. No se programa.');
    }

    // --- 2. RECORDATORIO (1 hora antes) ---
    final fechaRecordatorio = tarea.fechaLimite!.subtract(const Duration(minutes: 60));
    if (fechaRecordatorio.isAfter(ahoraReal)) {
      final cuantoFalta = fechaRecordatorio.difference(ahoraReal);
      final tzRecordatorio = ahoraTz.add(cuantoFalta);
      
      final opcionesRecordatorio = [
        {'titulo': '⏳ Queda 1 hora', 'cuerpo': 'El tiempo vuela. Solo falta una hora para entregar "${tarea.titulo}".'},
        {'titulo': '⏱️ Tic tac...', 'cuerpo': 'En 60 minutos vence "${tarea.titulo}". ¡Tú puedes!'},
        {'titulo': '🏃 Recta final', 'cuerpo': 'Última hora para terminar "${tarea.titulo}". ¡Acelera el paso!'},
        {'titulo': '🔔 Último aviso', 'cuerpo': 'Se acerca la hora de entrega para "${tarea.titulo}".'},
        {'titulo': '👀 No lo olvides', 'cuerpo': 'Falta menos de una hora para el límite de "${tarea.titulo}".'},
      ];

      var seleccion = opcionesRecordatorio[random.nextInt(opcionesRecordatorio.length)];

      await _programarNotificacion(idBase + 1, seleccion['titulo']!, seleccion['cuerpo']!, tzRecordatorio, fechaRecordatorio);
    }

    // --- 3. URGENCIA (Alerta de inicio) ---
    if (tarea.horasEstimadas != null && tarea.horasEstimadas! > 0) {
      final fechaUrgencia = tarea.fechaLimite!.subtract(Duration(hours: tarea.horasEstimadas!));
      if (fechaUrgencia.isAfter(ahoraReal)) {
        final cuantoFalta = fechaUrgencia.difference(ahoraReal);
        final tzUrgencia = ahoraTz.add(cuantoFalta);
        
        final opcionesInicio = [
          {'titulo': '🚀 Es hora de empezar', 'cuerpo': 'Calculaste ${tarea.horasEstimadas} hrs. ¡Deberías empezar "${tarea.titulo}" justo ahora!'},
          {'titulo': '🛠️ ¡Manos a la obra!', 'cuerpo': 'Para terminar a tiempo "${tarea.titulo}", necesitas iniciar en este momento.'},
          {'titulo': '💡 Momento de actuar', 'cuerpo': 'Es el momento ideal para comenzar "${tarea.titulo}". ¡Mucho éxito!'},
          {'titulo': '⚙️ Engranajes en marcha', 'cuerpo': 'Tu estimado es de ${tarea.horasEstimadas} hrs. Inicia "${tarea.titulo}" para no atrasarte.'},
          {'titulo': '🎯 Objetivo a la vista', 'cuerpo': 'Comienza a trabajar en "${tarea.titulo}" ahora para cumplir con tu meta a tiempo.'},
        ];

        var seleccion = opcionesInicio[random.nextInt(opcionesInicio.length)];

        await _programarNotificacion(idBase, seleccion['titulo']!, seleccion['cuerpo']!, tzUrgencia, fechaUrgencia);
      }
    }
  }

  // --- FUNCIÓN INTERNA DE AGENDAMIENTO ---
  Future<void> _programarNotificacion(int id, String titulo, String body, tz.TZDateTime fechaSistema, DateTime fechaVisual) async {
    print('🕒 Agendando notificación para que suene a las: $fechaVisual');
    
    try {
      await _plugin.zonedSchedule(
        id,
        titulo,
        body,
        fechaSistema,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            canalIdGlobal, // Usamos el canal explícito
            'Alertas de Tareas',
            importance: Importance.max,
            priority: Priority.high,
            color: Color(0xFF276749),
            fullScreenIntent: true, 
          ),
        ),
        // alarmClock es el modo más agresivo para saltar la suspensión nativa
        androidScheduleMode: AndroidScheduleMode.alarmClock, 
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      print('✅ Alarma registrada con éxito en el sistema (Modo AlarmClock).');
    } catch (e) {
      print('❌ ERROR AL AGENDAR ALARMA: $e');
    }
  }

  // --- MÉTODOS DE UTILIDAD Y LIMPIEZA ---
  Future<void> cancelarAlerta(String id) async {
    final int idBase = id.hashCode.abs() % 100000;
    await _plugin.cancel(idBase);
    await _plugin.cancel(idBase + 1);
    await _plugin.cancel(idBase + 2);
    print('🚫 Alarmas canceladas para ID: $idBase');
  }

  
}