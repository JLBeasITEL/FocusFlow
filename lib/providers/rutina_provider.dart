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
  // --- LÓGICA DE NOTIFICACIONES PARA RUTINAS ---
  Future<void> _gestionarNotificacionesRutina(Rutina rutina) async {
    // 1. Limpiamos cualquier alarma previa de esta rutina (los 7 días)
    for (int i = 0; i < 7; i++) {
      NotificacionesService().cancelarAlertaRutina(rutina.id.hashCode + i); // Exacta
      NotificacionesService().cancelarAlertaRutina(rutina.id.hashCode + i + 1000); // 1 hora antes
      NotificacionesService().cancelarRecordatoriosSecundarios(rutina.id.hashCode + i); // Limpiamos los secundarios
    }

    // 2. Si la rutina no está activa, terminamos aquí
    if (!rutina.activa) return;

    // 3. Programamos los horarios activos
    final ahora = DateTime.now();

    rutina.horarios.forEach((diaIndex, hora) {
      final proximaFecha = _calcularProximaFecha(diaIndex, hora);
      
      // --- CORRECCIÓN: EVITAR NOTIFICACIONES FANTASMA ---
      // Si el hábito ya se completó, no programamos las alarmas correspondientes al día de hoy.
      if (rutina.completada && 
          proximaFecha.year == ahora.year && 
          proximaFecha.month == ahora.month && 
          proximaFecha.day == ahora.day) {
        return; // Salta a la siguiente iteración (actúa como un 'continue')
      }
      // --------------------------------------------------

      final fechaUnaHoraAntes = proximaFecha.subtract(const Duration(hours: 1));

      // Aviso 1 hora antes
      if (fechaUnaHoraAntes.isAfter(ahora)) {
        NotificacionesService().programarAlertaRutina(
          id: rutina.id.hashCode + diaIndex + 1000,
          titulo: 'Preparación de hábito',
          body: 'Tu hábito "${rutina.titulo}" comienza en 1 hora.',
          fechaVisual: fechaUnaHoraAntes,
          iconoCode: rutina.iconoCode,
          esAlarmaFullScreen: false,
          esInsistente: false,
        );
      }

      // Aviso a la hora exacta
      NotificacionesService().programarAlertaRutina(
        id: rutina.id.hashCode + diaIndex,
        titulo: '¡Es hora de tu hábito!',
        body: 'Es momento de: ${rutina.titulo}',
        fechaVisual: proximaFecha,
        iconoCode: rutina.iconoCode,
        esAlarmaFullScreen: true,
        esInsistente: true,
      );

      // Sembramos los avisos para las siguientes 3 horas si no se completa
      NotificacionesService().programarRecordatoriosSecundarios(
        rutina.id.hashCode + diaIndex,
        rutina.titulo,
        proximaFecha,
      );
    });
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

  void addRutina(Rutina rutina) {
    state = [...state, rutina];
    _guardarRutinas();
    _gestionarNotificacionesRutina(rutina); 
  }

  void editarRutina(Rutina rutinaEditada) {
    state = [
      for (final r in state)
        if (r.id == rutinaEditada.id) rutinaEditada else r,
    ];
    _guardarRutinas();
    _gestionarNotificacionesRutina(rutinaEditada); 
  }

  void toggleActiva(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(activa: !r.activa) else r,
    ];
    _guardarRutinas();
    
    final rutinaActualizada = state.firstWhere((r) => r.id == id);
    _gestionarNotificacionesRutina(rutinaActualizada); 
  }

  void toggleCompletada(String id) {
    final hoy = DateTime.now().toIso8601String().split('T')[0];
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(
            completada: !r.completada,
            racha: !r.completada ? r.racha + 1 : (r.racha > 0 ? r.racha - 1 : 0),
            // CORRECCIÓN: Si marca la tarea, guarda hoy. Si la desmarca (error del usuario), la borramos.
            fechaCompletada: !r.completada ? hoy : null,
          )
        else
          r,
    ];
    _guardarRutinas();

    final rutinaActualizada = state.firstWhere((r) => r.id == id);
    _gestionarNotificacionesRutina(rutinaActualizada);
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
    
    for (int i = 0; i < 7; i++) {
      NotificacionesService().cancelarAlertaRutina(id.hashCode + i);
      NotificacionesService().cancelarAlertaRutina(id.hashCode + i + 1000);
      NotificacionesService().cancelarRecordatoriosSecundarios(id.hashCode + i); 
    }
  }

  
}

final rutinaProvider = NotifierProvider<RutinaNotifier, List<Rutina>>(() {
  return RutinaNotifier();
});