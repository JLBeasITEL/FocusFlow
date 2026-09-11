import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../providers/tema_provider.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/temporizador_rutina_provider.dart';
import '../../services/notificaciones_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/home_screen.dart';

// Se cambia a ConsumerStatefulWidget únicamente para permitir la animación del slider
class PantallaAlarma extends ConsumerStatefulWidget {
  final int idAlarma;
  final String titulo;
  final String cuerpo;
  final int iconoCode;

  // Presente SOLO para la alarma de vencimiento del temporizador de rutina
  // (ver notificaciones_service.dart, rama 'temporizador' de
  // _manejarNavegacionAlarma). null para cualquier otra alarma (tareas,
  // rutinas por horario): esas nunca completan nada por sí solas, solo
  // apagan el sonido y vuelven a HomeScreen. Con un valor no-null,
  // "Entendido" además cancela el temporizador y llama a toggleCompletada
  // -- la única forma en que una rutina con temporizador queda completada
  // -- y no se ofrece "Posponer" (no tiene sentido posponer una
  // confirmación de vencimiento).
  final String? rutinaIdTemporizador;

  // Solo true cuando esta pantalla la empuja el reconciliador de arranque
  // (ver reconciliador_temporizador_rutina.dart), NUNCA cuando la empuja la
  // alarma nativa en vivo (diseño acordado: "solo el reconciliador pasa
  // true"). Se lo pasa tal cual a toggleCompletada -- ver ese parámetro
  // para el porqué: el reconciliador puede correr mientras el loop de
  // arranque de rutina_provider.dart todavía tiene esta rutina tomada.
  final bool esperarGuardLibreAlConfirmar;

  const PantallaAlarma({
    super.key,
    required this.idAlarma,
    required this.titulo,
    required this.cuerpo,
    required this.iconoCode,
    this.rutinaIdTemporizador,
    this.esperarGuardLibreAlConfirmar = false,
  });

  @override
  ConsumerState<PantallaAlarma> createState() => _PantallaAlarmaState();
}

class _PantallaAlarmaState extends ConsumerState<PantallaAlarma> {
  // Configuración del slider de posponer
  final List<int> _opcionesMinutos = [5, 10, 15, 30, 45, 60];
  int _snoozeIndex = 0;
  bool _isPosponeSliderVisible = false;

  // Canal nativo que permite mostrar esta pantalla sobre el bloqueo del
  // dispositivo SOLO mientras la alarma está visible. Ver MainActivity.kt.
  static const _canalAlarma = MethodChannel('com.beasdev.focusflow/alarm_screen');

  // --- 1. ENCENDER LA PANTALLA AL INICIAR ---
  @override
  void initState() {
    super.initState();
    // Obliga a la pantalla a mantenerse encendida mientras este widget exista
    WakelockPlus.enable();
    // Permite que esta pantalla se muestre encima del bloqueo (como una alarma normal)
    _canalAlarma.invokeMethod('showOverLockscreen').catchError((_) {});
  }

