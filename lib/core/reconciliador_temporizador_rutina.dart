import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rutina.dart';
import '../presentation/screens/pantalla_alarma.dart';
import '../providers/rutina_provider.dart';
import '../providers/temporizador_rutina_provider.dart';
import '../services/notificaciones_service.dart';

// ============================================================
// reconciliarTemporizadorRutinaAlArrancar — red de seguridad de arranque
// ------------------------------------------------------------
// Cubre el caso "el temporizador venció con la app cerrada y nadie lo
// confirmó": sin esto, el usuario abriría la app y vería la cuenta
// congelada en 00:00 para siempre, sin ninguna forma de completar la
// rutina (nunca se completa sola, ver diseño acordado) ni de que el
// checkbox vuelva a responder (manejarToqueCheckboxRutina lo sigue viendo
// como "temporizador activo para esta rutina"). Descartar sin preguntar
// NO es opción.
//
// Se llama UNA vez al arrancar (ver main.dart), después del primer frame
// (necesita navigatorKey ya montado). Si el temporizador ya venció, se
// empuja la MISMA PantallaAlarma que usa la alarma nativa, con
// esperarGuardLibreAlConfirmar:true.
// ============================================================
Future<void> reconciliarTemporizadorRutinaAlArrancar({
  required ProviderContainer container,
  required GlobalKey<NavigatorState> navigatorKey,
}) async {
  // Espera a que el loop de arranque de _cargarRutinasInterno termine del
  // todo ANTES de leer nada (diseño acordado): sin esto, el temporizador
  // podría apuntar a una rutina que esa lista todavía no terminó de cargar.
  // esperarGuardLibre en toggleCompletada (más abajo) es la red de
  // seguridad adicional para la carrera puntual con esa MISMA rutina.
  await container.read(rutinaProvider.notifier).esperarCargaInicial();

  final TemporizadorRutina? activo = container.read(temporizadorRutinaProvider);
  if (activo == null) return;

  // No vencido todavía: el tick que ya arrancó solo (ver
  // TemporizadorRutinaNotifier._cargarDesdeDisco) lo sigue mostrando en
  // vivo con normalidad -- nada que reconciliar acá.
  if (activo.segundosRestantes > 0) return;

  // La alarma nativa (fullScreenIntent / tap en la notificación) ya empujó
  // su propia PantallaAlarma para este mismo vencimiento en este mismo
  // arranque en frío -- ver NotificacionesService.init(). Empujar una
  // segunda acá duplicaría la pantalla para el mismo evento.
  if (NotificacionesService().huboNavegacionTemporizadorAlIniciar) return;

  Rutina? rutinaEncontrada;
  for (final r in container.read(rutinaProvider)) {
    if (r.id == activo.rutinaId) {
      rutinaEncontrada = r;
      break;
    }
  }

  // La rutina ya no existe (se borró mientras la app estaba cerrada):
  // eliminarRutina ya debería haber cancelado el temporizador en ese caso,
  // pero por si esta lectura cae en una ventana intermedia, no hay nada
  // que confirmar -- solo se limpia el temporizador huérfano.
  if (rutinaEncontrada == null) {
    await container.read(temporizadorRutinaProvider.notifier).cancelar();
    return;
  }
  final Rutina rutina = rutinaEncontrada;

  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => PantallaAlarma(
        idAlarma: NotificacionesService.idAlarmaVencimientoTemporizadorRutina,
        titulo: 'Temporizador terminado',
        cuerpo: 'Confirma que terminaste "${rutina.titulo}"',
        iconoCode: rutina.iconoCode,
        rutinaIdTemporizador: rutina.id,
        esperarGuardLibreAlConfirmar: true,
      ),
    ),
  );
}
