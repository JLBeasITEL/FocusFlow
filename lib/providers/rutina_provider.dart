import 'dart:convert';
import 'package:flutter/material.dart'; // Necesario para TimeOfDay
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rutina.dart';
import '../services/notificaciones_service.dart'; 

class RutinaNotifier extends Notifier<List<Rutina>> {
  static const String _storageKey = 'lista_rutinas_v2';

  @override
  List<Rutina> build() {
    _cargarRutinas();
    return [];
  }

  // --- CALCULADORA DE PROGRESO DIARIO ---
  double get progresoDiario {
    final hoy = DateTime.now().weekday; // 1 = Lunes, 7 = Domingo
    
    // Filtramos para considerar solo las rutinas que tocan el día de hoy
    final rutinasDeHoy = state.where((r) => r.horarios.containsKey(hoy)).toList();
    
    if (rutinasDeHoy.isEmpty) return 0.0;
    
    // Contamos cuántas de esas están marcadas como completadas
    final completadas = rutinasDeHoy.where((r) => r.completada).length;
    
    return completadas / rutinasDeHoy.length;
  }

  Future<void> _cargarRutinas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rutinasJson = prefs.getString(_storageKey);

    if (rutinasJson != null) {
      final List<dynamic> listaDecodificada = jsonDecode(rutinasJson);
      final List<Rutina> rutinas = listaDecodificada.map((item) => Rutina.fromJson(item)).toList();

      final ahora = DateTime.now();
      final hoyStr = ahora.toIso8601String().split('T')[0];
      final hoyFecha = DateTime(ahora.year, ahora.month, ahora.day);
      
      bool huboCambios = false;

      state = rutinas.map((r) {
        Rutina rutinaActualizada = r;
        
        // 1. Desmarcar si es un nuevo día
        if (r.fechaCompletada != hoyStr && r.completada) {
          rutinaActualizada = rutinaActualizada.copyWith(completada: false);
          huboCambios = true;
        }

        // 2. Verificar rachas perdidas instantáneamente
        if (rutinaActualizada.racha > 0 && rutinaActualizada.fechaCompletada != null) {
          try {
            DateTime ultima = DateTime.parse(rutinaActualizada.fechaCompletada!);
            final fechaUltima = DateTime(ultima.year, ultima.month, ultima.day);
            
            if (!fechaUltima.isAtSameMomentAs(hoyFecha)) {
              int diasPasados = hoyFecha.difference(fechaUltima).inDays;
              for (int i = 1; i < diasPasados; i++) {
                final diaRevision = hoyFecha.subtract(Duration(days: i));
                if (rutinaActualizada.horarios.containsKey(diaRevision.weekday - 1)) {
                  // Rompió la racha
                  rutinaActualizada = rutinaActualizada.copyWith(racha: 0);
                  huboCambios = true;
                  break;
                }
              }
            }
          } catch (_) {}
        }
        return rutinaActualizada;
      }).toList();

      if (huboCambios) _guardarRutinas();

      // 3. Regenerar alarmas de forma segura al abrir la app
      for (var rutina in state) {
        if (rutina.activa) _gestionarNotificacionesRutina(rutina);
      }
    }
  }

  Future<void> _guardarRutinas() async {
    final prefs = await SharedPreferences.getInstance();
    final String rutinasCodificadas = jsonEncode(state.map((r) => r.toJson()).toList());
    await prefs.setString(_storageKey, rutinasCodificadas);
  }

  // --- LÓGICA DE NOTIFICACIONES PARA RUTINAS ---

  // NUEVO: Generador matemático de ID que NUNCA cambia entre sesiones
  int _generarIdNumerico(String id) {
    int hash = 0;
    for (int i = 0; i < id.length; i++) {
      hash = (31 * hash + id.codeUnitAt(i)) & 0x7FFFFFFF; // Límite seguro de 32-bits
    }
    return hash;
  }

  Future<void> _gestionarNotificacionesRutina(Rutina rutina) async {
    // Usamos nuestro generador constante
    final int baseId = _generarIdNumerico(rutina.id);
    final ahora = DateTime.now();

    // --- PRINTS DE DIAGNÓSTICO ---
    print("🔔 DEBUG: -- INICIANDO GESTIÓN DE ALARMAS --");
    print("🔔 DEBUG: Rutina: '${rutina.titulo}' | Estado completada: ${rutina.completada}");
    print("🔔 DEBUG: ID Base numérico: $baseId");

    // 1. APAGADO DE EMERGENCIA (Ahora con AWAIT)
    // Al usar await, obligamos a Flutter a pausarse hasta que Android confirme
    // que la alarma fue destruida. Esto evita las alarmas fantasma.
    for (final diaIndex in rutina.horarios.keys) {
      await NotificacionesService().cancelarAlertaRutina(baseId + diaIndex); 
      await NotificacionesService().cancelarAlertaRutina(baseId + diaIndex + 1000); 
      await NotificacionesService().cancelarRecordatoriosSecundarios(baseId + diaIndex); 
    }
    print("🔔 DEBUG: Alarmas previas canceladas exitosamente de la memoria.");

    // 2. Si la rutina no está activa, terminamos aquí
    if (!rutina.activa) {
      print("🔔 DEBUG: La rutina está inactiva. Proceso terminado.");
      return;
    }

    // 3. Programamos los horarios activos
    // Cambiamos el .forEach por un 'for in' para poder usar await adentro
    for (var entry in rutina.horarios.entries) {
      final diaIndex = entry.key;
      final hora = entry.value;
      final int idExacto = baseId + diaIndex; // El ID final de esta alarma
      
      DateTime proximaFecha = _calcularProximaFecha(diaIndex, hora);
      
      // Si ya se completó hoy, empujamos la fecha 7 días
      if (rutina.completada && 
          proximaFecha.year == ahora.year && 
          proximaFecha.month == ahora.month && 
          proximaFecha.day == ahora.day) {
        
        proximaFecha = proximaFecha.add(const Duration(days: 7));
        print("🔔 DEBUG: ⏩ Rutina de hoy marcada completa. ID: $idExacto reprogramado al: $proximaFecha");
      } else {
        print("🔔 DEBUG: ⏰ Programando ID: $idExacto para el: $proximaFecha");
      }

      final fechaUnaHoraAntes = proximaFecha.subtract(const Duration(hours: 1));
      
      // Aviso 1 hora antes (Con AWAIT)
      if (fechaUnaHoraAntes.isAfter(ahora)) {
        await NotificacionesService().programarAlertaRutina(
          id: idExacto + 1000,
          titulo: 'Preparación de hábito',
          body: 'Tu hábito "${rutina.titulo}" comienza en 1 hora.',
          fechaVisual: fechaUnaHoraAntes,
          iconoCode: rutina.iconoCode,
          esAlarmaFullScreen: false,
          esInsistente: false,
        );
      }

      // Aviso a la hora exacta (Con AWAIT)
      await NotificacionesService().programarAlertaRutina(
        id: idExacto,
        titulo: '¡Es hora de tu hábito!',
        body: 'Es momento de: ${rutina.titulo}',
        fechaVisual: proximaFecha,
        iconoCode: rutina.iconoCode,
        esAlarmaFullScreen: true,
        esInsistente: true,
      );

      // Sembramos los avisos secundarios (Con AWAIT)
      await NotificacionesService().programarRecordatoriosSecundarios(
        idExacto,
        rutina.titulo,
        proximaFecha,
      );
    }
    print("🔔 DEBUG: -- FINALIZÓ LA PROGRAMACIÓN CON ÉXITO --");
  }

  DateTime _calcularProximaFecha(int diaSemana, TimeOfDay hora) {
    final ahora = DateTime.now();
    int targetWeekday = diaSemana + 1; // Dart: 1=Lunes, 7=Domingo

    DateTime fecha = DateTime(ahora.year, ahora.month, ahora.day, hora.hour, hora.minute);

    // Sumar días si la fecha ya pasó en esta semana o si es hoy pero la hora ya pasó
    while (fecha.weekday != targetWeekday || fecha.isBefore(ahora)) {
      fecha = fecha.add(const Duration(days: 1));
    }
    return fecha;
  }

  // --- MÉTODOS DE ACCIÓN ---

  Future<void> addRutina(Rutina rutina) async {
  state = [...state, rutina];
  _guardarRutinas();
  await _gestionarNotificacionesRutina(rutina);
}

