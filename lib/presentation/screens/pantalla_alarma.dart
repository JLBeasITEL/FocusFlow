import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../providers/tema_provider.dart'; 
import '../../services/notificaciones_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/home_screen.dart';

// Se cambia a ConsumerStatefulWidget únicamente para permitir la animación del slider
class PantallaAlarma extends ConsumerStatefulWidget {
  final int idAlarma;
  final String titulo;
  final String cuerpo;
  final int iconoCode;

  const PantallaAlarma({
    super.key,
    required this.idAlarma,
    required this.titulo,
    required this.cuerpo,
    required this.iconoCode,
  });

  @override
  ConsumerState<PantallaAlarma> createState() => _PantallaAlarmaState();
}

class _PantallaAlarmaState extends ConsumerState<PantallaAlarma> {
  // Configuración del slider de posponer
  final List<int> _opcionesMinutos = [5, 10, 15, 30, 45, 60];
  int _snoozeIndex = 0; 
  bool _isPosponeSliderVisible = false; 

  // --- 1. ENCENDER LA PANTALLA AL INICIAR ---
  @override
  void initState() {
    super.initState();
    // Obliga a la pantalla a mantenerse encendida mientras este widget exista
    WakelockPlus.enable(); 
  }

  // --- 2. PERMITIR QUE SE APAGUE AL CERRAR ---
  @override
  void dispose() {
    // Libera el bloqueo para no gastar batería cuando la alarma se cierre
    WakelockPlus.disable(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Escuchamos el tema actual configurado en la app
    final temaActual = ref.watch(temaProvider);

    // 2. Definimos las paletas de colores según el tema
    Color bgColor;
    Color textColor;
    Color accentColor;
    Color snoozeColor; // Color para el botón/slider de posponer

    switch (temaActual) {
      case TemaApp.zenClasico:
        bgColor = const Color(0xFFF4F1EA); 
        textColor = const Color(0xFF4A4A4A);
        accentColor = const Color(0xFF7B9E87); 
        snoozeColor = const Color(0xFF5A7A65); 
        break;
      case TemaApp.brisaMarina:
        bgColor = const Color(0xFFE8F1F5); 
        textColor = const Color(0xFF2C3E50);
        accentColor = const Color(0xFF5D9B9B); 
        snoozeColor = const Color(0xFF1B4965); 
        break;
      case TemaApp.atardecerMinimalista:
        bgColor = const Color(0xFFFFF5E6); 
        textColor = const Color(0xFF5C4A3D);
        accentColor = const Color(0xFFE07A5F); 
        snoozeColor = const Color(0xFFAC6B53); 
        break;
      case TemaApp.clasico:
      // --- NUEVA PALETA PARA EL TEMA CLÁSICO ---
        bgColor = Colors.white; // Fondo limpio como el HomeScreen
        textColor = Colors.black87; // Texto elegante oscuro
        accentColor = Colors.teal; // Acento principal de las tareas
        snoozeColor = Colors.teal.shade700; // Un verde/azulado oscuro para el botón posponer
        break;
    }

    const double sliderHeight = 64.0;
    const double handleDiameter = sliderHeight;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('TAREA PENDIENTE', 
                style: TextStyle(color: textColor.withValues(alpha: 0.6), letterSpacing: 3, fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 40),
              
              Icon(
                IconData(widget.iconoCode, fontFamily: 'MaterialIcons'), 
                size: 100, 
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
              
              const SizedBox(height: 80),
              
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
                      print('Error al detener la alarma: $e');
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}