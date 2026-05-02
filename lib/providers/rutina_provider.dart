import 'dart:convert';
import 'package:flutter/material.dart'; // Necesario para TimeOfDay
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rutina.dart';
import '../services/notificaciones_service.dart'; // Importación del servicio

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

      // Comprobamos si cambió el día para reiniciar el checklist diario
      final hoy = DateTime.now().toIso8601String().split('T')[0];
      state = rutinas.map((r) {
        if (r.fechaCompletada != hoy) {
          return r.copyWith(completada: false, fechaCompletada: hoy);
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
    }

    // 2. Si la rutina no está activa, terminamos aquí
    if (!rutina.activa) return;

    // 3. Programamos los horarios activos
    final ahora = DateTime.now();

    rutina.horarios.forEach((diaIndex, hora) {
      final proximaFecha = _calcularProximaFecha(diaIndex, hora);
      final fechaUnaHoraAntes = proximaFecha.subtract(const Duration(hours: 1));

      // Aviso 1 hora antes (solo si aún no pasa)
      if (fechaUnaHoraAntes.isAfter(ahora)) {
        NotificacionesService().programarAlertaRutina(
          id: rutina.id.hashCode + diaIndex + 1000,
          titulo: 'Preparación de hábito',
          body: 'Tu hábito "${rutina.titulo}" comienza en 1 hora.',
          fechaVisual: fechaUnaHoraAntes,
        );
      }

      // Aviso a la hora exacta
      NotificacionesService().programarAlertaRutina(
        id: rutina.id.hashCode + diaIndex,
        titulo: '¡Es hora de tu hábito!',
        body: 'Es momento de: ${rutina.titulo}',
        fechaVisual: proximaFecha,
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
    _gestionarNotificacionesRutina(rutina); // Programar al crear
  }

  void editarRutina(Rutina rutinaEditada) {
    state = [
      for (final r in state)
        if (r.id == rutinaEditada.id) rutinaEditada else r,
    ];
    _guardarRutinas();
    _gestionarNotificacionesRutina(rutinaEditada); // Actualizar al editar
  }

  void toggleActiva(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(activa: !r.activa) else r,
    ];
    _guardarRutinas();
    
    final rutinaActualizada = state.firstWhere((r) => r.id == id);
    _gestionarNotificacionesRutina(rutinaActualizada); // Reprogramar o limpiar
  }

  void toggleCompletada(String id) {
    final hoy = DateTime.now().toIso8601String().split('T')[0];
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(
            completada: !r.completada,
            racha: !r.completada ? r.racha + 1 : (r.racha > 0 ? r.racha - 1 : 0),
            fechaCompletada: hoy,
          )
        else
          r,
    ];
    _guardarRutinas();
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
    
    // Al eliminar, borramos los rastros de sus alarmas
    for (int i = 0; i < 7; i++) {
      NotificacionesService().cancelarAlertaRutina(id.hashCode + i);
      NotificacionesService().cancelarAlertaRutina(id.hashCode + i + 1000);
    }
  }
}

final rutinaProvider = NotifierProvider<RutinaNotifier, List<Rutina>>(() {
  return RutinaNotifier();
});