Future<void> editarRutina(Rutina rutinaEditada) async {
  state = [
    for (final r in state)
      if (r.id == rutinaEditada.id) rutinaEditada else r,
  ];
  _guardarRutinas();
  await _gestionarNotificacionesRutina(rutinaEditada);
}

Future<void> toggleActiva(String id) async {
  state = [
    for (final r in state)
      if (r.id == id) r.copyWith(activa: !r.activa) else r,
  ];
  _guardarRutinas();
  
  final rutinaActualizada = state.firstWhere((r) => r.id == id);
  await _gestionarNotificacionesRutina(rutinaActualizada);
}

  Future<void> toggleCompletada(String id) async {
  final hoy = DateTime.now().toIso8601String().split('T')[0];
  state = [
    for (final r in state)
      if (r.id == id)
        r.copyWith(
          completada: !r.completada,
          racha: !r.completada ? r.racha + 1 : (r.racha > 0 ? r.racha - 1 : 0),
          fechaCompletada: !r.completada ? hoy : null,
        )
      else
        r,
  ];
  _guardarRutinas();

  final rutinaActualizada = state.firstWhere((r) => r.id == id);
  await _gestionarNotificacionesRutina(rutinaActualizada); // <- await aquí
}

  Future<void> resincronizarTodasLasAlarmas() async {
    for (final rutina in state) {
      // Solo reprogramamos si el hábito está encendido
      if (rutina.activa) {
        await _gestionarNotificacionesRutina(rutina);
      }
    }
  }

  void incrementarRacha(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(racha: r.racha + 1) else r,
    ];
    _guardarRutinas();
  }

  void eliminarRutina(String id) {
    state = state.where((r) => r.id != id).toList();
    _guardarRutinas();
    
    // Actualizado con el ID seguro
    final int baseId = _generarIdNumerico(id);
    for (int i = 0; i < 7; i++) {
      NotificacionesService().cancelarAlertaRutina(baseId + i);
      NotificacionesService().cancelarAlertaRutina(baseId + i + 1000);
      NotificacionesService().cancelarRecordatoriosSecundarios(baseId + i); 
    }
  }

  
}

final rutinaProvider = NotifierProvider<RutinaNotifier, List<Rutina>>(() {
  return RutinaNotifier();
});