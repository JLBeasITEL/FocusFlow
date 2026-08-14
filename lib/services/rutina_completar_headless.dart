import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/rutina_provider.dart';
import 'notificaciones_service.dart';

// Completa una rutina desde el checkbox del widget de Rutinas SIN abrir la
// app: corre en el isolate headless que home_widget levanta para atender un
// HomeWidgetBackgroundIntent. Ese isolate SÍ es un FlutterEngine real (no un
// Dart isolate pelado), así que los plugins funcionan, pero nunca ejecuta
// main.dart — no hereda el ProviderContainer ni el NotificacionesService ya
// inicializados de la app en primer plano: ambos se arman frescos y
// descartables solo para esta operación.
//
// Se llama al MISMO RutinaNotifier.toggleCompletada que usa rutina_card.dart
// (con toda su lógica de racha/monedas/cancelación de notificaciones
// intacta) en vez de reimplementar ese estado a mano acá — ver el
// historial de bugs de notificaciones de rutinas antes de tocar esto.
Future<void> completarRutinaHeadless(String id) async {
  // NotificacionesService().init() nunca corrió en este isolate; sin esto,
  // toggleCompletada podría fallar al cancelar la notificación de hoy
  // (justo el tipo de desincronización que ya causó bugs antes).
  await NotificacionesService().init(GlobalKey<NavigatorState>());

  // Contenedor propio y descartable: RutinaNotifier.build() dispara
  // _cargarRutinas() sin esperarlo, así que el state arranca en [] y se
  // llena de forma asíncrona — se espera (con tope de 5s) a que la rutina
  // buscada aparezca antes de completarla.
  final container = ProviderContainer();
  try {
    final limite = DateTime.now().add(const Duration(seconds: 5));
    while (!container.read(rutinaProvider).any((r) => r.id == id)) {
      if (DateTime.now().isAfter(limite)) return;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await container.read(rutinaProvider.notifier).toggleCompletada(id);
  } finally {
    container.dispose();
  }
}
