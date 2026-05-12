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

      final hoy = DateTime.now().toIso8601String().split('T')[0];
      state = rutinas.map((r) {
        // CORRECCIÓN CLAVE: Solo desmarcamos la rutina si cambió el día.
        // NO sobrescribimos la "fechaCompletada" aquí, porque necesitamos 
        // recordar en qué día se hizo realmente para calcular la racha.
        if (r.fechaCompletada != hoy && r.completada) {
          return r.copyWith(completada: false);
        }
        return r;
      }).toList();
    }
  }

  Future<void> _guardarRutinas() async {
    final prefs = await SharedPreferences.getInstance();
    final String rutinasCodificadas = jsonEncode(state.map((r) => r.toJson()).toList());
    await prefs.setString(_storageKey, rutinasCodificadas);
  }

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
    if (rutinaActualizada.completada) {
      final ahora = DateTime.now();
      final diaIndex = ahora.weekday - 1; 
      
      final int idBase = id.hashCode + diaIndex;
      NotificacionesService().cancelarRecordatoriosSecundarios(idBase);
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
    
    for (int i = 0; i < 7; i++) {
      NotificacionesService().cancelarAlertaRutina(id.hashCode + i);
      NotificacionesService().cancelarAlertaRutina(id.hashCode + i + 1000);
      NotificacionesService().cancelarRecordatoriosSecundarios(id.hashCode + i); 
    }
  }

  // --- FUNCIÓN PARA ROMPER RACHAS PERDIDAS ---
  void verificarRachasPerdidas() {
    final ahora = DateTime.now();
    // Quitamos horas y minutos para comparar solo los días exactos
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);

    bool huboCambios = false;

    state = state.map((rutina) {
      if (rutina.racha == 0 || rutina.fechaCompletada == null || rutina.fechaCompletada!.isEmpty) {
        return rutina;
      }

      DateTime ultima;
      try {
        ultima = DateTime.parse(rutina.fechaCompletada!);
      } catch (e) {
        return rutina; 
      }

      final fechaUltima = DateTime(ultima.year, ultima.month, ultima.day);

      // Si la completó hoy mismo o ayer, la racha está a salvo (el ciclo for no entrará)
      if (fechaUltima.isAtSameMomentAs(hoy)) {
         return rutina;
      }

      int diasPasados = hoy.difference(fechaUltima).inDays;
      bool perdioRacha = false;

      // Revisamos día por día hacia atrás, desde "ayer" hasta la fechaUltima
      for (int i = 1; i < diasPasados; i++) {
        final diaRevision = hoy.subtract(Duration(days: i));
        final diaSemana = diaRevision.weekday - 1; // 0 = Lunes, 6 = Domingo

        // Si encontramos un día que tocaba hacerla, y está vacío...
        if (rutina.horarios.containsKey(diaSemana)) {
          perdioRacha = true;
          break; // La racha se rompe inmediatamente
        }
      }

      if (perdioRacha) {
        huboCambios = true;
        return rutina.copyWith(racha: 0); 
      }

      return rutina;
    }).toList();

    if (huboCambios) {
      // CORRECCIÓN: Usamos la función de guardado real de este Provider
      _guardarRutinas(); 
    }
  }
}

final rutinaProvider = NotifierProvider<RutinaNotifier, List<Rutina>>(() {
  return RutinaNotifier();
});