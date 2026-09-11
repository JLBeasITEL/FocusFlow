import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rutina.dart';
import '../presentation/screens/pantalla_alarma.dart';
import '../providers/rutina_provider.dart';
import '../providers/temporizador_rutina_provider.dart';
import '../services/notificaciones_service.dart';

// ============================================================
// iniciarListenerTemporizadorRutina — ofrece la confirmación mientras la
// app sigue viva (primer plano y volver de segundo plano)
// ------------------------------------------------------------
// El reconciliador de arranque (reconciliador_temporizador_rutina.dart) solo
// corre UNA vez, al iniciar en frío -- deja dos huecos reales:
//   1. El temporizador vence con la app en PRIMER PLANO: nadie navega,
//      TemporizadorRutinaNotifier._tick() solo se detiene al llegar a 0.
//   2. Vence con la app en segundo plano pero VIVA (proceso no killeado), y
//      el usuario vuelve a ella sin tocar la notificación: no es un
//      arranque, así que el reconciliador nunca corre; main.dart solo hace
//      iniciarTick() en el resume.
//
// Este listener cubre AMBOS reaccionando al FLANCO "temporizadorRutinaProvider
// pasó a segundosRestantes <= 0", que ocurre en los dos casos: el tick en
// vivo llegando a cero (caso 1) y iniciarTick() recalculando contra venceEn
// al volver de segundo plano y descubriendo que ya venció (caso 2, ver
// TemporizadorRutinaNotifier.iniciarTick()/_recalcularContraVenceEn()). No
// reemplaza al reconciliador de arranque -- es un mecanismo ADICIONAL, y de
// hecho también reacciona a la carga inicial del propio arranque (la difierre
// desde disco puede resolver antes o después de que este listener se
// registre), por eso comparte el mismo guard anti-duplicado con él.
//
// Se llama UNA vez desde main(), lo antes posible (antes de runApp): un
// container.listen no reacciona a cambios de estado que ocurrieron ANTES de
// registrarse, así que cuanto antes se registre, menos ventana de pérdida
// hay contra la carga async del propio temporizador al arrancar.
// ============================================================
void iniciarListenerTemporizadorRutina({
  required ProviderContainer container,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  container.listen<TemporizadorRutina?>(
    temporizadorRutinaProvider,
    (previous, next) {
      if (next == null || next.segundosRestantes > 0) return;
      _ofrecerConfirmacionSiCorresponde(container: container, navigatorKey: navigatorKey, activo: next);
    },
  );
}

Future<void> _ofrecerConfirmacionSiCorresponde({
  required ProviderContainer container,
  required GlobalKey<NavigatorState> navigatorKey,
  required TemporizadorRutina activo,
}) async {
  // Guard anti-duplicado compartido con el reconciliador de arranque y con
  // tocar la notificación: si cualquiera de los tres ya se está ocupando de
  // este MISMO vencimiento (rutinaId + venceEn exactos), no hacer nada más.
  if (!NotificacionesService().marcarVencimientoTemporizadorSiNuevo(activo.rutinaId, activo.venceEn)) {
    return;
  }

  // Espera a que la carga inicial de rutinas termine (relevante solo si
  // este flanco es, de hecho, el de la carga en frío del propio arranque --
  // ver comentario de arriba): sin esto, una carrera con el loop de arranque
  // de rutina_provider.dart podría hacer creer que la rutina fue borrada
  // cuando en realidad todavía no terminó de cargar. Mismo resguardo que ya
  // usa el reconciliador de arranque.
  await container.read(rutinaProvider.notifier).esperarCargaInicial();

  Rutina? rutinaEncontrada;
  for (final r in container.read(rutinaProvider)) {
    if (r.id == activo.rutinaId) {
      rutinaEncontrada = r;
      break;
    }
  }

  if (rutinaEncontrada == null) {
    // Rutina borrada mientras tanto: nada que confirmar. No se va a mostrar
    // ninguna PantallaAlarma (que es quien normalmente libera el guard en
    // su dispose()), así que hay que liberarlo a mano acá.
    NotificacionesService().liberarVencimientoTemporizadorEnPantalla();
    await container.read(temporizadorRutinaProvider.notifier).cancelar();
    return;
  }
  final Rutina rutina = rutinaEncontrada;

  SchedulerBinding.instance.addPostFrameCallback((_) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PantallaAlarma(
          idAlarma: NotificacionesService.idAlarmaVencimientoTemporizadorRutina,
          titulo: 'Temporizador terminado',
          cuerpo: 'Confirma que terminaste "${rutina.titulo}"',
          iconoCode: rutina.iconoCode,
          rutinaIdTemporizador: rutina.id,
        ),
      ),
    );
  });
}