  // --- 2. PERMITIR QUE SE APAGUE AL CERRAR ---
  @override
  void dispose() {
    // Libera el bloqueo para no gastar batería cuando la alarma se cierre
    WakelockPlus.disable();
    // Restaura el comportamiento normal: la app vuelve a respetar el bloqueo
    _canalAlarma.invokeMethod('hideOverLockscreen').catchError((_) {});
    // Red de seguridad: si esta pantalla se desmonta por cualquier vía que no
    // sea "Entendido" (para la rama del temporizador, el PopScope de abajo ya
    // bloquea la única vía conocida -- el atrás -- pero esto cubre cualquier
    // otra forma de desmontaje presente o futura), la notificación de alarma
    // no debe quedar sonando sin nadie que la apague.
    FlutterLocalNotificationsPlugin().cancel(widget.idAlarma).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Escuchamos el tema actual configurado en la app
    final temaActual = ref.watch(temaProvider);

    // 2. Paleta de colores según el tema (fuente única en TemaColores)
    final Color bgColor = temaActual.colorFondoAlarma;
    final Color textColor = temaActual.colorTextoAlarma;
    final Color accentColor = temaActual.colorAcentoAlarma;
    final Color snoozeColor = temaActual.colorPosponerAlarma; // Color para el botón/slider de posponer

    const double sliderHeight = 64.0;
    const double handleDiameter = sliderHeight;

    // Interpolación entre el layout de portrait (alto disponible >= 600dp,
    // sin cambios respecto al diseño original) y una versión compacta para
    // landscape de teléfono (alto disponible <= 380dp), donde el ícono y los
    // dos espaciadores grandes se comprimen para que el botón "Entendido" y
    // el slider de posponer quepan sin salirse de la pantalla. El botón y el
    // slider mantienen sus 64dp fijos (son objetivos táctiles). El
    // SingleChildScrollView de abajo es la red de seguridad final para
    // cualquier caso extremo que ni así entre.
    const double alturaCompacta = 380.0;
    const double alturaCompleta = 600.0;

    // Bloquea el atrás SOLO en la alarma de vencimiento del temporizador de
    // rutina: "Entendido" es la única salida (diseño acordado, ver el
    // bloque de arriba), así que dejar salir por atrás sin pasar por ahí es
    // exactamente el estado colgado que este PopScope existe para evitar
    // (persistido en disco intacto, sin confirmar, y sin nada que vuelva a
    // ofrecer la confirmación hasta el próximo arranque de la app). Las
    // demás alarmas (tareas, rutinas por horario) no tienen nada pendiente
    // de confirmar, así que ahí el atrás se deja funcionar como siempre.
    return PopScope(
      canPop: widget.rutinaIdTemporizador == null,
      child: Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double t = ((constraints.maxHeight - alturaCompacta) / (alturaCompleta - alturaCompacta)).clamp(0.0, 1.0);
              final double tamanoIcono = 56.0 + (100.0 - 56.0) * t;
              final double espacioTrasLabel = 12.0 + (40.0 - 12.0) * t;
              final double espacioGrande = 16.0 + (80.0 - 16.0) * t;

              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.rutinaIdTemporizador != null ? 'TEMPORIZADOR TERMINADO' : 'TAREA PENDIENTE',
                style: TextStyle(color: textColor.withValues(alpha: 0.6), letterSpacing: 3, fontWeight: FontWeight.bold)
              ),
              SizedBox(height: espacioTrasLabel),

              Icon(
                IconData(widget.iconoCode, fontFamily: 'MaterialIcons'),
                size: tamanoIcono,
                color: accentColor
              ),
              const SizedBox(height: 20),
              
              Text(
                widget.titulo, 
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, color: textColor, fontWeight: FontWeight.bold)
              ),
              
