import 'dart:io';
import 'package:app_tareas/presentation/screens/pantalla_alarma.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/foundation.dart';
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

  // Android limita a 500 alarmas concurrentes por app (IllegalStateException
  // "Maximum limit of concurrent alarms 500 reached" desde Android 12+). Si
  // el volumen de rutinas/días vuelve a crecer lo suficiente para chocar con
  // esto, este log lo hace inconfundible en vez de perderse entre los demás
  // "❌ Error" genéricos.
  void _logErrorAlarma(String contexto, Object e) {
    if (!kDebugMode) return;
    if (e.toString().contains('Maximum limit of concurrent alarms')) {
      debugPrint('🚨 LÍMITE DE ALARMAS DE ANDROID ALCANZADO ($contexto): $e');
    } else {
      debugPrint('❌ Error en $contexto: $e');
    }
  }
  
  // Cambiamos a v4 para forzar a Android a limpiar la caché anterior
  static const String canalRecordatoriosId = 'canal_recordatorios_v4';
  static const String canalAlarmasId = 'canal_alarmas_v4';

  // ============================================================
  // Temporizador opcional por rutina — ID fijo de la notificación ongoing
  // ------------------------------------------------------------
  // Un solo temporizador activo a la vez (global, ver TemporizadorRutina),
  // así que esta notificación no necesita un ID calculado por rutina/
  // ocurrencia: uno fijo alcanza. No colisiona con nada más generado en
  // este archivo: el reset completo de rutinas llega como mucho a ~210005
  // (baseId % 100000 + offsets de hasta +30000, dos semanas de colchón) y
  // el top-up incremental arranca su propio rango en 100.000.000 (ver
  // rutina_provider.dart, offsetSemanaRelleno).
  // ============================================================
  static const int idOngoingTemporizadorRutina = 999999;
  static const int idAlarmaVencimientoTemporizadorRutina = 999998;
  static const String _canalTemporizadorRutinaId = 'canal_temporizador_rutina_v1';

  // true si ESTE arranque en frío de la app fue causado por tocar la
  // notificación de vencimiento del temporizador (fullScreenIntent incluido).
  // El reconciliador de arranque (ver reconciliador_temporizador_rutina.dart)
  // lo consulta para no empujar una SEGUNDA PantallaAlarma encima de la que
  // ya empuja este init() más abajo para el mismo evento -- son dos caminos
  // independientes que, sin este chequeo, competirían por el mismo caso.
  bool huboNavegacionTemporizadorAlIniciar = false;

  // ============================================================
  // Guard anti-duplicado: qué VENCIMIENTO concreto de temporizador (no un
  // bool suelto) ya tiene una PantallaAlarma en curso o mostrada
  // ------------------------------------------------------------
  // Hoy compiten TRES caminos independientes por ofrecer la misma
  // confirmación: tocar la notificación (_manejarNavegacionAlarma, más
  // abajo), el reconciliador de arranque (reconciliador_temporizador_rutina.dart)
  // y el listener en vivo (temporizador_rutina_listener.dart, que cubre
  // primer plano y volver de segundo plano). Sin coordinación, dos de ellos
  // podrían disparar casi al mismo tiempo para el MISMO vencimiento (p. ej.
  // tocar la notificación justo cuando la app también dispara `resumed`) y
  // apilar dos PantallaAlarma.
  //
  // Se identifica por {rutinaId, venceEn} en vez de un bool global a
  // propósito: si alguna vía de salida no lo liberara correctamente (bug),
  // un bool suelto seguiría bloqueando para SIEMPRE cualquier temporizador
  // futuro, incluso uno completamente distinto. Con la identidad completa,
  // un guard que quedara pegado por error nunca bloquea un vencimiento
  // distinto (rutina u horario distintos) -- se autolimita al caso
  // exacto. La liberación real (para poder volver a ofrecer ESE MISMO
  // vencimiento si hiciera falta) la hace PantallaAlarma.dispose(), que
  // corre pase lo que pase: confirmar, o cualquier otra vía de desmontaje.
  ({String rutinaId, DateTime venceEn})? _vencimientoTemporizadorEnPantalla;

  // true si este vencimiento gana la carrera y debe proceder a mostrar
  // PantallaAlarma; false si otro camino ya se está ocupando de este MISMO
  // vencimiento (rutinaId + venceEn exactos).
  bool marcarVencimientoTemporizadorSiNuevo(String rutinaId, DateTime venceEn) {
    final actual = _vencimientoTemporizadorEnPantalla;
    if (actual != null && actual.rutinaId == rutinaId && actual.venceEn == venceEn) {
      return false;
    }
    _vencimientoTemporizadorEnPantalla = (rutinaId: rutinaId, venceEn: venceEn);
    return true;
  }

  void liberarVencimientoTemporizadorEnPantalla() {
    _vencimientoTemporizadorEnPantalla = null;
  }

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
      final String? payload = details.notificationResponse?.payload;
      if (payload != null) {
        final partes = payload.split('|');
        if (payload.startsWith('alarma|') && partes.length >= 8 && partes[5] == 'temporizador') {
          huboNavegacionTemporizadorAlIniciar = true;
        }
        _manejarNavegacionAlarma(payload);
      }
    }

    if (Platform.isAndroid) {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
    }
  }

  // El prefijo 'alarma|' también lo lee MainActivity.kt (nativo) de forma
  // síncrona en onCreate/onNewIntent, para activar showWhenLocked/
  // turnScreenOn antes de que el engine de Flutter llegue a correr este
  // método. Si este prefijo cambia, hay que replicarlo allá.
  void _manejarNavegacionAlarma(String payload) {
    if (payload.startsWith('alarma|')) {
      final partes = payload.split('|');
      int id = 0;
      String titulo = '';
      String cuerpo = '';
      int iconoCode = 0;
      String? rutinaIdTemporizador;
      DateTime? venceEnTemporizador;

      // Rama del temporizador de rutina: va ANTES del catch-all genérico de
      // partes.length >= 5 porque esta también lo cumple (siempre trae 8
      // partes), pero necesita el rutinaId y el venceEn extra: el rutinaId
      // para que PantallaAlarma pueda llamar a toggleCompletada al
      // confirmar (ninguna otra alarma completa nada por sí sola), y
      // venceEn para identificar el vencimiento CONCRETO ante el guard
      // anti-duplicado (ver marcarVencimientoTemporizadorSiNuevo) que
      // también consultan el reconciliador de arranque y el listener en
      // vivo -- sin él, este camino no podría coordinarse con esos otros
      // dos para el mismo vencimiento.
      if (partes.length >= 8 && partes[5] == 'temporizador') {
        id = int.tryParse(partes[1]) ?? 0;
        titulo = partes[2];
        cuerpo = partes[3];
        iconoCode = int.tryParse(partes[4]) ?? 0;
        rutinaIdTemporizador = partes[6];
        venceEnTemporizador = DateTime.tryParse(partes[7]);
      } else if (partes.length >= 5) {
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

      // Guard anti-duplicado: si el reconciliador de arranque o el listener
      // en vivo ya se están ocupando de este MISMO vencimiento (rutinaId +
      // venceEn exactos), no apilar una segunda PantallaAlarma encima. Si
      // venceEnTemporizador no pudo parsearse (payload corrupto o de una
      // versión anterior sin este campo), se deja pasar sin guard: peor
      // caso, una PantallaAlarma duplicada, nunca perder la única
      // confirmación disponible.
      final bool bloqueadoPorOtroCamino = rutinaIdTemporizador != null &&
          venceEnTemporizador != null &&
          !marcarVencimientoTemporizadorSiNuevo(rutinaIdTemporizador, venceEnTemporizador);
      if (bloqueadoPorOtroCamino) return;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PantallaAlarma(
              idAlarma: id,
              titulo: titulo,
              cuerpo: cuerpo,
              iconoCode: iconoCode,
              rutinaIdTemporizador: rutinaIdTemporizador,
            ),
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
      final horas = tarea.horasEstimadas!;

      // --- NOTIFICACIONES DE CAMBIO DE NIVEL DE URGENCIA AUTOMÁTICA ---
      // Los umbrales son los mismos que usa Tarea.urgencia (2x, 1.5x y 1x las
      // horas estimadas antes del límite), así que el momento exacto en que
      // "ahora" cruza cada umbral es el momento en que el nivel sube.
      final momentoMedio = tarea.fechaLimite!.subtract(Duration(minutes: (horas * 2 * 60).round()));
      if (momentoMedio.isAfter(ahoraReal)) {
        final tzMedio = ahoraTz.add(momentoMedio.difference(ahoraReal));
        await _programarNotificacion(idBase + 3, '📊 Urgencia subió a Media',
          'La urgencia de "${tarea.titulo}" cambió a Media. Quedan ${_formatoHorasRestantes(horas * 2)}.', tzMedio,
          esAlarmaFullScreen: false,
          esInsistente: false
        );
      }

      final momentoAlto = tarea.fechaLimite!.subtract(Duration(minutes: (horas * 1.5 * 60).round()));
      if (momentoAlto.isAfter(ahoraReal)) {
        final tzAlto = ahoraTz.add(momentoAlto.difference(ahoraReal));
        await _programarNotificacion(idBase + 4, '📈 Urgencia subió a Alta',
          'La urgencia de "${tarea.titulo}" cambió a Alta. Quedan ${_formatoHorasRestantes(horas * 1.5)}.', tzAlto,
          esAlarmaFullScreen: false,
          esInsistente: false
        );
      }

      final fechaUrgencia = tarea.fechaLimite!.subtract(Duration(minutes: (horas * 60).round()));
      if (fechaUrgencia.isAfter(ahoraReal)) {
        final tzUrgencia = ahoraTz.add(fechaUrgencia.difference(ahoraReal));
        await _programarNotificacion(idBase, '🚀 Urgencia subió a Muy alta',
          'Deberías empezar "${tarea.titulo}" ahora. Quedan ${_formatoHorasRestantes(horas)}.', tzUrgencia,
          esAlarmaFullScreen: usarPantallaCompleta,
          esInsistente: usarLoopInsistente
        );
      }
    } else if (tarea.tipoRecurrencia != TipoRecurrencia.ninguna && tarea.intervalo != null) {
      // --- NOTIFICACIONES DE CAMBIO DE NIVEL DE URGENCIA POR RECURRENCIA ---
      // Sin horas estimadas, Tarea.urgencia usa el intervalo de repetición
      // como referencia (50%, 25% y 10% del intervalo antes del límite); acá
      // se programan las mismas notificaciones en esos mismos momentos.
      final horasIntervalo = (tarea.tipoRecurrencia == TipoRecurrencia.dias ? tarea.intervalo! : tarea.intervalo! * 30) * 24;

      final momentoMedio = tarea.fechaLimite!.subtract(Duration(minutes: (horasIntervalo * 0.50 * 60).round()));
      if (momentoMedio.isAfter(ahoraReal)) {
        final tzMedio = ahoraTz.add(momentoMedio.difference(ahoraReal));
        await _programarNotificacion(idBase + 3, '📊 Urgencia subió a Media',
          'La urgencia de "${tarea.titulo}" cambió a Media.', tzMedio,
          esAlarmaFullScreen: false,
          esInsistente: false
        );
      }

      final momentoAlto = tarea.fechaLimite!.subtract(Duration(minutes: (horasIntervalo * 0.25 * 60).round()));
      if (momentoAlto.isAfter(ahoraReal)) {
        final tzAlto = ahoraTz.add(momentoAlto.difference(ahoraReal));
        await _programarNotificacion(idBase + 4, '📈 Urgencia subió a Alta',
          'La urgencia de "${tarea.titulo}" cambió a Alta.', tzAlto,
          esAlarmaFullScreen: false,
          esInsistente: false
        );
      }

      final fechaUrgencia = tarea.fechaLimite!.subtract(Duration(minutes: (horasIntervalo * 0.10 * 60).round()));
      if (fechaUrgencia.isAfter(ahoraReal)) {
        final tzUrgencia = ahoraTz.add(fechaUrgencia.difference(ahoraReal));
        await _programarNotificacion(idBase, '🚀 Urgencia subió a Muy alta',
          'Deberías atender "${tarea.titulo}" ahora.', tzUrgencia,
          esAlarmaFullScreen: usarPantallaCompleta,
          esInsistente: usarLoopInsistente
        );
      }
    }
  }

  // Convierte horas (con decimales) a un texto legible tipo "2 h 30 min".
  String _formatoHorasRestantes(double horas) {
    final totalMinutos = (horas * 60).round();
    final h = totalMinutos ~/ 60;
    final m = totalMinutos % 60;
    if (h > 0 && m > 0) return '$h h $m min';
    if (h > 0) return '$h h';
    return '$m min';
  }

  Future<void> _programarNotificacion(int id, String titulo, String body, tz.TZDateTime fechaSistema, {required bool esAlarmaFullScreen, required bool esInsistente}) async {
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
          ? AndroidNotificationDetails(canalDinamicoId, 'Alarmas Urgentes', 
              importance: Importance.max, priority: Priority.max, color: const Color(0xFF276749), fullScreenIntent: true, 
              playSound: true, sound: RawResourceAndroidNotificationSound(sonidoElegido),
              additionalFlags: flags != null ? Int32List.fromList(flags) : null)
          : AndroidNotificationDetails(canalDinamicoId, 'Recordatorios', 
              importance: Importance.high, priority: Priority.high, color: const Color(0xFF276749), fullScreenIntent: false,
              playSound: true, sound: RawResourceAndroidNotificationSound(sonidoElegido));

      await _plugin.zonedSchedule(
        id, titulo, body, fechaSistema,
        NotificationDetails(android: detalles),
        androidScheduleMode: AndroidScheduleMode.alarmClock, 
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        // Prefijo 'alarma|' también leído por MainActivity.kt (nativo).
        payload: esAlarmaFullScreen ? 'alarma|$id|$titulo|$body' : null,
      );
    } catch (e) {
      _logErrorAlarma('_programarNotificacion (tarea id=$id)', e);
    }
  }

  Future<void> programarAlertaRutina({
    required int id, required String titulo, required String body, 
    required DateTime fechaVisual, 
    int? iconoCode, 
    bool esAlarmaFullScreen = true, bool esInsistente = true
  }) async {
    // Antes usaba tz.getLocation('America/Mexico_City') hardcodeado en vez
    // de tz.local (la zona horaria real detectada en init()): en cualquier
    // dispositivo fuera de esa zona, esto desalineaba sistemáticamente la
    // hora a la que realmente sonaba cada alarma de rutina.
    final tz.TZDateTime fechaSistema = tz.TZDateTime.from(fechaVisual, tz.local);
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

      // Prefijo 'alarma|' también leído por MainActivity.kt (nativo).
      final String payloadData = esAlarmaFullScreen ? 'alarma|$id|$titulo|$body|${iconoCode ?? 0}' : '';

      await _plugin.zonedSchedule(
        id, titulo, body, fechaSistema,
        NotificationDetails(android: detalles),
        androidScheduleMode: AndroidScheduleMode.alarmClock, 
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: esAlarmaFullScreen ? payloadData : null, 
        // ============================================================
        // FIX: se eliminó matchDateTimeComponents.
        // Antes, este parámetro le pedía a Android que reprogramara
        // automáticamente esta alarma cada semana, a nivel de sistema
        // operativo, de forma independiente a nuestro código Dart.
        //
        // Esto es lo que causaba que cancel() fallara de forma
        // silenciosa e inconsistente (comportamiento documentado como
        // problemático en el plugin flutter_local_notifications con
        // notificaciones recurrentes vía matchDateTimeComponents).
        //
        // Ya NO lo necesitamos: nuestro propio código en
        // rutina_provider.dart (_gestionarNotificacionesRutina) ya
        // recalcula y reprograma la siguiente ocurrencia cada vez que
        // se marca completa, se edita, o se abre la app. Ahora cada
        // llamada a zonedSchedule es una alarma de UNA SOLA vez, sin
        // ambigüedad para Android sobre si debe o no recrearla después
        // de cancelarla.
        // ============================================================
      );
    } catch (e) {
       _logErrorAlarma('programarAlertaRutina (id=$id)', e);
    }
  }

  // ============================================================
  // Notificación ongoing del temporizador de rutina
  // ------------------------------------------------------------
  // Cuenta atrás NATIVA: when = epoch millis de venceEn, usesChronometer +
  // chronometerCountDown hacen que sea Android quien la actualiza segundo a
  // segundo, no la app (que ya no necesita correr para que se vea correcta).
  // ongoing:true la hace no descartable con un swipe. Sin actions: no hay
  // botones. Importance/priority baja y silent:true porque es puramente
  // informativa — no debe interrumpir con sonido ni heads-up cada vez que
  // se (re)muestra.
  // ============================================================
  Future<void> mostrarNotificacionOngoingTemporizador({
    required String titulo,
    required DateTime venceEn,
  }) async {
    try {
      final AndroidNotificationDetails detalles = AndroidNotificationDetails(
        _canalTemporizadorRutinaId,
        'Temporizador de rutina',
        channelDescription: 'Cuenta atrás del temporizador activo de una rutina.',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        silent: true,
        when: venceEn.millisecondsSinceEpoch,
        usesChronometer: true,
        chronometerCountDown: true,
      );
      await _plugin.show(
        idOngoingTemporizadorRutina,
        titulo,
        'Temporizador en curso',
        NotificationDetails(android: detalles),
      );
    } catch (e) {
      _logErrorAlarma('mostrarNotificacionOngoingTemporizador', e);
    }
  }

  Future<void> cancelarNotificacionOngoingTemporizador() async {
    try {
      await _plugin.cancel(idOngoingTemporizadorRutina);
    } catch (_) {
      // Ignorar: si ya no existía, no es un error real.
    }
  }

  // ============================================================
  // Alarma de vencimiento del temporizador de rutina
  // ------------------------------------------------------------
  // Alarma de UNA SOLA ocurrencia (AndroidScheduleMode.alarmClock, mismo
  // esquema que programarAlertaRutina) programada en el instante en que el
  // temporizador arranca, para el instante exacto en que vence: así
  // sobrevive al cierre de la app -- la cuenta la lleva Android, no un
  // Timer de Dart. ID fijo 999998 (ver idOngoingTemporizadorRutina arriba
  // sobre por qué un ID fijo alcanza y por qué no colisiona con nada más).
  //
  // Payload con rama propia ('temporizador'): a diferencia de
  // programarAlertaRutina, PantallaAlarma necesita el rutinaId para poder
  // llamar a toggleCompletada al confirmar (ver _manejarNavegacionAlarma) --
  // ninguna otra alarma de este archivo completa nada por sí sola.
  // ============================================================
  Future<void> programarAlarmaVencimientoTemporizador({
    required String rutinaId,
    required String rutinaTitulo,
    required int iconoCode,
    required DateTime venceEn,
  }) async {
    final tz.TZDateTime fechaSistema = tz.TZDateTime.from(venceEn, tz.local);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sonidoAlarma = prefs.getString('sonido_alarma') ?? 'default_alarma';
      final canalDinamicoId = '${canalAlarmasId}_$sonidoAlarma';

      const String titulo = 'Temporizador terminado';
      final String cuerpo = 'Confirma que terminaste "$rutinaTitulo"';

      // Prefijo 'alarma|' también leído por MainActivity.kt (nativo), que
      // solo mira ese prefijo y no cuenta partes, así que agregar venceEn
      // al final es seguro. Va acá (y no solo en el estado persistido) para
      // que _manejarNavegacionAlarma pueda identificar el vencimiento
      // CONCRETO ante el guard anti-duplicado sin depender de leer
      // temporizadorRutinaProvider (esta clase no tiene acceso al
      // ProviderContainer, ver notas de la sección del guard más arriba).
      final String payload =
          'alarma|$idAlarmaVencimientoTemporizadorRutina|$titulo|$cuerpo|$iconoCode|temporizador|$rutinaId|${venceEn.toIso8601String()}';

      await _plugin.zonedSchedule(
        idAlarmaVencimientoTemporizadorRutina,
        titulo,
        cuerpo,
        fechaSistema,
        NotificationDetails(
          android: AndroidNotificationDetails(
            canalDinamicoId,
            'Alarmas Urgentes',
            importance: Importance.max,
            priority: Priority.max,
            color: const Color(0xFF276749),
            fullScreenIntent: true,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(sonidoAlarma),
            additionalFlags: Int32List.fromList(<int>[4]),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      _logErrorAlarma('programarAlarmaVencimientoTemporizador (rutina=$rutinaId)', e);
    }
  }

  Future<void> cancelarAlarmaVencimientoTemporizador() async {
    try {
      await _plugin.cancel(idAlarmaVencimientoTemporizadorRutina);
    } catch (_) {
      // Ignorar: si ya no existía, no es un error real.
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
    await _plugin.cancel(idBase + 3);
    await _plugin.cancel(idBase + 4);
  }

  // ============================================================
  // MÉTODO NUEVO: cancelarListaDeIds
  // ------------------------------------------------------------
  // Reemplaza la necesidad de "recalcular" qué IDs pertenecen a una
  // rutina. Recibe la lista EXACTA de IDs que se guardó en
  // rutina.notificacionesActivas y los cancela uno por uno.
  // Cada cancelación va en su propio try/catch para que, si un ID
  // ya no existe (por ejemplo porque ya sonó), no detenga la
  // cancelación de los demás.
  // ============================================================
  Future<void> cancelarListaDeIds(List<int> ids) async {
    for (final id in ids) {
      try {
        await _plugin.cancel(id);
      } catch (_) {
        // Ignoramos: si el ID ya no existía, no es un error real.
      }
    }
  }

  // Se mantienen por compatibilidad, pero YA NO se usan desde
  // rutina_provider.dart (que ahora usa cancelarListaDeIds con IDs
  // guardados explícitamente en el modelo Rutina).
  Future<void> cancelarAlertaRutina(int id) async {
    try { await _plugin.cancel(id); } catch (e) { // Ignorar
    }
  }

  // Ahora DEVUELVE la lista de IDs que efectivamente se programaron,
  // para que rutina_provider.dart pueda guardarlos y cancelarlos
  // con certeza más adelante.
  //
  // Bajado de 3 a 1 recordatorio por ocurrencia (ver nota extensa en
  // rutina_provider.dart, _resetCompletoNotificacionesRutina): Android
  // limita a 500 alarmas concurrentes por app, y con 3 recordatorios × 4
  // semanas de colchón × varias rutinas de varios días, ese límite se
  // alcanzaba en la práctica, dejando las semanas más lejanas sin
  // programar (silenciosamente) y por eso las rutinas dejaban de sonar
  // después de la primera semana.
  Future<List<int>> programarRecordatoriosSecundarios(int idBase, String titulo, DateTime horaAlarma) async {
    final prefs = await SharedPreferences.getInstance();
    final sonidoNota = prefs.getString('sonido_notificacion') ?? 'default_nota';
    final canalDinamicoId = '${canalRecordatoriosId}_$sonidoNota';

    final List<int> idsCreados = [];

    for (int i = 1; i <= 1; i++) {
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
          // FIX: se eliminó matchDateTimeComponents por el mismo motivo que
          // en programarAlertaRutina — evitar el bug de cancelación
          // inconsistente en alarmas recurrentes a nivel de Android.
        );
        // Solo anotamos el ID si la programación fue exitosa
        idsCreados.add(idRecordatorio);
      } catch (e) {
        _logErrorAlarma('programarRecordatoriosSecundarios (id=$idRecordatorio)', e);
      }
    }

    return idsCreados;
  }

  // Se mantiene por compatibilidad, pero YA NO se usa desde
  // rutina_provider.dart (reemplazado por cancelarListaDeIds).
  Future<void> cancelarRecordatoriosSecundarios(int idBase) async {
    for (int i = 1; i <= 3; i++) {
      await _plugin.cancel(idBase + (i * 10000));
    }
  }

  Future<void> posponerAlerta(int idAlarma, String titulo, String cuerpo, int minutos) async {
    await _plugin.cancel(idAlarma);

    final tz.TZDateTime nuevaHora = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutos));
    // Prefijo 'alarma|' también leído por MainActivity.kt (nativo).
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
            'Alarmas Urgentes',
            importance: Importance.max,
            priority: Priority.max,
            color: const Color(0xFF276749),
            fullScreenIntent: true,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(sonidoAlarma),
            additionalFlags: Int32List.fromList(<int>[4]),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: datosPayload,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error al posponer la alarma: $e');
    }
  }

  // --- BOMBA NUCLEAR PARA ALARMAS FANTASMAS ---
  Future<void> limpiarTodasLasAlarmasDelSistema() async {
    await _plugin.cancelAll();
  }
}