              if (widget.cuerpo.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.cuerpo,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: textColor.withValues(alpha: 0.8)),
                ),
              ],
              
              SizedBox(height: espacioGrande),

              // --- BOTÓN ENTENDIDO (INTACTO SEGÚN TU CÓDIGO) ---
              // --- BOTÓN ENTENDIDO MODIFICADO ---
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () async {
                    // 1. Detenemos el sonido/notificación
                    try {
                      await FlutterLocalNotificationsPlugin().cancel(widget.idAlarma);
                    } catch (e) {
                      if (kDebugMode) debugPrint('Error al detener la alarma: $e');
                    }

                    // 1b. Alarma de vencimiento del temporizador de rutina:
                    // esta es la ÚNICA confirmación que existe para este
                    // flujo (nunca se completa sola, ver diseño acordado),
                    // así que acá es donde toggleCompletada finalmente se
                    // llama. fechaEfectiva usa el venceEn persistido (leído
                    // ANTES de cancelar, que lo borra) para que la rutina
                    // cuente para el día en que venció el temporizador, no
                    // el día en que el usuario llegó a tocar "Entendido".
                    final String? rutinaId = widget.rutinaIdTemporizador;
                    if (rutinaId != null) {
                      final activo = ref.read(temporizadorRutinaProvider);
                      final DateTime fechaEfectiva = (activo != null && activo.rutinaId == rutinaId)
                          ? activo.venceEn
                          : ref.read(relojProvider)();
                      await ref.read(temporizadorRutinaProvider.notifier).cancelar();
                      await ref.read(rutinaProvider.notifier).toggleCompletada(
                            rutinaId,
                            fechaEfectiva: fechaEfectiva,
                            esperarGuardLibre: widget.esperarGuardLibreAlConfirmar,
                          );
                    }

                    // 2. REEMPLAZO: En lugar de cerrar la app, forzamos abrir el HomeScreen
                    // Esto además evita que el usuario pueda volver a la alarma presionando "Atrás"
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const HomeScreen(),
                        ),
                        (Route<dynamic> route) => false, // Elimina pantallas previas
                      );
                    }
                  },
                  child: const Text(
                    'Entendido',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ),
              ),
              
              // Posponer no aplica a la alarma de vencimiento del
              // temporizador de rutina (diseño acordado: la única acción
              // ahí es confirmar). Se omite el bloque entero, no solo se
              // deshabilita, para no dejarle al usuario un control que no
              // hace nada.
              if (widget.rutinaIdTemporizador == null) ...[
              const SizedBox(height: 16),

              // --- NUEVO BOTÓN/SLIDER DE POSPONER CON COLORES DE TEMA ---
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: !_isPosponeSliderVisible
                    ? GestureDetector(
                        key: const ValueKey('unpressed_pospone'),
                        onTap: () => setState(() => _isPosponeSliderVisible = true),
                        child: Container(
                          width: double.infinity,
                          height: sliderHeight,
                          decoration: BoxDecoration(
                            color: snoozeColor, 
                            borderRadius: BorderRadius.circular(32),
                          ),
                          alignment: Alignment.center,
                          child: const Text('Posponer', 
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      )
                    : LayoutBuilder(
                        key: const ValueKey('pressed_slider'),
                        builder: (context, constraints) {
                          final totalWidth = constraints.maxWidth;
                          final availableTrackWidth = totalWidth - handleDiameter;
                          final maxIndex = _opcionesMinutos.length - 1;
                          final handleLeftPosition = availableTrackWidth * (_snoozeIndex / maxIndex);

                          return Container(
                            width: double.infinity,
                            height: sliderHeight,
                            decoration: BoxDecoration(
                              color: textColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Stack(
                              children: [
                                // Llenado de color en la pista del slider
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  height: sliderHeight,
                                  width: handleLeftPosition + (handleDiameter / 2),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: snoozeColor, 
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(32),
                                        bottomLeft: Radius.circular(32),
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Texto guía
                                Center(
                                  child: Opacity(
                                    opacity: 0.6,
                                    child: Text(
                                      'Desliza para posponer', 
                                      style: TextStyle(fontSize: 16, color: textColor)
                                    ),
                                  ),
                                ),
                                
                                // Asa interactiva
                                Positioned(
                                  left: handleLeftPosition,
                                  child: GestureDetector(
                                    onHorizontalDragUpdate: (details) {
                                      final normalizedPosition = (details.localPosition.dx / totalWidth).clamp(0.0, 1.0);
                                      final roundedIndex = (normalizedPosition * maxIndex).round().clamp(0, maxIndex);
                                      if (_snoozeIndex != roundedIndex) {
                                        setState(() => _snoozeIndex = roundedIndex);
                                      }
                                    },
                                    onHorizontalDragEnd: (details) async {
                                      final minutosFinales = _opcionesMinutos[_snoozeIndex];
                                      
                                      await FlutterLocalNotificationsPlugin().cancel(widget.idAlarma);
                                      
                                      await NotificacionesService().posponerAlerta(
                                        widget.idAlarma,
                                        widget.titulo,
                                        widget.cuerpo,
                                        minutosFinales
                                      );

                                      SystemNavigator.pop();
                                    },
                                    child: Container(
                                      width: handleDiameter,
                                      height: handleDiameter,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: snoozeColor),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${_opcionesMinutos[_snoozeIndex]} min',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              ],
              const SizedBox(height: 40),
            ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}